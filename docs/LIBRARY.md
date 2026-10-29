# Library reference

`. lib/shaker.libsh` loads everything (the dispatcher does it for you). All functions log through
`log_event` (stderr) and return codes; none exits the shell except `die`. Under `set -e` use
`func || handle` for functions documented as returning non-zero on a normal outcome.

Conventions: public functions have no prefix by area when they mirror a Bitnami name
(`ensure_dir_exists`, `replace_in_file`); framework internals are prefixed (`shaker_`, `rosetta_`,
`lifecycle_`, `state_`, `spec_`, `service_`, `pkg_`); a leading `_` marks a private helper.

## core.libsh
| Function | Description |
|---|---|
| `shaker_resolve_path <path>` | physical absolute path following symlinks, without `realpath` |
| `shaker_init_paths` | computes/exports the layout (`BH_ROOT BH_LINK BH_CORE BH_DEPS BH_ETC BH_VAR BH_STATE`, `BH_SHAKER_HOME/LIB_FOLDER/ASSETS_FOLDER/SHARE_FOLDER`) and the unexported `SHAKER_HOME SHAKER_LIB SHAKER_ASSETS SHAKER_SHARE`; called at load |
| `shaker_version` | contents of `VERSION` |
| `shaker_bootstrap` | create the directory layout and the `BH_LINK` symlink; idempotent; refuses to replace a real directory |

## validate.libsh
| Function | Description |
|---|---|
| `normalize_boolean <v>` | echoes `true`/`false`; rc 1 for unrecognized (echoes `false`) |
| `is_boolean_yes <v>` | rc 0 when the value is a true value; for `if is_boolean_yes "${X:-}"` |
| `normalize_case <lower\|upper> <s>` | case conversion |
| `is_int` `is_uint` `is_port` | numeric checks (port 1-65535) |
| `is_secret_name <name>` | rc 0 for names that look like secrets (`*PASSWORD* *SECRET* *PASSWD* *CREDENTIAL* TOKEN *_TOKEN *_TOKEN_* *_KEY *_KEY_*`) |
| `validate_type <type> <value>` | `string secret int uint port bool path enum:a,b`; rc 0 ok, 1 invalid, 2 unknown type |

## log.libsh
| Function | Description |
|---|---|
| `log_event <level> <msg...>` | level `debug info warn error`; honours `BH_SHAKER_LOG_LEVEL`, `BH_SHAKER_DEBUG`, `BH_SHAKER_QUIET`, `BH_SHAKER_COLOR`, `BH_SHAKER_MODULE` |
| `log_debug` `log_info` `log_warn` `log_error` | shorthands |
| `die <msg...>` | log error and `exit 1` |
| `stderr_print`, `log_full_message`, `log_level_value` | building blocks |

Colour defaults to on only for a terminal on stderr or when `CI`/`GITHUB_ACTIONS` is set.
The timestamp comes from the `printf %(..)T` builtin: no `date` fork per line.

## os.libsh
| Function | Exports |
|---|---|
| `detect_deployment_environment` | `BH_SHAKER_DEPLOYMENT_ENVIRONMENT` (`container`/`vm`/`physical`), `..._TYPE` (docker, podman, lxc, kvm, vmware, oracle, microsoft, xen, vm, container), `..._ORCHESTRATOR` (`kubernetes`) |
| `detect_init_system` | `BH_SHAKER_INIT_SYSTEM` = `systemd` `openrc` `sysv` `none` |
| `detect_os` | `BH_SHAKER_OS_NAME VERSION ID VERSION_ID FAMILY ARCH LIBC` (lowercase) |
| `os_family_of <id> [id_like]` | `debian rhel suse alpine arch unknown` |
| `detect_arch` / `detect_libc` | `amd64 arm64 armv7` / `glibc musl unknown` |
| `detect_package_manager` | `BH_SHAKER_OS_PKG_MANAGER`, `..._PATH`; family-aware order, then any known manager |
| `detect_all` | all of the above in dependency order |

Container detection order: `KUBERNETES_SERVICE_HOST` → `/.dockerenv` → `/run/.containerenv` →
`$container` → `systemd-detect-virt --container` → `/proc/1/cgroup`. VM: `systemd-detect-virt --vm` →
DMI vendor/product → `hypervisor` CPU flag.

## pkg.libsh
`pkg_install`, `pkg_remove`, `pkg_update`, `pkg_clean`, `pkg_is_installed` take **logical** names.
`pkg_resolve <logical>` consults `share/pkgmap.map` (`logical|family|real names`, `-` = not needed).
`pkg_build_command <op> [names]` fills `SHAKER_PKG_CMD`; `pkg_run` executes it with `sudo -E` when not
root, non-interactively, or only prints it under `BH_SHAKER_DRY_RUN=true`.

| Manager | install | check |
|---|---|---|
| apt-get | `install -y --no-install-recommends` | `dpkg -s` |
| dnf / microdnf | `install -y` without weak deps | `rpm -q` |
| yum / tdnf | `install -y` | `rpm -q` |
| zypper | `--non-interactive install --no-recommends` | `rpm -q` |
| apk | `add --no-cache` | `apk info -e` |
| pacman | `-S --noconfirm --needed` | `pacman -Qi` |

