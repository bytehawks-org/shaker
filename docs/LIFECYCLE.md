# Lifecycle

The verbs map one-to-one onto what Bitnami split across `postunpack.sh`, `setup.sh`,
`entrypoint.sh` and `run.sh`, but are generic and driven by `runtime.spec`.

| Phase | When | Who | Idempotent | Bitnami equivalent |
|---|---|---|---|---|
| `install` | image build / provisioning | root | yes | `postunpack.sh` |
| `init` | every start | root or service uid | yes | `setup.sh` |
| `run` | every start | root → service user, or arbitrary uid | - | `entrypoint.sh` + `run.sh` |
| `stop` | host without supervisor | any | yes | - |
| `verify` | anytime (probe, cron, CI) | any (read-only) | read-only | - |

## Install

For each record of the spec:

* **user** `name|uid|gid|home` - group resolved by gid (created as the user's name if the gid does not
  exist); `gid=0` is the OpenShift convention. User: `useradd -r` below uid 1000, plain above; busybox
  `adduser -S` where `useradd` is missing; no home directory is created (declare it as a `dir`).
* **dir** `path|mode|owner` - created; owner applied **recursively**; a numeric mode (`0750`) is applied
  to the directory only, a symbolic one (`g+rwX`) recursively.
* **hook** directories are created so operators can mount scripts into them.
* state directory: group-owned by the service group and `g+rwX`, so `init` works as any uid of that group.

Fields used by `install` must not depend on runtime parameters (`${VAR}` without default fails).

## Init

```
1  pre_init hooks         always
2  persistence            for each persist|path|volume
3  templates              for each template|src|dest|mode
4  first_init hooks       only when the marker is missing (or --reinit)
5  post_init hooks        always
6  state + event          initialized_at, init_version, config_hash
```

### Hooks
Executable files, or non-executable `*.sh` (run with bash), in lexical order, from the directory
declared per stage. Any other file is ignored. A failing hook aborts `init` (recorded as
`init fail <stage>`) unless `BH_SHAKER_HOOKS_CONTINUE=true`. Hooks inherit the resolved parameters
and `BH_PKG_*`. Typical use: wait for a database, create a schema, load seed data from
`/docker-entrypoint-initdb.d`-style mounts.

### Persistence
`persist|<path>|<volume>`:
* volume not mounted / not writable → nothing happens, data stays in the container layer;
* volume empty and `<path>` has content → seeded with `cp -a`;
* `<path>` is then replaced by a symlink to the volume. Already linked → no-op.

### Templates
`template|<src>|<dest>|<mode>`: `<bundle>/assets/<src>` is rendered with `{{ NAME }}` /
`{{ NAME:-default }}` (all resolved parameters and `BH_PKG_*` available), written to a temporary file,
chmod-ed, chowned to the service user when running as root, and atomically renamed. The SHA-256 of the
result is stored in the state (`tpl.N.dest`, `tpl.N.sha256`) for drift detection. **Edit parameters,
not the generated file**: manual edits are reported as drift and overwritten by the next `init`.

### First-init marker
`<volume>/.bytehawks-<pkg>.initialized` when the package has a writable persistent volume, otherwise
`<state>/<pkg>.initialized`. A new container on an old volume does **not** repeat one-time setup; a
new volume does. `--reinit` forces it.

## Run

1. `init` (unless `--no-init`).
2. Argument vector = the `run` record with `${VAR}` expanded from the parameters + extra arguments
   after `--`. No shell is involved: arguments are never re-split or globbed.
3. Root with a declared user → `BH_SHAKER_*` cleaned, `exec_as_user uid gid cmd`
   (`setpriv`, `gosu`, `su-exec`; `runuser` with a warning because it stays as parent).
4. Otherwise → arbitrary-uid handling, `BH_SHAKER_*` cleaned, `exec`.

### Arbitrary uid
When the platform assigns a uid that has no passwd entry (OpenShift, `runAsUser` without a matching
user), many programs break on `getpwuid()`. `ensure_passwd_entry`:
1. `/etc/passwd` writable (group-0 image convention) → append `bytehawks:x:UID:GID:...`;
2. else `libnss_wrapper` found → private passwd/group files + `LD_PRELOAD` + `NSS_WRAPPER_*`;
3. else a warning; the service starts anyway.

### Daemon mode
`--daemon` re-invokes `shaker run <pkg> --no-init` detached (so the service `exec`s into the recorded
PID). The log and PID file are created and handed to the service user first, because a service that
writes its own PID file (nginx) or opens `/dev/stdout` could otherwise not open files created by root.

## Verify

| Check | FAIL when | WARN when |
|---|---|---|
| bundle | not found | - |
| requires | tool not in `PATH`, `<prefix>/bin`, `<deps>/bin` | - |
| user | missing or uid differs | - |
| dir | missing, owner differs, mode lacks requested bits | - |
| parameters | (resolution error aborts earlier, exit 1) | - |
| template | not rendered; **hash differs from the one recorded at init (drift)** | rendering now would differ (parameters changed) or no recorded hash |
| state | - | no install record |
| health | TCP closed / command non-zero | - |

Numeric modes are compared exactly on the low 9 bits; symbolic ones (`g+rwX`) check that the
requested bits are present.

## State and audit trail

`$BH_STATE` (default `/opt/bytehawks/var/lib/shaker`; falls back to `$TMPDIR/bytehawks-state-<uid>`
when not writable - then ephemeral):

```
nginx.state     installed_at= installed_version= installed_recipe= installed_user=
                first_init_at= initialized_at= init_version= config_hash=
                tpl.0.dest= tpl.0.sha256=  last_verify_at= last_verify_result=
nginx.initialized   (only without a persistent volume)
events.log      2026-10-23T06:00:08Z nginx init ok 1.28.0
                2026-10-23T06:00:10Z nginx verify 0 ok:8 warn:1 fail:1
```

* `installed_recipe` is the Distillery recipe hash: it answers "which exact build is this host
  running" and, compared with the bundle's, "was it upgraded since install".
* `config_hash` is a SHA-256 over all resolved parameters (secrets included, only the digest is stored).
* `events.log` is append-only; rotation is not implemented yet.
* In an image the state directory is created at build time with group write access, so runtime uids
  can update it; on a read-only root filesystem mount a volume or `emptyDir` at `$BH_STATE`.
