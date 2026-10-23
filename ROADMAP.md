# Roadmap

Status legend: ✅ done · 🚧 partial · ⬜ planned. Versions are indicative; pre-1.0 minors may break.
The roadmap is shared with [Distillery](https://github.com/bytehawks-org/distillery/blob/main/ROADMAP.md):
items marked **(contract)** need a change on both sides.

## Where we are (v0.3.0)

| Phase | Scope | State |
|---|---|---|
| 0 | Fix prototype bugs, tests, CI | ✅ |
| 1 | Bitnami-equivalent primitives: validation, fs/users, files/templates, net, hooks, logging, packages | ✅ |
| 2 | Rosetta: CLI/env/alias/`_FILE`/config-file resolver, typed validation, provenance | ✅ |
| 3 | Distillery executes builds: checksums, dependencies, bundle | ✅ (Distillery 0.3.0) |
| 4 | Lifecycle verbs: `install init run stop verify status unit`, state, events, drift | ✅ |
| 5 | End-to-end package: nginx built from source and run through Shaker | ✅ (manual + contract test) |
| 6 | Persistence, arbitrary uid / OpenShift, service helpers | ✅ basic (see 0.4+) |

## 0.4 - operability

| Item | Detail | Why |
|---|---|---|
| ⬜ `shaker health <pkg>` | health only, exit code, no state writes, fast; for probes | `verify` writes state; probes need a pure check |
| ⬜ JSON output | `--format=json` for `verify`, `status`, `env`, `detect` | machines, dashboards, CI gates |
| ⬜ Persist CLI parameters | optional `init --save` writing a drop-in so `verify`/`run` need no flags | today flags are per invocation |
| ⬜ `events.log` rotation + JSON lines | size cap, optional syslog/journald | audit retention |
| ⬜ Secret generation | `generate` flag in the map: create a random value once, store `0600`, reuse | Bitnami `ALLOW_EMPTY_PASSWORD`/auto-password parity without insecure defaults |
| ⬜ Native config validation hook | `validate` command in the spec (`nginx -t`) run after rendering, before start | fail before restart, not during |
| ⬜ Reload | `shaker reload <pkg>`: re-init + signal (`reload_signal` in the spec) | config change without restart |

## 0.5 - lifecycle completeness

| Item | Detail |
|---|---|
| ⬜ `uninstall` / `purge` | remove user, directories, state, symlinks; keep data unless `--purge-data` |
| ⬜ Upgrade path | compare `installed_recipe`/`init_version` with the bundle, run `upgrade` hooks (`from → to`), refuse downgrades |
| ⬜ Multi-package orchestration | `shaker up <app>`: honour `manifest.depends` ordering, init dependencies first |
| ⬜ Rollback | keep the previous rendered config + state snapshot, `shaker rollback` |
| ⬜ Transactional `init` | render everything to a staging dir, validate, then swap |
| ⬜ OpenRC / SysV generators | `shaker unit --type=openrc|sysv` for non-systemd legacy hosts |
| ⬜ Windows/WSL notes | document WSL2 usage (development environment) |

## 0.6 - ecosystem & integration

| Item | Detail |
|---|---|
| ⬜ Kubernetes generator | `shaker k8s <pkg>` → Deployment/StatefulSet, ConfigMap, Secret references, probes from the bundle (**contract**) |
| ⬜ Helm/Kustomize skeleton from the map | parameters become values/overlays |
| ⬜ `shaker docs <pkg>` | generate the parameter reference (markdown) from the map |
| ⬜ Shell completion | bash/zsh for verbs, packages, declared flags |
| ⬜ Bundle signature | verify a detached signature (minisign/cosign) of the bundle before `install` (**contract**) |
| ⬜ Compliance report | `shaker report` aggregating verify/state into a NIS2-friendly evidence document |
| ⬜ More distro coverage | Debian/Ubuntu old LTS, SLES, Amazon Linux in CI; `pkgmap` growth |

## 1.0 criteria

* bundle schema frozen and versioned (`schema: 1` negotiated, clear errors on mismatch);
* all verbs have JSON output and stable exit codes;
* upgrade, uninstall and rollback exist and are tested;
* CI green on the full distro matrix (including musl) for 3 consecutive months;
* at least five real packages in Distillery (e.g. nginx, postgresql, valkey, haproxy, mariadb) running through the lifecycle in containers *and* on VMs;
* security review of hooks, state and privilege-drop paths.

## Known gaps today (tracked, honest)

* The multi-distribution CI matrix is defined but has not been observed running on GitHub yet.
* YAML/JSON configuration needs an optional tool; no pure-bash parser.
* `events.log` is unbounded; no `uninstall`; no upgrade logic; `depends` informational only at runtime.
* `shaker unit` targets systemd only.
* `run --daemon` reaps nothing: it is a convenience for hosts without a supervisor, not a supervisor.
* Test coverage of `os.libsh` uses fixtures and fake roots, not real VM/bare-metal hosts.
* `pkgmap.map` is small (5 logical names).

## Non-goals

A package manager, a process supervisor, a configuration-management DSL, support for non-Linux systems.