## fs.libsh
| Function | Description |
|---|---|
| `am_i_root` | uid 0 |
| `is_dir_empty <dir>` | true for missing or empty (hidden files count) |
| `ensure_dir_exists <dir> [owner] [mode]` | `mkdir -p` + optional chown/chmod |
| `configure_permissions_ownership <path> [-u u] [-g g] [-d dirmode] [-f filemode]` | recursive, separate dir/file modes |
| `ensure_group_exists <name> [gid]` / `ensure_user_exists <name> [uid] [group] [home]` | `groupadd`/`useradd`, busybox `addgroup`/`adduser` fallback; system account only below 1000; no home created |
| `run_as_user <user> cmd...` | run a command as another user (`setpriv runuser gosu su-exec su`); not for PID 1 |
| `exec_as_user <uid\|user> <gid\|group> cmd...` | **exec** with dropped privileges (`setpriv gosu su-exec`, `runuser` last) |
| `ensure_passwd_entry [name] [home]` | arbitrary uid support (writable passwd, else `nss_wrapper`) |
| `generate_random_string [len=32]` | `A-Za-z0-9` from `/dev/urandom` |

## file.libsh
| Function | Description |
|---|---|
| `replace_in_file <file> <old> <new>` | **literal** replacement, in place, any characters safe |
| `ensure_line_in_file <file> <line>` | append if no identical line |
| `render_template <tpl> [dest]` | `{{ NAME }}`, `{{ NAME:-default }}` from the environment; error if unset without default. A line beginning `{{? NAME }}` is emitted only when `NAME` is set and non-empty (optional settings), e.g. `{{? BH_APP_PASSWORD }}requirepass {{ BH_APP_PASSWORD }}` |
| `expand_vars <string>` | `${NAME}`, `${NAME:-default}`; never evaluates; error if unset without default |
| `sha256_of_file` / `sha256_of_string` | `sha256sum`, `shasum -a 256` or `openssl dgst` |

## net.libsh · hook.libsh · service.libsh
| Function | Description |
|---|---|
| `is_port_open <host> <port>` | TCP connect within 2 s via `/dev/tcp` |
| `wait_for_port <host> <port> [timeout=30]` | poll every second |
| `run_hooks <dir>` | executables and `*.sh`, lexical order; `BH_SHAKER_HOOKS_CONTINUE` |
| `service_pid <pidfile>` `is_service_running <pidfile>` | |
| `service_start_detached <pidfile> <log> cmd...` | nohup, records PID, verifies survival for 1 s |
| `service_stop <pidfile> [signal=TERM] [timeout=30]` | signal, wait, then `SIGKILL`; removes PID file |

## rosetta.libsh
`rosetta_reset`, `rosetta_load_map <file>`, `rosetta_find_config <pkg>`, `rosetta_load_config <file>`
(+ `rosetta_parse_env|ini|json|yaml` reading stdin into `ROSETTA_CFG`), `rosetta_parse_cli args...`
(fills `ROSETTA_CLI_VALUE`, `ROSETTA_REST`), `rosetta_resolve` (fills `ROSETTA_VALUE`,
`ROSETTA_SOURCE`), `rosetta_export`, `rosetta_print <export|dotenv|explain>`, `rosetta_describe`.
State lives in global associative arrays `ROSETTA_TYPE/DEFAULT/FLAGS/ALIASES/FILEKEY/CLI/NATIVE/DESC`
indexed by canonical name, with `ROSETTA_ORDER` keeping declaration order.

## state.libsh · spec.libsh · lifecycle.libsh
`state_dir`, `state_file`, `state_get|set|unset <pkg> ...`, `state_event <pkg> <verb> <ok|fail|..> [detail]`,
`state_now`; `shaker_find_bundle <pkg>`, `spec_load <bundle>` (fills `SPEC_*`, exports `BH_PKG_*`);
`lifecycle_parse_args`, `lifecycle_load`, `lifecycle_resolve`, `lifecycle_install|init|run|stop|verify|status|unit`.

## seal.libsh · artifact.libsh
`seal_check_platform [arch libc]`, `seal_check_digest <bundle>`, `seal_check_signature <bundle>`, `seal_verify_gpg <file> <sig> <fingerprint...>`,
`seal_check_files <bundle>` (honours `SPEC_MUTABLE`), `seal_require_trust <bundle>`, `seal_check_platform_install`; each prints one line and
returns a code (0 ok, 1 problem, 2 nothing to check, 3 signed but nothing pinned). `artifact_restore <tar.gz> [--sidecar=] [--force] [--require-signature]`.

## up.libsh
`up_plan <pkg>` (fills `UP_ORDER`, dependencies first; checks recipes and cycles), `up_apply <pkg> <main|dep> [opts]`, `up_all <pkg> [opts]`.

## shaker.libsh
`cleanup_bh_shaker_env_vars` (unset every exported `BH_SHAKER_*`; internal paths are unexported so
Shaker keeps working), `debug_bh_shaker_env_vars` (secrets masked), `print_welcome_banner` (stderr).

## Using the libraries in your own script

```bash
#!/usr/bin/env bash
set -euo pipefail
. /opt/bytehawks/core/shaker/lib/shaker.libsh
detect_all
log_info "running on ${BH_SHAKER_OS_FAMILY}/${BH_SHAKER_ARCH} (${BH_SHAKER_DEPLOYMENT_ENVIRONMENT})"
pkg_install ca-certificates tzdata
wait_for_port db.example.com 5432 60 || die "database not reachable"
render_template /etc/myapp/myapp.conf.tmpl /etc/myapp/myapp.conf
```
