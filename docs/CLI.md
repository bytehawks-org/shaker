# CLI reference

```
shaker <command> [options]
```

Exit codes: `0` success · `1` failure (invalid parameter, failed check, I/O error) · `2` usage error
(unknown command). `verify` returns `1` when any check FAILs (and, with `--strict`, on WARN).

Logs go to **stderr**; **stdout** carries only the machine-readable result of a command (`env`,
`detect`, `render`, `unit`, `verify` table, `status`). `BH_SHAKER_QUIET=true` silences stderr.

## Options shared by the package verbs

Parsed by `lifecycle_parse_args` for `install init run stop verify status unit env exec`:

| Option | Meaning |
|---|---|
| `--bundle=DIR` | use this bundle instead of `$BH_ROOT/<pkg>/.bytehawks` / `$BH_DEPS/.bytehawks/<pkg>` |
| `--config=FILE` | configuration file (default: auto-discovered, see [ROSETTA](ROSETTA.md#legacy-configuration-files)) |
| `--map=FILE` | Rosetta map (default `<bundle>/rosetta.map`); lets `env`/`exec` work without a bundle |
| `--no-init` | (`run`) skip `init` |
| `--daemon` | (`run`) detach, PID file + log |
| `--reinit` | (`init`/`run`) run `first_init` hooks again |
| `--strict` | (`verify`) warnings fail |
| `--no-health` | (`verify`) skip the health check (build time, CI) |
| `--files` | (`verify`) also check every installed file against the bundle's `files.sha256`, skipping `mutable` paths |
| `--require-signature` | (`install`, `verify`) refuse a bundle not signed by a pinned signer (same as `BH_SHAKER_REQUIRE_SIGNATURE=true`) |
| `--format=` | (`env`) `export` (default), `dotenv`, `explain` |
| `--validate` | (`env`) validate only, print nothing |
| `--help-vars` | (`env`) describe the package parameters |
| `--` | everything after is the command (`exec`) or extra service arguments (`run`) |
| `--<flag>[=value]` | any flag declared in the `cli` column of the package's Rosetta map; unknown flags are an error |

## Lifecycle

### `shaker install <pkg>`
Idempotent, root. Creates the service group/user, directories (owner, mode), hook directories, makes
the state directory writable by the service group, records `installed_*` in the state.
Without root: error, unless `BH_SHAKER_ALLOW_NONROOT=true` (then users and ownership are skipped).

### `shaker init <pkg> [params]`
Resolves parameters, then `pre_init` hooks → persistence → templates → `first_init` hooks (once) →
`post_init` hooks → state. Idempotent. Details: [LIFECYCLE](LIFECYCLE.md#init).

### `shaker run <pkg> [params] [--no-init] [--daemon] [-- extra args]`
`init` (unless `--no-init`) then start the service.
* default: `exec` - the service replaces Shaker (PID 1 in a container). If root and the package
  declares a user, privileges are dropped to it; otherwise the current uid is kept (and made
  resolvable, see arbitrary uid).
* `--daemon`: detached via `nohup`, stdout/stderr appended to `$BH_VAR/log/<pkg>.log`, PID in the
  package's declared `pidfile` (default `$BH_VAR/run/<pkg>.pid`); returns once the process survived 1 s.

### `shaker stop <pkg>`
Sends the package's stop signal (`stopsignal`, e.g. `QUIT` for nginx) to the PID file process, waits
`BH_SHAKER_STOP_TIMEOUT` (30 s) then `SIGKILL`. Removes the PID file. No PID file → success.

### `shaker up <pkg> [params] [--plan] [--run]`
Brings a package and everything it was built against up, **dependencies first**. The dependencies come from `BH_PKG_DEPENDS` in the
bundle's `manifest.env` (`<package>=<recipe sha256>`, written by Distillery; a bundle without it has none), each dependency's own bundle
lists its dependencies in turn. Before anything is done it checks that the installed bundle of every dependency is the build recorded
(a different recipe stops the run: rebuild or reinstall one of them), and that there is no cycle. Then, for every unit in order, it runs
`install` and `init`; a unit whose bundle declares no runtime (a library) is skipped. Parameters, `--config` and `--bundle` apply to
`<pkg>` only, dependencies use their defaults and the environment. The first failure stops the chain. `--plan` prints the order and
changes nothing; `--run` starts `<pkg>` afterwards (as `shaker run`). Idempotent.

```
$ shaker up nifi --plan
temurin
nifi
```

### `shaker restore <artifact.tar.gz> [--sidecar=FILE] [--force] [--require-signature]`
Unpacks a Distillery artifact into `BH_ROOT` without Distillery. `<name>.json` (and `<name>.json.asc` if present) must sit next to the
tarball, or be given with `--sidecar`. Nothing is written before all of these pass: the tarball matches the sha256 recorded in the
sidecar; the sidecar signature comes from a pinned signer (`BH_SHAKER_TRUSTED_FINGERPRINTS`; required with `--require-signature`);
the build platform equals this host (`BH_SHAKER_ALLOW_PLATFORM_MISMATCH`); the build root equals `BH_ROOT` (paths are baked into the
files); member names are relative and links stay inside the tree. It extracts into a staging directory, re-checks the links, copies
into the root and verifies the restored bundle's `bundle.sha256`. Restoring the same recipe again is a no-op (`--force` repeats it).
Then: `shaker install <pkg>`.

### `shaker verify <pkg> [params] [--strict] [--no-health] [--files] [--require-signature]`
Read-only audit. One line per check:

```
[OK  ] bundle                       /opt/bytehawks/nginx/.bytehawks (nginx 1.28.0)
[OK  ] platform                     amd64/glibc
[OK  ] bundle digest                5 files match
[OK  ] bundle signature             signed by B54C4E48307BEE7831E844365799A3FD70E80C1F
[OK  ] installed files              540 paths intact, 8 mutable skipped
[OK  ] requires openssl
[OK  ] user nginx                   uid 1001
[OK  ] dir /opt/bytehawks/nginx/run 1001:0 775
[OK  ] parameters                   5 declared, all valid
[FAIL] template .../nginx.conf      DRIFT: modified after init (hash 54a0efc3a583 != 4c8dc9117517)
[WARN] template .../nginx.conf      parameters changed since last init (run: shaker init nginx)
[FAIL] health tcp                   127.0.0.1:8080 closed
-- 9 ok, 0 warning, 1 failed
```
The first four lines come from the Distillery seal and are skipped when the bundle does not carry it (hand-written
bundle, older Distillery): **platform** (`BH_PKG_ARCH`/`BH_PKG_LIBC` against the host; FAIL on mismatch unless
`BH_SHAKER_ALLOW_PLATFORM_MISMATCH=true`), **bundle digest** (`bundle.sha256`), **bundle signature** (`bundle.sha256.asc`
against `BH_SHAKER_TRUSTED_FINGERPRINTS`; WARN when signed but nothing is pinned, FAIL when required and missing or foreign)
and, with `--files`, **installed files**. Problems under `--files` are listed below the line (at most 20).
Pass the same parameters you used for `init` (or put them in the config file / environment):
CLI flags are not persisted, so a bare `verify` compares against defaults.

### `shaker status <pkg>`
Bundle, recipe hash, every state key (`installed_at`, `initialized_at`, `config_hash`, ...) and the
last five events of the package.

### `shaker unit <pkg>`
Prints a systemd unit to stdout. See [DEPLOYMENT](DEPLOYMENT.md#systemd).

## Parameters

### `shaker env <pkg> [params]`
Prints the resolved parameters.

| `--format` | Output | Use |
|---|---|---|
| `export` | `export NAME=<printf %q>` | `eval "$(shaker env pkg)"` |
| `dotenv` | `NAME="value"` | `docker --env-file`, systemd `EnvironmentFile=` |
| `explain` | `NAME  source  value` (secrets `********`) | debugging, support |

### `shaker exec <pkg> [params] -- cmd args...`
Resolves, exports (including `native_env` twins), removes `BH_SHAKER_*` from the environment and
`exec`s the command. Generic entrypoint for applications that read their own env but have no runtime
spec yet.

## Tools

| Command | |
|---|---|
| `shaker detect [--format=text\|env]` | prints `BH_SHAKER_DEPLOYMENT_*`, `OS_*`, `OS_FAMILY`, `INIT_SYSTEM`, `ARCH`, `LIBC`, `OS_PKG_MANAGER*` |
| `shaker render <template> [dest]` | `{{ NAME }}` / `{{ NAME:-default }}` from the environment; unset without default = error, no file written |
| `shaker pkg install\|remove <names>` | logical names (`share/pkgmap.map`) → real names; `BH_SHAKER_DRY_RUN=true` prints the command |
| `shaker pkg update\|clean` | refresh / drop package-manager caches (image layers) |
| `shaker pkg check <names>` | exit 0 if all installed |
| `shaker hooks <dir>` | run `*` executable or `*.sh` in lexical order; `BH_SHAKER_HOOKS_CONTINUE=true` ignores failures |
| `shaker wait-for <host> <port> [seconds=30]` | wait for a TCP port (bash `/dev/tcp`) |
| `shaker bootstrap` | create `BH_ROOT`, `core`, `deps`, `etc`, `var`, state and log dirs and the `BH_LINK` symlink; never touches a real directory at `BH_LINK` |
| `shaker banner` / `version` / `help` | |

## Examples

```sh
# Which parameters does a package accept?
shaker env nginx --help-vars

# Where does each value come from?
NGINX_HTTP_PORT_NUMBER=9000 shaker env nginx --server-name=example.com --format=explain
# BH_NGINX_PORT         alias:NGINX_HTTP_PORT_NUMBER  9000
# BH_NGINX_SERVER_NAME  cli                     example.com

# Image build, no root user, no state: prepare files only
BH_SHAKER_ALLOW_NONROOT=true shaker install nginx

# Compose a prerequisite install in a Dockerfile, any base distro
shaker pkg update && shaker pkg install ca-certificates tzdata && shaker pkg clean
```
