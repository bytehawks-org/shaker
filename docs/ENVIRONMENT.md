# Environment variables

## Layout (shared with Distillery; override before running Shaker)

| Variable | Default | Meaning |
|---|---|---|
| `BH_ROOT` | `/opt/bytehawks` | real root of the ecosystem |
| `BH_LINK` | `/opt/bh` | convenience symlink created by `bootstrap` |
| `BH_CORE` | `$BH_ROOT/core` | Distillery + Shaker |
| `BH_DEPS` | `$BH_ROOT/deps` | libraries; their bundles in `$BH_DEPS/.bytehawks/<lib>` |
| `BH_ETC` | `$BH_ROOT/etc` | per-package configuration for legacy hosts |
| `BH_VAR` | `$BH_ROOT/var` | `log/`, `run/` |
| `BH_STATE` | `$BH_VAR/lib/shaker` | state files and `events.log` |

## Behaviour

| Variable | Default | Meaning |
|---|---|---|
| `BH_SHAKER_LOG_LEVEL` | `info` | `debug info warn error` |
| `BH_SHAKER_DEBUG` | `false` | `true` ≡ level `debug` (Bitnami `BITNAMI_DEBUG`) |
| `BH_SHAKER_QUIET` | `false` | suppress all log output |
| `BH_SHAKER_COLOR` | auto | force colour on/off |
| `BH_SHAKER_MODULE` | - | tag added to every log line |
| `BH_SHAKER_DISABLE_BANNER` | `false` | hide the banner (`shaker banner`) |
| `BH_SHAKER_DRY_RUN` | `false` | `pkg_*` print the command instead of running it |
| `BH_SHAKER_CONFIG` | - | configuration file, overrides discovery |
| `BH_SHAKER_CONFIG_FORMAT` | by extension | `env ini json yaml` |
| `BH_SHAKER_BUNDLE` | - | bundle directory (same as `--bundle=`) |
| `BH_SHAKER_ALLOW_NONROOT` | `false` | let `install` run unprivileged (skips users/ownership) |
| `BH_SHAKER_HOOKS_CONTINUE` | `false` | keep going after a failing hook |
| `BH_SHAKER_STOP_TIMEOUT` | `30` | seconds before `stop` sends `SIGKILL` |

## Set by Shaker

| Variable | Set by | Content |
|---|---|---|
| `BH_SHAKER_DEPLOYMENT_ENVIRONMENT[_TYPE\|_ORCHESTRATOR]` | `detect_*` | `container vm physical` / type / `kubernetes` |
| `BH_SHAKER_INIT_SYSTEM` | `detect_init_system` | `systemd openrc sysv none` |
| `BH_SHAKER_OS_NAME\|VERSION\|ID\|VERSION_ID\|FAMILY` | `detect_os` | lowercase |
| `BH_SHAKER_ARCH` `BH_SHAKER_LIBC` | `detect_os` | `amd64 arm64 armv7` · `glibc musl` |
| `BH_SHAKER_OS_PKG_MANAGER[_PATH]` | `detect_package_manager` | |
| `BH_SHAKER_HOME` `..._LIB_FOLDER` `..._ASSETS_FOLDER` `..._SHARE_FOLDER` (`..._BASE_FOLDER` legacy alias) | `shaker_init_paths` | |
| `BH_PKG_NAME VERSION VARIANT PREFIX RECIPE BUNDLE` | `spec_load` | from the bundle; available to templates, hooks, run command, **and kept for the service** |
| `BH_<PKG>_*` and their `native_env` | `rosetta_export` | resolved parameters |

All `BH_SHAKER_*` are removed before the service `exec`s; `BH_PKG_*`, `BH_<PKG>_*` and the layout
variables are kept.

## Read from the platform

`KUBERNETES_SERVICE_HOST`, `container`, `TMPDIR`, `CI`, `GITHUB_ACTIONS`, `LD_PRELOAD`/`NSS_WRAPPER_*`
(set by `ensure_passwd_entry`), `DEBIAN_FRONTEND` (set to `noninteractive` for `apt-get`).

## Test hooks (not for production)

`BH_SHAKER_OS_RELEASE_FILE`, `BH_SHAKER_PROC_ROOT` (fake `/proc /sys /run /` for detection),
`SHAKER_PASSWD_FILE`, `SHAKER_GROUP_FILE`, `DISTILLERY_HOME` (integration test).
