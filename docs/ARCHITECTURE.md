# Architecture

## 1. Purpose and scope

Shaker normalizes, standardizes and audits software installations in two very different worlds
with **one declarative model**:

* **containers / pods**: configuration arrives as CLI arguments, environment variables and mounted
  secret files; the service must be PID 1, usually with an arbitrary non-root uid;
* **legacy servers / VMs**: configuration lives in files under `/opt/bytehawks/etc`, the service is
  started by systemd (or by hand), accounts and permissions are provisioned once.

It is *not* a package manager, a process supervisor or a configuration-management tool. It
complements them: `shaker pkg` drives the host package manager only to install prerequisites, and
`shaker unit` hands supervision to systemd.

## 2. Two repositories, one contract

```
                 declarative                                     imperative, idempotent
┌─────────────────────────────────────┐   bundle    ┌──────────────────────────────────────┐
│ Distillery                          │  (files)    │ Shaker                               │
│  packages.yaml  config.yaml         │────────────►│  reads ONLY the bundle               │
│  fetch → verify sha256 → build      │             │  install · init · run · verify       │
│  recipe hash (Merkle over deps)     │             │  state files + event log              │
└─────────────────────────────────────┘             └──────────────────────────────────────┘
```

The bundle is the whole interface. It lives in the package prefix (`<prefix>/.bytehawks/`, for
libraries `<deps>/.bytehawks/<lib>/`):

| File | Written by | Read by | Content |
|---|---|---|---|
| `manifest.json` | Distillery | humans, tooling | identity, source URL, source sha256, recipe sha256, dependencies, build time |
| `manifest.env` | Distillery | Shaker | `BH_PKG_NAME/VERSION/VARIANT/PREFIX/RECIPE` exported to templates, hooks, run command |
| `rosetta.map` | Distillery | Shaker | parameters ([ROSETTA](ROSETTA.md)) |
| `runtime.spec` | Distillery | Shaker | user, dirs, persistence, templates, hooks, run, stop signal, PID file, health, required tools |
| `assets/` | Distillery | Shaker | templates and hooks shipped with the package |

Both text formats are line oriented with `|` as separator **on purpose**: Shaker parses them in
pure bash, so a minimal image needs no YAML/JSON tool. The YAML stays on the Distillery side where
Python is available. The formats are specified in the Distillery repository (`docs/BUNDLE.md`).

Rule of thumb: *anything that varies per application is data in the bundle; Shaker contains no
`if package == ...`*.

## 3. Library structure

```
bin/shaker              dispatcher (argument parsing only, no logic)
lib/shaker.libsh        loader (sources everything, housekeeping, banner)
lib/core.libsh          bash check, path layout (BH_ROOT & co), bootstrap
lib/validate.libsh      booleans, case, typed validation, secret-name detection
lib/log.libsh           levelled logging to stderr
lib/os.libsh            deployment / OS / family / init / arch / libc / package manager detection
lib/pkg.libsh           distro-agnostic package manager front-end
lib/fs.libsh            users, permissions, directories, exec_as_user, arbitrary uid
lib/file.libsh          replace_in_file, render_template, expand_vars, sha256
lib/net.libsh           is_port_open, wait_for_port (/dev/tcp)
lib/hook.libsh          run_hooks
lib/rosetta.libsh       parameter model and resolver
lib/state.libsh         state files, event log
lib/service.libsh       PID-file helpers
lib/spec.libsh          bundle reader (runtime.spec, manifest.env)
lib/seal.libsh          platform, bundle digest and signature, installed-files check
lib/artifact.libsh      shaker restore: verified unpacking of a Distillery artifact
lib/up.libsh            shaker up: dependency order from BH_PKG_DEPENDS
lib/lifecycle.libsh     the verbs
share/pkgmap.map        logical → real package names per family
assets/banner.txt
```

Libraries only define functions; sourcing them has no side effect other than computing paths
(`shaker_init_paths`). Everything is function-level documented ([LIBRARY](LIBRARY.md)).

## 4. Data flow of a start

```
shaker run nginx --port=8081
  │ detect_all                       deployment, OS, family, init, arch, libc, package manager
  │ spec_load                        bundle → SPEC_*, export BH_PKG_*
  │ lifecycle_resolve                rosetta map + config file + CLI + env → validated, exported
  │ lifecycle_init                   pre_init → persistence → templates → first_init → post_init
  │                                  └ state_set / state_event (what, when, hash)
  │ _lifecycle_argv                  expand ${VAR} in the declared command (+ extra args)
  └ cleanup BH_SHAKER_* ; exec       as the declared user when root, else as the current uid
```

## 5. Design decisions

| Decision | Rationale |
|---|---|
| bash ≥ 4.2, no other runtime | present on every distro including 2015-era enterprise ones; Alpine needs one `apk add bash`. Associative arrays and `printf %(..)T` are the only >4.0 features used |
| Config files **parsed, never sourced** | a configuration file must not be able to run code as root |
| `${VAR}` expansion is a 40-line function, not `eval`/`envsubst` | no code execution, no dependency, same behaviour everywhere |
| `exec`, not a wrapper | the service is PID 1 and receives container signals; no zombie-reaping shim to maintain (use `--init`/`tini` if the service forks children without reaping them) |
| Group-0 + `g+rwX` model | any uid in the root group can write, so OpenShift/restricted PodSecurity work without per-uid images |
| State is plain `KEY=VALUE` | greppable, diffable, readable in an incident with no tooling; atomic rewrite via rename |
| Drift = SHA-256 of rendered files | cheap and unambiguous; separates "someone edited the file" (FAIL) from "parameters changed, re-run init" (WARN) |
| First-init marker follows the data | on a persistent volume the marker lives on the volume, so a re-created container does not re-run one-time setup, a fresh volume does |
| Fail closed on parameters | unknown CLI flag, invalid type, missing required, `X` and `X_FILE` both set, unset template variable → error before anything is touched |
| Secrets never printed | `explain` masks `secret` types and secret-looking names; debug dump masks them; state stores only a hash of the parameters |

## 6. Failure model

* Every verb returns non-zero on failure and writes an event (`init fail templates`, ...).
* `init` is **not transactional**: a failure after persistence/templates leaves those applied. All
  steps are idempotent, so the fix is to correct the cause and run again.
* `verify` is read-only and safe at any time (cron, probe, CI).
* `install` requires root (or `BH_SHAKER_ALLOW_NONROOT=true`, which skips account and ownership
  work; used by tests and rootless image builds).

## 7. What Shaker deliberately does not do (yet)

Uninstall/rollback, multi-package orchestration (`depends` is recorded but not acted upon), upgrade
migrations between versions, structured (JSON) output, OpenRC/sysv unit generation, log rotation of
`events.log`. See [ROADMAP](../ROADMAP.md).
