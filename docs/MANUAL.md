# Shaker user manual

A hands-on guide: from a hand-written bundle to a signed Distillery artifact restored, started and audited on a host. Every command and
output below was run for real (bash 5, Ubuntu 24.04, as root; the examples use a throw-away root so nothing outside it is touched). The
[reference documents](../README.md#documentation) stay the place to look up an option; this manual shows how the pieces fit.

| Part | Subject |
|---|---|
| [1](#1-the-model-in-five-minutes) | Bundle, root, state, parameters |
| [2](#2-setup) | Installing Shaker, `bootstrap`, `detect` |
| [3](#3-quick-start-without-distillery) | A hand-written bundle: install, run, verify, stop |
| [4](#4-parameters-rosetta) | One parameter, every dialect: precedence, secrets, files, errors |
| [5](#5-the-lifecycle) | `install`, `init` (templates, hooks), `run`, `stop`, `status` |
| [6](#6-packages-built-by-distillery) | Drift detection, parameter changes, systemd unit |
| [7](#7-artifacts-and-trust) | `restore`, pinned signers, `verify --files`, `up` |
| [8](#8-containers-and-kubernetes) | Images, PID 1, secrets |
| [9](#9-legacy-hosts) | systemd, `--daemon`, config files |
| [10](#10-tools) | `render`, `pkg`, `hooks`, `wait-for`, `detect` |
| [11](#11-troubleshooting) | Messages you will meet |
| [12](#12-cheat-sheet) | One page |

The matching guide for the build half is the [Distillery manual](https://github.com/bytehawks-org/distillery/blob/main/docs/MANUAL.md).

---

## 1. The model in five minutes

Shaker knows nothing about any application. It reads a **bundle**, a directory with a few small text files, and applies it:

| File in `<prefix>/.bytehawks/` | Says |
|---|---|
| `runtime.spec` | the service account, directories and modes, templates, hook directories, the command (an argv), stop signal, pid file, health check, required tools |
| `rosetta.map` | the parameters: canonical name, type, default, aliases, CLI flag, config-file key |
| `manifest.env` / `manifest.json` | identity (`BH_PKG_*`): name, version, recipe, platform, dependencies. `manifest.json` only has to exist |
| `assets/` | templates and hook scripts |
| `files.sha256`, `bundle.sha256(.asc)` | integrity and signature (optional, written by [Distillery](https://github.com/bytehawks-org/distillery)) |

Distillery produces bundles; so can you, by hand ([section 3](#3-quick-start-without-distillery)). Everything lives under one **root**,
`BH_ROOT` (`/opt/bytehawks` by default, `/opt/bh` is only a convenience symlink):

```
$BH_ROOT/<pkg>/                 application prefix, with .bytehawks/ = its bundle
$BH_ROOT/deps/.bytehawks/<lib>/ bundles of libraries
$BH_ROOT/etc/<pkg>/             legacy configuration files
$BH_ROOT/var/{lib/shaker,log,run}/   state (per package) + append-only events.log, logs, pid files
```

The verbs, in the order you use them:

| Verb | Does | Needs root |
|---|---|---|
| `install` | service user and group, directories with owner and mode, hook directories | yes (or `BH_SHAKER_ALLOW_NONROOT=true`, which skips users and ownership) |
| `init` | `pre_init` hooks → persistence → templates → `first_init` hooks (once) → `post_init` hooks → state | no |
| `run` | `init`, then `exec` the service (PID 1 in a container), dropping privileges to the service user | no |
| `stop`, `status`, `verify` | stop a `--daemon` service; show the record; read-only audit | no |
| `up` | `install` + `init` of the dependencies first, then of the package | as `install` |
| `restore` | unpack a Distillery artifact after checking hash, signature, platform and paths | as the target tree requires |

Logs go to **stderr**, results to **stdout**; `BH_SHAKER_QUIET=true` silences stderr.

## 2. Setup

Requirements: bash ≥ 4.2 and the usual coreutils-class tools. Optional: `jq` or `python3` (JSON config), `python3`+PyYAML or `yq` (YAML),
`setpriv`/`gosu`/`su-exec` (drop privileges), `gpg` (signatures). Linux only; glibc and musl; apt, dnf, yum, zypper, apk, pacman.

```sh
git clone https://github.com/bytehawks-org/shaker /opt/bytehawks/core/shaker
export PATH=/opt/bytehawks/core/shaker/bin:$PATH
sudo shaker bootstrap          # creates /opt/bytehawks, core, deps, etc, var/* and the /opt/bh symlink (never replaces a real /opt/bh)
```

Shaker is relocatable: it finds its libraries from the script location. For the examples, work under a private root:

```sh
export BH_ROOT=/tmp/hb
shaker bootstrap
```

`shaker detect` tells you what it is running on (it is also what `pkg` and the platform checks use):

```console
$ shaker detect
BH_SHAKER_ARCH                                   amd64
BH_SHAKER_DEPLOYMENT_ENVIRONMENT                 container
BH_SHAKER_DEPLOYMENT_ENVIRONMENT_TYPE            docker
BH_SHAKER_INIT_SYSTEM                            none
BH_SHAKER_LIBC                                   glibc
BH_SHAKER_OS_FAMILY                              debian
BH_SHAKER_OS_ID                                  ubuntu
BH_SHAKER_OS_PKG_MANAGER                         apt-get
...
```

## 3. Quick start without Distillery

A web server for a directory, described by a hand-written bundle. Create `hello` under the root:

```sh
B=/tmp/hb/hello/.bytehawks
mkdir -p $B /tmp/hb/hello/www && echo hi > /tmp/hb/hello/www/index.html
echo '{"schema": 1, "package": "hello", "version": "0.1"}' > $B/manifest.json      # marks "this is a bundle"
cat > $B/manifest.env <<'EOF'
BH_PKG_NAME=hello
BH_PKG_VERSION=0.1
BH_PKG_PREFIX=/tmp/hb/hello
EOF
cat > $B/rosetta.map <<'EOF'
# env|type|default|flags|aliases|file_key|cli|native_env|description
BH_HELLO_PORT|port|8000||HELLO_PORT|server.port|--port||TCP port
BH_HELLO_TOKEN|secret||||auth.token|--token||API token (unused here, shows masking)
EOF
cat > $B/runtime.spec <<'EOF'
user|hello|1020|0|/tmp/hb/hello
run|python3|-m|http.server|${BH_HELLO_PORT}|--bind|127.0.0.1|--directory|/tmp/hb/hello/www
stopsignal|TERM
pidfile|/tmp/hb/hello/run.pid
health|tcp|127.0.0.1|${BH_HELLO_PORT}
EOF
```

Install it, start it detached, look at it, stop it:

```console
$ shaker install hello
[INFO] Installing hello 0.1
[INFO] User hello (1020:0) ready

$ shaker run hello --daemon
[INFO] Initializing hello 0.1
[INFO] Starting hello in background (log: /tmp/hb/var/log/hello.log)
$ curl -s localhost:8000/
hi

$ shaker verify hello
[OK  ] user hello                   uid 1020
[OK  ] parameters                   2 declared, all valid
[OK  ] state                        installed 2026-10-30T08:22:28Z, initialized 2026-10-30T08:22:29Z
[OK  ] health tcp                   127.0.0.1:8000 open
-- 5 ok, 0 warning, 0 failed

$ shaker stop hello
```

The `run` line is an **argv**, one `|`-separated field per argument; `${BH_HELLO_PORT}` is expanded by Shaker from the resolved
parameters, never by a shell. The privilege drop (root → `hello`) happens just before `exec`. The record formats are in
[BUNDLE](https://github.com/bytehawks-org/distillery/blob/main/docs/BUNDLE.md#runtimespec).

## 4. Parameters (Rosetta)

A parameter has one canonical name, `BH_<PACKAGE>_<NAME>`, and many ways in. In order of precedence:

| # | Source | `explain` label |
|---|---|---|
| 1 | CLI flag declared in the map (`--port=9000`) | `cli` |
| 2 | the canonical variable (`BH_HELLO_PORT=9000`) | `env` |
| 3 | `BH_HELLO_PORT_FILE=/run/secrets/port` (file content) | `env-file` |
| 4 | an alias (`HELLO_PORT`), then its `_FILE` | `alias:NAME` |
| 5 | a configuration file key (`server.port`), then drop-ins | `config:KEY` |
| 6 | the default | `default` |

`shaker env` prints the result; `--format=explain` says where each value came from, and masks secrets:

```console
$ HELLO_PORT=8123 shaker env hello --format=explain
BH_HELLO_PORT                    alias:HELLO_PORT             8123

$ echo s3cr3t > /tmp/hb/token
$ BH_HELLO_TOKEN_FILE=/tmp/hb/token shaker env hello --format=explain | grep TOKEN
BH_HELLO_TOKEN                   env-file                     ********

$ shaker env hello --port=8123 --format=dotenv         # also: export (default), for eval "$(shaker env ...)"
BH_HELLO_PORT="8123"
```

Mistakes are refused, all together, and nothing is exported:

```console
$ BH_HELLO_TOKEN=a BH_HELLO_TOKEN_FILE=/tmp/hb/token shaker env hello
[ERROR] BH_HELLO_TOKEN and BH_HELLO_TOKEN_FILE are both set: choose one
$ shaker env hello --port=99999
[ERROR] BH_HELLO_PORT: invalid value '99999' for type 'port' (from cli)
```

**Legacy configuration files.** `--config=FILE` (or `BH_SHAKER_CONFIG`, or the first of `$BH_ROOT/etc/<pkg>/<pkg>.{conf,env,ini,yaml,json}`)
supplies values by `file_key`; `FILE.d/*.conf` drop-ins override it in lexical order. Formats: `KEY=VALUE`, ini (`section.key`),
JSON and YAML (flattened; need `jq`/`python3`/`yq`). Files are parsed, never sourced.

```console
$ printf '[server]\nport = 8124\n' > /tmp/hb/hello.ini
$ shaker env hello --config=/tmp/hb/hello.ini --format=explain | head -1
BH_HELLO_PORT                    config:server.port           8124
```

**For an application you did not package** a `rosetta.map` alone is enough: `shaker exec myapp --map=./rosetta.map -- /usr/bin/myapp`
resolves the parameters, exports them (with the `native_env` twins the program reads), removes Shaker's own variables and `exec`s the
program:

```console
$ shaker exec hello --port=8123 -- sh -c 'echo $BH_HELLO_PORT'
8123
```

`shaker env hello --help-vars` lists what a package accepts. Full rules: [ROSETTA](ROSETTA.md).

## 5. The lifecycle

### `install`
Idempotent. Creates the group and user (a numeric `gid` of `0` is the OpenShift convention), the `dir` records (owner applied recursively;
a numeric mode such as `0750` applies to that directory only, a symbolic one such as `g+rwX` recursively), the hook directories, and makes
the state directory group-writable so `init` works as any uid of that group. Before touching anything it checks the bundle's platform and,
if present, its digest and signature ([section 7](#7-artifacts-and-trust)).

### `init`: templates, hooks, persistence
Add to `runtime.spec` a directory, a template and a hook directory:

```
dir|/tmp/hb/hello/conf|0750|1020:0
template|hello.conf.tmpl|/tmp/hb/hello/conf/hello.conf|0640
hook|post_init|/tmp/hb/hello/hooks/post-init.d
```

`assets/hello.conf.tmpl` (inside the bundle) and a hook script:

```
port={{ BH_HELLO_PORT }}
{{? BH_HELLO_TOKEN }}token={{ BH_HELLO_TOKEN }}
```
```bash
#!/bin/bash            # /tmp/hb/hello/hooks/post-init.d/10-note.sh  (chmod +x)
echo "hook: configured $BH_PKG_NAME $BH_PKG_VERSION on port $BH_HELLO_PORT" >&2
```

```console
$ shaker install hello && shaker init hello --port=8123
[INFO] Initializing hello 0.1
[INFO] Rendered hello.conf.tmpl -> /tmp/hb/hello/conf/hello.conf
[INFO] Running hook /tmp/hb/hello/hooks/post-init.d/10-note.sh
hook: configured hello 0.1 on port 8123
$ cat /tmp/hb/hello/conf/hello.conf; ls -l /tmp/hb/hello/conf/hello.conf
port=8123
-rw-r----- 1 hello root 10 Oct 30 08:23 /tmp/hb/hello/conf/hello.conf

$ BH_HELLO_TOKEN=abc shaker init hello --port=8123 && cat /tmp/hb/hello/conf/hello.conf
port=8123
token=abc
```

* Templates: `{{ NAME }}`, `{{ NAME:-default }}`, and a line starting `{{? NAME }}` that exists only when `NAME` is set and non-empty (optional
  settings, as `token=` above). Values are inserted verbatim: no escaping, no evaluation; an unset variable without a default fails
  the render and nothing is written. The file is owned by the service user.
* Hooks: executable files or `*.sh`, lexical order, in `pre_init` (always), `first_init` (once; `--reinit` repeats it) and `post_init`
  (always). They inherit the parameters and `BH_PKG_*`. A failing hook aborts `init` unless `BH_SHAKER_HOOKS_CONTINUE=true`.
* Persistence: `persist|path|volume` seeds a mounted volume from the image content on first use and symlinks the path to it.

`init` is idempotent: run it at every start. Details: [LIFECYCLE](LIFECYCLE.md).

### `run`, `stop`, `status`
`shaker run PKG [params] [-- extra args]` does `init` and then `exec`s the command, so the service is the process (PID 1 in a container). As
root it drops to the service user; as another uid it keeps it and makes it resolvable (arbitrary uid). `--daemon` detaches it with a PID file
and a log for hosts without a supervisor; `--no-init` skips `init`. `stop` sends the declared signal (`QUIT` for nginx), waits
`BH_SHAKER_STOP_TIMEOUT` (30 s), then `SIGKILL`.

`status` is the record: what was applied, when, from which build, and the last events:

```console
$ shaker status demoweb
package   demoweb 1.0 (stable)
bundle    /tmp/dw/demoweb/.bytehawks
recipe    7d0eaad55e4f...
state     installed_at=2026-10-30T08:21:41Z
state     initialized_at=2026-10-30T08:21:41Z
state     config_hash=09c7ff27...
event     2026-10-30T08:21:41Z demoweb init ok 1.0
event     2026-10-30T08:21:41Z demoweb run ok daemon
```

## 6. Packages built by Distillery

From here on the bundle comes from Distillery (`demoweb 1.0`, a small web server with one library dependency, built under the root `/tmp/dw`;
the [Distillery manual](https://github.com/bytehawks-org/distillery/blob/main/docs/MANUAL.md) shows how). `verify` is the read-only audit; one
line per check, exit code `1` if any FAILs (`--strict`: on warnings too, `--no-health`: skip the probe, `--files`: see next section).
Pass the **same parameters you used for `init`**: CLI flags are not persisted.

```console
$ BH_ROOT=/tmp/dw shaker run demoweb --port=9090 --daemon
$ curl -s localhost:9090/
hello from demolib 2.0
$ shaker verify demoweb --port=9090 --files
[OK  ] bundle                       /tmp/dw/demoweb/.bytehawks (demoweb 1.0)
[OK  ] platform                     amd64/glibc
[OK  ] bundle digest                6 files match
[OK  ] installed files              11 paths intact, 0 mutable skipped
[OK  ] user demoweb                 uid 1010
[OK  ] dir /tmp/dw/demoweb/conf     1010:0 775
[OK  ] dir /tmp/dw/demoweb/run      1010:0 775
[OK  ] parameters                   3 declared, all valid
[OK  ] template /tmp/dw/demoweb/conf/demoweb.conf in sync
[OK  ] state                        installed 2026-10-30T08:20:39Z, initialized 2026-10-30T08:20:39Z
[OK  ] health tcp                   127.0.0.1:9090 open
-- 11 ok, 0 warning, 0 failed
```

**Drift.** Someone edits a rendered file by hand; `verify` notices, and `init` puts it back:

```console
$ echo "# edited by hand" >> /tmp/dw/demoweb/conf/demoweb.conf
$ shaker verify demoweb --no-health | grep template
[FAIL] template /tmp/dw/demoweb/conf/demoweb.conf DRIFT: modified after init (hash 9b11b94b537b != e238b33b36a9)
$ shaker init demoweb >/dev/null 2>&1; shaker verify demoweb --no-health | grep template
[OK  ] template /tmp/dw/demoweb/conf/demoweb.conf in sync
```

**Pending change.** The parameters now differ from those applied at the last `init`:

```console
$ shaker verify demoweb --port=9999 --no-health | grep template
[WARN] template /tmp/dw/demoweb/conf/demoweb.conf parameters changed since last init (run: shaker init demoweb)
```

**systemd.** `shaker unit demoweb` prints a hardened unit (`NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`, the `ReadWritePaths` it
needs, the declared stop signal), with `ExecStartPre=shaker init` and `ExecStart=shaker run --no-init`:

```console
$ shaker unit demoweb | sudo tee /etc/systemd/system/demoweb.service
$ sudo systemctl daemon-reload && sudo systemctl enable --now demoweb
```

## 7. Artifacts and trust

A Distillery build host publishes **artifacts**: `<name>.tar.gz` + `<name>.json` (+ `<name>.json.asc`). Shaker unpacks them on the target
**without Distillery** (only bash, tar and `gpg`), after checks that all pass before a single byte is written:

| Check | Fails when |
|---|---|
| tarball sha256 | it differs from the one recorded in the sidecar |
| sidecar signature | not signed by a **pinned** signer (`BH_SHAKER_TRUSTED_FINGERPRINTS`); with `--require-signature` also when unsigned |
| platform | the build's architecture/libc is not this host's (override: `BH_SHAKER_ALLOW_PLATFORM_MISMATCH=true`) |
| root | the build root differs from `BH_ROOT` (absolute paths are baked into the files) |
| paths | an absolute path, `..`, or a link leaving the tree |

Trust is configured **here**, in the consumer's environment - never read from the artifact:

```sh
export BH_SHAKER_TRUSTED_FINGERPRINTS=A7F44A4763E0F51B851548BA70F9957CE632215A     # full PRIMARY fingerprint(s), comma or space separated
export BH_SHAKER_REQUIRE_SIGNATURE=true
# the public key must be in the local gpg keyring, or give a file/URL in BH_SHAKER_TRUSTED_KEYS
```

```console
$ shaker restore dist/bh_demolib_all_library_amd64_2.0_9643d43809df.tar.gz
[INFO] Signature ok: signed by A7F44A4763E0F51B851548BA70F9957CE632215A
[INFO] Restored demolib 2.0 (9643d43809df) into /tmp/dw; next: shaker install demolib
$ shaker restore dist/bh_demoweb_stable_application_amd64_1.0_7d0eaad55e4f.tar.gz
[INFO] Signature ok: signed by A7F44A4763E0F51B851548BA70F9957CE632215A
[INFO] Restored demoweb 1.0 (7d0eaad55e4f) into /tmp/dw; next: shaker install demoweb
```

Restoring the same recipe again is a no-op (`--force` repeats it). With a signer that is not in your list the restore stops before
writing; pinning a key that is not in your keyring stops with `trusted keys are not in the local gpg keyring (set BH_SHAKER_TRUSTED_KEYS)`.

**`up`: a stack in dependency order.** The bundle records its direct dependencies and their recipes (`BH_PKG_DEPENDS`). `up` installs and
initializes them first, refuses a dependency that is not the build recorded, rejects cycles, and skips units without a runtime (libraries):

```console
$ shaker up demoweb --plan            # prints the order, changes nothing
demolib
demoweb
$ shaker up demoweb                   # add --run to start demoweb afterwards
[INFO] up: [1/2] demolib
[INFO] up: demolib has no runtime to set up
[INFO] up: [2/2] demoweb
[INFO] Bundle signed by A7F44A4763E0F51B851548BA70F9957CE632215A
[INFO] Installing demoweb 1.0
[INFO] User demoweb (1010:0) ready
[INFO] Initializing demoweb 1.0
[INFO] Rendered demoweb.conf.tmpl -> /tmp/dw/demoweb/conf/demoweb.conf
[INFO] up: demoweb installed and initialized
```

Parameters, `--config` and `--bundle` apply to the named package only; dependencies take their defaults and the environment.

**`verify --files`: audit at any time.** Re-checks the bundle digest, its signature, and every installed file, link and directory against
the build, skipping the paths the runtime rewrites on purpose (`mutable`):

```console
$ shaker verify demoweb --files --require-signature --no-health
[OK  ] bundle digest                6 files match
[OK  ] bundle signature             signed by A7F44A4763E0F51B851548BA70F9957CE632215A
[OK  ] installed files              11 paths intact, 0 mutable skipped
...
-- 11 ok, 0 warning, 0 failed

$ echo x >> /tmp/dw/demoweb/bin/demoweb            # someone patches the binary
$ shaker verify demoweb --files --no-health
[FAIL] installed files              modified demoweb/bin/demoweb
         1 problem(s) in 11 checked paths
-- 10 ok, 0 warning, 1 failed
```

## 8. Containers and Kubernetes

The same bundle and verbs, with the service as PID 1. Build the tree in one stage, ship it into any base that has bash:

```dockerfile
FROM debian:12-slim
COPY --from=build /opt/bytehawks /opt/bytehawks
COPY shaker /opt/bytehawks/core/shaker
ENV PATH=/opt/bytehawks/core/shaker/bin:$PATH
RUN shaker install demoweb                 # user 1010:0, directories, group-writable state
USER 1010
ENTRYPOINT ["shaker", "run", "demoweb"]    # `docker run image --port=9000` passes declared flags
```

* Parameters are plain environment (`-e BH_DEMOWEB_PORT=9000`), aliases (`DEMOWEB_PORT`), flags after the image name, or secrets as files:
  `-v ./secrets:/run/secrets:ro -e BH_APP_PASSWORD_FILE=/run/secrets/pw`. The service sees the value; `shaker env --format=explain` shows `********`.
* `gid 0` services run as any uid (OpenShift): `run` makes the uid resolvable with `nss_wrapper` or a writable `/etc/passwd`.
* `readOnlyRootFilesystem: true`: point `BH_STATE` at an `emptyDir`; the install record is then absent (a `verify` WARN, not a failure).
* Kubernetes: `env` entries for `BH_*`, `BH_*_FILE` pointing at mounted Secrets, probes on the port of the bundle's `health` record. See
  [DEPLOYMENT](DEPLOYMENT.md). These container recipes are not run in this manual.

## 9. Legacy hosts

A VM or server without containers uses the same bundle:

```sh
sudo shaker bootstrap && sudo shaker restore <artifact>.tar.gz && sudo shaker install demoweb
sudo mkdir -p /opt/bytehawks/etc/demoweb && sudo cp demoweb.ini /opt/bytehawks/etc/demoweb/      # picked up automatically
sudo shaker run demoweb --daemon          # no supervisor: pid file + log under $BH_ROOT/var
shaker unit demoweb | sudo tee /etc/systemd/system/demoweb.service      # or let systemd supervise it
```

An environment variable overrides the file, which makes a hot fix (or a one-off test) visible in `explain`. Native packages built
by Distillery (`apt install ./bytehawks-demoweb_*.deb`) run `shaker install` in their post-install script.

## 10. Tools

Independent of any bundle:

```console
$ printf 'port {{ PORT:-80 }}\n{{? TOKEN }}token {{ TOKEN }}\nname {{ NAME }}\n' > t.tmpl
$ NAME=web shaker render t.tmpl                 # to stdout; a second argument writes that file
port 80
name web
$ TOKEN=abc NAME=web shaker render t.tmpl
port 80
token abc
name web

$ BH_SHAKER_DRY_RUN=true shaker pkg install ca-certificates tzdata      # logical names -> your distro's tool and names
[INFO] [dry-run]  apt-get install -y --no-install-recommends ca-certificates tzdata
$ shaker pkg update && shaker pkg install ca-certificates && shaker pkg clean      # Dockerfile layer pattern

$ shaker wait-for 127.0.0.1 5432 30           # wait for a TCP port (bash /dev/tcp); exit 1 on timeout
$ shaker hooks ./init.d                       # run executables / *.sh in lexical order
```

## 11. Troubleshooting

| Message / symptom | Cause and fix |
|---|---|
| `No Distillery bundle for 'X' (looked in ...)` | no `manifest.json` in `$BH_ROOT/X/.bytehawks` or `$BH_ROOT/deps/.bytehawks/X`. A hand-written bundle needs that file (`{"schema":1}` will do), or pass `--bundle=DIR` |
| `... are both set: choose one` | a variable and its `_FILE` twin: remove one |
| `invalid value ... for type ...` | the declared type refused it; `shaker env X --help-vars` shows the types |
| `[FAIL] template ... DRIFT` | the rendered file was edited. `shaker init X` renders it again; put lasting changes into parameters or the template |
| `[WARN] ... parameters changed since last init` | `verify` was called with other parameters than `init`; flags are not persisted, repeat them |
| `[FAIL] health tcp ... closed` | not running, wrong port (pass the same `--port`), or still starting. `--no-health` in build-time checks |
| `[FAIL] platform` / refusing to install | the bundle is for another architecture or C library (a glibc build on Alpine). Rebuild with the right `--libc`, or `BH_SHAKER_ALLOW_PLATFORM_MISMATCH=true` if you know better |
| `restore` refuses: root | the artifact was built under another root: restore under that `BH_ROOT`, or rebuild |
| signature errors | the signer is not in `BH_SHAKER_TRUSTED_FINGERPRINTS`, or its public key is not in the keyring (`BH_SHAKER_TRUSTED_KEYS`) |
| `Process exited immediately, see ...log` | read that log; typical: the service user cannot read the tree (check owner/mode of the prefix and its parents) |
| `install requires root` | `install` creates users and changes owners: run as root, or set `BH_SHAKER_ALLOW_NONROOT=true` for image-build / rootless cases (ownership is then skipped) |

More logging: `BH_SHAKER_LOG_LEVEL=debug` (secrets stay masked).

## 12. Cheat sheet

```sh
shaker bootstrap | detect | version
shaker install P | init P [--flags] | run P [--daemon|--no-init|--reinit] [-- args] | stop P | status P
shaker verify P [--files] [--strict] [--no-health] [--require-signature]      shaker unit P
shaker up P [--plan|--run]                shaker restore ARTIFACT.tar.gz [--sidecar F] [--force] [--require-signature]
shaker env P [--format=export|dotenv|explain|--validate|--help-vars]    shaker exec P [--flags] -- cmd args
shaker render TPL [DEST]    shaker pkg install|remove|update|clean|check ...    shaker hooks DIR    shaker wait-for HOST PORT [SECS]
env: BH_ROOT  BH_SHAKER_ALLOW_NONROOT  BH_SHAKER_QUIET  BH_SHAKER_LOG_LEVEL  BH_SHAKER_TRUSTED_FINGERPRINTS  BH_SHAKER_TRUSTED_KEYS
     BH_SHAKER_REQUIRE_SIGNATURE  BH_SHAKER_ALLOW_PLATFORM_MISMATCH  BH_SHAKER_STOP_TIMEOUT  BH_SHAKER_HOOKS_CONTINUE  BH_SHAKER_DRY_RUN
```

Exit codes: `0` ok, `1` failure (invalid parameter, failed check, I/O error), `2` usage error.
