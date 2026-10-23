# shaker

> A modular bash framework for hardened initialization, configuration normalization and
> lifecycle governance of software installations, on **containers and legacy VM/servers alike**.

Shaker is the *runtime / installation* half of the [ByteHawks](https://github.com/bytehawks-org)
ecosystem. [Distillery](https://github.com/bytehawks-org/distillery) **declares and builds**
(sources, checksums, dependencies, parameters, runtime contract); Shaker **applies and audits**
what Distillery declared. Nothing application-specific is hard-coded in Shaker: it reads the
*bundle* that Distillery writes next to every artifact.

It is the declarative, traceable successor to the hand-written per-application scripts of the
Bitnami images (`libos.sh`, `libfs.sh`, `libfile.sh`, `<app>-env.sh`, `setup.sh`,
`entrypoint.sh`, `run.sh`) - see [docs/BITNAMI-MIGRATION.md](docs/BITNAMI-MIGRATION.md).

```
 Distillery (build time)                       Shaker (install / runtime)
 packages.yaml ──► build ──► artifacts   ──►   shaker install   user, dirs, permissions
   sources+sha256            /opt/bytehawks/   shaker init      parameters ► templates, hooks
   depends_on                <pkg>/            shaker run       exec as PID 1, drop privileges
   runtime: (contract)       └ .bytehawks/     shaker verify    audit: permissions, drift, health
                               bundle ───────► shaker status / unit / stop
```

## Highlights

| | |
|---|---|
| **One parameter, every dialect** (Rosetta) | CLI flag, canonical env, upstream/Bitnami alias, `*_FILE` secret, config file (env/ini/json/yaml + drop-ins) → one canonical `BH_<PKG>_<NAME>`; provenance of every value (`--format=explain`) |
| **Container *and* legacy** | same bundle, same verbs: ENTRYPOINT in a pod, `ExecStart` on a VM (`shaker unit` prints a hardened systemd unit) |
| **Distro-agnostic** | bash ≥ 4.2 + POSIX tools; systemd optional; apt, dnf, microdnf, yum, tdnf, zypper, apk, pacman; glibc and musl; amd64/arm64 |
| **Tracked** | `state` per package (what, when, which build recipe) + append-only event log; drift detection of rendered files |
| **Secure by default** | config files are parsed, never sourced; no `eval`; secrets masked in every output; privileges dropped with `exec` (service stays PID 1); arbitrary-uid / OpenShift ready |
| **Tested** | 139 shell assertions, a CI workflow with a 6-distribution matrix (Debian, Fedora, Rocky, openSUSE, Arch, Alpine), end-to-end contract test against Distillery (a real nginx 1.28 built from source with Distillery was installed, run and verified through Shaker) |

## Quick start

```sh
# 1. layout (once) - /opt/bytehawks and the /opt/bh symlink
sudo shaker bootstrap

# 2. what is this machine?
shaker detect

# 3. a package built by Distillery lives in /opt/bytehawks/nginx with its bundle in .bytehawks/
sudo shaker install nginx                 # user 1001:0, directories, permissions
shaker env nginx --port=8081 --format=explain
shaker init nginx --port=8081             # renders conf from parameters, runs hooks
shaker verify nginx --port=8081           # user, perms, parameters, drift, health
shaker run nginx --port=8081              # exec nginx as PID 1 (container)
sudo shaker run nginx --daemon            # or detached with a PID file (host without supervisor)
shaker unit nginx | sudo tee /etc/systemd/system/nginx.service
```

Container:

```dockerfile
FROM debian:12-slim
COPY --from=build /opt/bytehawks /opt/bytehawks
RUN /opt/bytehawks/core/shaker/bin/shaker install nginx
USER 1001
ENTRYPOINT ["/opt/bytehawks/core/shaker/bin/shaker", "run", "nginx"]
```

Kubernetes - secrets stay secrets, parameters are plain env:

```yaml
env:
  - {name: BH_NGINX_PORT, value: "8080"}
  - {name: BH_POSTGRESQL_PASSWORD_FILE, value: /run/secrets/pg/password}   # any secret parameter
```

## Commands

| Command | Purpose |
|---|---|
| `install <pkg>` | service user/group, directories with owner and mode, state permissions (root, idempotent) |
| `init <pkg>` | pre_init hooks → persistence → templates → first_init hooks (once) → post_init hooks → state |
| `run <pkg> [-- args]` | `init` + exec the service; `--daemon` detaches with PID file; `--no-init` skips init |
| `stop <pkg>` | stop a `--daemon` service with the declared signal |
| `verify <pkg>` | read-only audit, non-zero exit on failure (`--strict`: also on warnings) |
| `status <pkg>` | recorded state and last events |
| `unit <pkg>` | hardened systemd unit |
| `env <pkg>` / `exec <pkg> -- cmd` | resolve Rosetta parameters; print or exec with them |
| `detect`, `render`, `pkg`, `hooks`, `wait-for`, `bootstrap`, `banner`, `version` | tools |

Full reference: [docs/CLI.md](docs/CLI.md).

## Filesystem layout

```
/opt/bytehawks              real path (never use /opt/bh inside binaries or configs)
/opt/bh -> /opt/bytehawks   convenience symlink
├── core/shaker             this repository  (core/distillery is the builder)
├── deps/                   libraries built by Distillery (+ .bytehawks/<lib>/)
├── etc/<pkg>/              <pkg>.conf + <pkg>.conf.d/*.conf  (legacy hosts)
├── var/                    lib/shaker (state, events.log), log/, run/
└── <pkg>/                  application prefix, .bytehawks/ = the bundle
```

Shaker itself is relocatable: it finds its own libraries from the script location.

## Documentation

| Document | Content |
|---|---|
| [ARCHITECTURE](docs/ARCHITECTURE.md) | design, data flow, contract with Distillery, design decisions |
| [CLI](docs/CLI.md) | every command and option, exit codes |
| [ROSETTA](docs/ROSETTA.md) | parameter model, precedence, file formats, `*_FILE`, provenance |
| [LIFECYCLE](docs/LIFECYCLE.md) | install / init / run / stop / verify / status / unit in detail, state, hooks, persistence |
| [DEPLOYMENT](docs/DEPLOYMENT.md) | containers, Kubernetes, OpenShift, legacy VM/server, systemd |
| [ENVIRONMENT](docs/ENVIRONMENT.md) | every variable Shaker reads or sets |
| [LIBRARY](docs/LIBRARY.md) | function reference of every `lib/*.libsh` |
| [PORTABILITY](docs/PORTABILITY.md) | supported platforms, required tools, rules for contributors |
| [BITNAMI-MIGRATION](docs/BITNAMI-MIGRATION.md) | what Bitnami did, how each piece maps, how to port an app |
| [SECURITY](docs/SECURITY.md) | threat model and guarantees |
| [TESTING](docs/TESTING.md) | test runner, fixtures, CI, contributing |
| [ROADMAP](ROADMAP.md) / [CHANGELOG](CHANGELOG.md) | where it is going / what changed |

## Requirements

bash ≥ 4.2, coreutils-class tools (`cat cut grep sed tr find chmod chown mkdir mv ln date uname id`),
`sha256sum`/`shasum`/`openssl` for hashes. Optional: `jq` or `python3` (JSON config), `python3`+PyYAML
or `yq` (YAML config), `setpriv`/`gosu`/`su-exec` (drop privileges), `libnss_wrapper` (arbitrary uid on
read-only `/etc/passwd`). Linux only.

## License

Apache-2.0, see [LICENSE](LICENSE).
