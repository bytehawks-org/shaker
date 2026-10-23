# Changelog

All notable changes to Shaker. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning: [SemVer](https://semver.org/) (pre-1.0: minor versions may break).

## [0.3.1] - 2026-10-23

### Fixed (found by the first CI run on GitHub)
- Alpine / BusyBox: `setpriv` exists but cannot change uid/gid; `exec_as_user` and `run_as_user` now require the
  util-linux implementation (`has_setpriv`) and fall back to `gosu`/`su-exec` (`apk add su-exec`).
- `groupadd` flags built with an unquoted command substitution (shellcheck SC2046).
- Tests: JSON/YAML configuration tests are skipped when neither `jq`/`python3` nor `python3`+PyYAML/`yq` exist, so
  the suite passes on minimal images (verified with a PATH without python3, jq and yq).
- CI: `shellcheck` fails only on warnings and above (the `. "${dir}/x.libsh"` info notices are expected);
  the portability matrix no longer cancels the other distributions when one fails (`fail-fast: false`) and
  installs the optional tools on Alpine and Debian.

## [0.3.0] - 2026-10-23

### Added
- **Declarative lifecycle verbs** driven by the Distillery bundle: `install`, `init`, `run`,
  `stop`, `verify`, `status`, `unit` (`lib/lifecycle.libsh`, `lib/spec.libsh`).
  - `install`: service user/group (numeric or named gid, gid 0 supported), directories with owner
    and mode (numeric = directory only, symbolic such as `g+rwX` = recursive), hook directories,
    state-directory permissions for the service group.
  - `init`: `pre_init` hooks, persistence seeding and symlink to the volume, template rendering
    (atomic, owned by the service user, SHA-256 recorded), `first_init` hooks once (marker on the
    persistent volume when present), `post_init` hooks, state and audit event.
  - `run`: init + `exec` as PID 1 with privileges dropped (`setpriv`/`gosu`/`su-exec`, `runuser` as
    last resort); `--daemon` with PID file and log, `--no-init`, extra arguments after `--`.
  - `verify`: bundle, required tools, user, directory owner/mode, parameter validity, template
    drift (manual edits) and pending parameter changes, state, TCP/command health; `--strict`,
    `--no-health`.
  - `unit`: hardened systemd unit (`NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`,
    `ReadWritePaths`, stop signal from the package).
- `lib/state.libsh`: per-package state files, atomic updates, append-only event log, private
  fallback state directory when `BH_STATE` is not writable.
- `lib/service.libsh`: PID-file helpers (`service_start_detached`, `service_stop`, `is_service_running`).
- `lib/fs.libsh`: `exec_as_user`, `ensure_passwd_entry` (arbitrary uid: writable `/etc/passwd` or
  `nss_wrapper`).
- `expand_vars` (`${NAME}` / `${NAME:-default}`, never evaluated), `sha256_of_file`, `sha256_of_string`.
- `BH_PKG_*` variables (name, version, variant, prefix, recipe) available to templates, hooks and the
  run command, read from the bundle `manifest.env`.
- Documentation set (`docs/`), `ROADMAP.md`, this changelog.
- Integration test of the Distillery → Shaker contract (`tests/test_integration.sh`).

### Changed
- `shaker env` / `exec` reuse the lifecycle argument parser; the Rosetta map defaults to the bundle.
- `is_secret_name` no longer masks names such as `SERVER_TOKENS`.
- `ensure_user_exists` / `ensure_group_exists` create system accounts only below uid/gid 1000.

### Fixed
- Rendered files were owned by root when `init` ran as root: now owned by the service user.
- Daemonized services could not open their log or PID file after dropping privileges.

## [0.2.0] - 2026-10-23

### Added
- **Rosetta** (`lib/rosetta.libsh`): one canonical environment variable per parameter from CLI flags,
  env, `*_FILE` secrets, upstream aliases, configuration files (env, ini, json, yaml, drop-ins) and
  defaults; typed validation; provenance (`--format=explain`); `native_env` twins.
- `bin/shaker` dispatcher: `detect`, `env`, `exec`, `render`, `pkg`, `hooks`, `wait-for`,
  `bootstrap`, `banner`, `version`.
- Filesystem layout `/opt/bytehawks` (+ `/opt/bh` symlink), relocatable libraries (`core.libsh`).
- Distro-agnostic detection without systemd (container markers, cgroups, DMI), OS family, init
  system, architecture, libc.
- `pkg_*` front-end for apt, dnf, microdnf, yum, tdnf, zypper, apk, pacman with logical names
  (`share/pkgmap.map`) and dry-run.
- Bitnami-equivalent libraries: `validate`, `fs`, `file` (`replace_in_file`, `render_template`),
  `net` (`wait_for_port` via `/dev/tcp`), `hook`.
- Log levels (`BH_SHAKER_LOG_LEVEL`, `BH_SHAKER_DEBUG`), secret redaction.
- Test runner, fixtures for 7 os-release files, CI workflow with a 6-distribution matrix.

### Fixed
- VM detection never worked: `normalize_boolean "kvm"` returned `false`.
- `detect_os` executed the output of `lsb_release` as a command.
- Detection exported nothing without `systemd-detect-virt` (broke under `set -u`).
- `cleanup_bh_shaker_env_vars` removed Shaker's own paths.
- Invalid ANSI colour code for the module name.

### Removed
- `bin/shaker.sh` (replaced by `bin/shaker`).

## [0.1.0] - 2025-12-28

### Added
- Initial prototype: `normalize_boolean`, `normalize_case`, OS / deployment / package-manager
  detection, coloured logging, welcome banner, cleanup/debug of `BH_SHAKER_*` variables.
