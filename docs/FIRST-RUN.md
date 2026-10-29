# First run on GitHub and on a real Alpine: checklist

Shaker's `ci.yml` (shellcheck, tests, a 6-distribution matrix) has **never run on GitHub**, and the code paths written for Alpine
(`restore`, `up`, `verify --files`) have only run against GNU tools. The checklist for the whole pipeline, where Shaker is one
consumer, is [Distillery's FIRST-RUN](https://github.com/bytehawks-org/distillery/blob/main/docs/FIRST-RUN.md); this one is
what is specific to Shaker. "Predicted" means predicted: write down what you observe.

## 1. `ci.yml` on the branch

| ☐ | Job | Predicted | If not |
|---|---|---|---|
| ☐ | `shellcheck` | clean on `bin/` and `lib/` (new: `seal.libsh`, `artifact.libsh`, `up.libsh`) | fix the finding; the usual suspects are intentional word splitting in `up.libsh` (`for dep in $(…)`) and `sed` patterns: add a targeted `# shellcheck disable=` with the reason, never a blanket one |
| ☐ | `tests` | 221 assertions, 0 failed. The signature tests need `gpg`; without it they print "skipped" | a distro without `gpg` in the container image: install it in the "bootstrap bash and git" step |
| ☐ | matrix `debian:12` | green | |
| ☐ | matrix `fedora:40`, `rockylinux:9` | green. `tar`, `sed`, `find` are GNU; `gpg` is `gnupg2` | |
| ☐ | matrix `opensuse/leap:15.6`, `archlinux:latest` | green | an old `bash` or a missing `which`: the tests assume bash ≥ 4.2 |
| ☐ | matrix **`alpine:3.20`** | **the one to watch**: BusyBox `tar`, `sed`, `find`, `readlink`, `mktemp`, `install`, `stat` (the tests call `stat -c %a`) | see below |

## 2. Alpine / BusyBox specifically

The new commands avoid GNU-only options on purpose (no `readlink -m`, no GNU `tar` extensions beyond `-tzf`, `-tvzf`, `-xzf`,
`--no-same-owner`), but this was never executed on BusyBox. In an `alpine:3.20` container with `bash` installed:

| ☐ | Run | Predicted | Likely culprit if not |
|---|---|---|---|
| ☐ | `bash tests/run.sh tests/test_artifact.sh` | all pass | `tar -tvzf` line format: the symlink pre-scan parses `l… user/group size date time name -> target`; BusyBox prints seconds in the time, GNU does not (the pattern accepts both) |
| ☐ | `bash tests/run.sh tests/test_seal.sh` | all pass | `mktemp -d` template, `sha256sum` output format, `gpg` missing (install `gnupg`) |
| ☐ | `bash tests/run.sh tests/test_up.sh` | all pass | `stat -c %a` is BusyBox-compatible; `sed -n "s/…//p"` with `head -n 1` should be |
| ☐ | with a **real Distillery musl artifact**: `shaker restore <artifact>` then `shaker verify <pkg> --files` | ok | the staging copy (`cp -a "$stage/." root/`): BusyBox `cp -a` keeps symlinks; check modes of `bin/*` |
| ☐ | `shaker restore` of a **glibc** artifact | refused with "built for glibc, this host uses musl" | `detect_libc` result: print `shaker detect` and compare |

If a BusyBox difference breaks something: reproduce in the container, add the failing case to the test file **first**, then fix
the library. If the fix needs GNU tools, prefer `apk add tar sed` documented in `docs/PORTABILITY.md` over complex shell.

## 3. Against real Distillery output

☐ Take the artifacts of a Distillery CI run (its checklist, step 4) and run on a clean container of each family:

```sh
export BH_ROOT=/opt/bytehawks BH_SHAKER_TRUSTED_FINGERPRINTS=<primary fingerprint> BH_SHAKER_REQUIRE_SIGNATURE=true
shaker restore bh--nifi--…tar.gz --require-signature    # after the same for temurin, or:
shaker up nifi --plan                                   # temurin, nifi
shaker up nifi && shaker verify nifi --files --require-signature
```

| ☐ | Check | Predicted |
|---|---|---|
| ☐ | `restore` with a valid signature by the pinned primary key | ok |
| ☐ | the same with a different fingerprint pinned | refused, nothing written |
| ☐ | `up nifi` after restoring only nifi (no temurin) | stops at the plan: "nifi depends on temurin, which is not installed" |
| ☐ | `up nifi` with a temurin of another build | stops: "built against temurin …, but … is installed" |
| ☐ | `verify --files` after the service ran for a while | ok: only `conf/` (mutable) changed; any other change is a real finding |
| ☐ | Alpine: the musl NiFi artifact | `up nifi --run`: record whether it starts (native libraries of some NARs may be glibc-only) |

## 4. When all of it is green

☐ Tag a release (`v0.4.0`), so Distillery can carry Shaker as a catalog unit and `packaging.shaker.package` can name a real
package. ☐ Update `ROADMAP.md` ("Known gaps": the CI matrix has run) and delete this file or keep it for the next platform.
