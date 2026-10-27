# Testing and contributing

## Run the tests

```sh
./tests/run.sh                       # everything (201 assertions)
./tests/run.sh tests/test_rosetta.sh # one file
```

No test framework is required (no bats): `tests/run.sh` is ~40 lines, sources the libraries and each
`tests/test_*.sh`, and provides `assert_eq`, `assert_ok`, `assert_fail`, `assert_contains`, `new_tmp`.
Temp data lives in `tests/.tmp` (removed at the end; git-ignored). Tests run as root or as a normal user:
root-only checks (arbitrary uid with `setpriv`) are skipped otherwise, and lifecycle tests use
`BH_SHAKER_ALLOW_NONROOT=true`.

| File | Covers |
|---|---|
| `test_validate.sh` | booleans, case, ports, enums, secret-name detection |
| `test_os.sh` | os-release fixtures for 7 distributions → family; container / VM / physical / Kubernetes markers with `systemd-detect-virt` hidden |
| `test_pkg.sh` | command construction for every package manager, logical name mapping, dry-run |
| `test_file.sh` | literal replace, `ensure_line_in_file`, `render_template` (defaults, verbatim values, no evaluation, missing variable), `wait_for_port` |
| `test_rosetta.sh` | precedence, aliases, native twins, `_FILE`, conflicts, validation, env/ini/json/yaml/drop-ins, provenance masking, end-to-end `exec` |
| `test_state.sh` | state get/set/unset, events, fallback dir, `expand_vars`, SHA-256, PID helpers |
| `test_fs.sh` | mode helpers, recursive permissions, arbitrary uid, bootstrap |
| `test_lifecycle.sh` | install → init → verify (drift, parameter change, health) → run → daemon/stop → unit, with a hand-written bundle |
| `test_integration.sh` | **Distillery → Shaker contract** with a package built from a local tarball (needs a Distillery checkout and PyYAML; skipped otherwise; `DISTILLERY_HOME` to point at it) |

Fixtures: `tests/fixtures/os-release.*`.
Test hooks in the libraries: `BH_SHAKER_OS_RELEASE_FILE`, `BH_SHAKER_PROC_ROOT`, `SHAKER_PASSWD_FILE`.

## CI

`.github/workflows/ci.yml`
* `test`: `shellcheck -x -e SC2034 bin/shaker lib/*.libsh` + `tests/run.sh` on Ubuntu;
* `test-portability`: `tests/run.sh` inside Alpine 3.20, Fedora 40, Rocky 9, openSUSE Leap 15.6, Arch, Debian 12 containers.

## Manual end-to-end (what was done to validate 0.3.0)

Distillery built nginx 1.28.0 against its own openssl 3.5.4, zlib 1.3.1, pcre2 10.43 into a staged root,
then:

```sh
export BH_ROOT=/opt/bhtest
shaker install nginx                       # user nginx 1001:0, run/conf/html 1001:0
shaker run nginx --port=18080 --daemon     # master + workers as uid 1001, curl → 200, Server: nginx
shaker verify nginx                        # 10 ok; after a manual edit: FAIL ... DRIFT
shaker stop nginx
setpriv --reuid=54321 --regid=0 --clear-groups shaker run nginx --port=18081   # arbitrary uid, foreground
```

## Writing code

* Follow `docs/PORTABILITY.md`. Quote every expansion, `local` every variable, return codes not `exit`
  (except `die` and the dispatcher).
* Document every function with the header block used throughout (`Function`, `Usage`, `Returns`).
* A new feature = a test in the matching file + a line in `CHANGELOG.md` (`Unreleased`).
* New parameter type → `validate_type` + Distillery `RUNTIME_TYPES` + `docs/ROSETTA.md`.
* New spec record → `spec.libsh` + Distillery `bundle.spec_lines` + both `BUNDLE.md`/`LIFECYCLE.md` + the contract test.
* Commit messages: imperative, explain the *why* in the body.
