# Portability

Shaker must run on **any Linux distribution**, with or without the Bytehawks packages, on a minimal
container image or a 10-year-old enterprise VM.

## Support matrix

| Family | Distros exercised by the CI workflow | Package manager | libc |
|---|---|---|---|
| debian | Debian 12 (and Ubuntu: developed/tested here on 24.04) | apt-get | glibc |
| rhel | Fedora 40, Rocky 9 (RHEL, Alma, Oracle, Amazon, Photon, Azure Linux are mapped) | dnf, microdnf, yum, tdnf | glibc |
| suse | openSUSE Leap 15.6 (SLES mapped) | zypper | glibc |
| alpine | Alpine 3.20 | apk | musl |
| arch | Arch Linux | pacman | glibc |

An unknown distribution is handled through `ID_LIKE` in `os-release`; if that is missing too, family is
`unknown`, detection still works and every package manager is tried.
Architectures: amd64, arm64, armv7 (detected and exported; Shaker itself is architecture-neutral).
macOS/BSD/Windows are out of scope.

> Status: locally the suite passes on Ubuntu 24.04 (bash 5.2). The multi-distribution matrix is defined
> in `.github/workflows/ci.yml` and has to run on GitHub to be considered verified.

## Required

* `bash` ≥ 4.2 (RHEL/CentOS 7 era is the floor). Used from 4.x: associative arrays, `declare -g`,
  `${var,,}`, `printf -v`, `printf %(..)T`, `local -a`. **Not** used (>4.2): namerefs, `${var@Q}`,
  `mapfile -d`, `wait -n`.
* `cat cut tr grep sed find chmod chown mkdir mv ln cp date uname id ls mktemp sleep readlink` -
  coreutils, util-linux or busybox versions.
* a SHA-256 tool: `sha256sum`, `shasum`, or `openssl`.

## Optional (feature → tool)

| Feature | Tool | Fallback |
|---|---|---|
| JSON config | `jq` | `python3` |
| YAML config | `python3` + PyYAML | `yq` |
| drop privileges | `setpriv` (util-linux) | `gosu`, `su-exec`, `runuser`, `su` |
| arbitrary uid with read-only passwd | `libnss_wrapper` | warning only |
| VM / container detection | `systemd-detect-virt` | markers, cgroup, DMI |
| port check timeout | `timeout` | plain `/dev/tcp` |

## Rules enforced for contributors

1. No GNU-only flags: `realpath`, `readlink -f`, `sed -i`, `grep -P`, `date +%N`, `find -printf`,
   `stat -c`, `xargs -r`, `cp --reflink`, `mktemp --suffix`. (`ls -ldn` and `find -exec ... {} +` are the portable substitutes used.)
2. No bash > 4.2 features.
3. No dependency on systemd, on a particular package manager, or on a Bytehawks package.
4. Anything optional must degrade to a clear error or a documented fallback, never a stack trace.
5. Never `source` or `eval` data (config files, spec, manifests). Parse.
6. Never assume `/etc/passwd` is writable, root exists, a TTY is attached, or `$HOME` is set.
7. Every function that touches the system has a test hook or runs under `BH_SHAKER_DRY_RUN`/temp dirs.
8. Logs to stderr, results to stdout.

## Alpine / BusyBox specifics

* BusyBox has a `setpriv` applet that **cannot** change uid/gid. Shaker checks for util-linux's (`--reuid`);
  on Alpine install `su-exec` (`apk add su-exec`) or `util-linux`.
* Optional tools: `apk add jq python3 py3-yaml` for JSON/YAML configuration files.

## Bash on Alpine / busybox images

```dockerfile
RUN apk add --no-cache bash          # the only prerequisite
ENTRYPOINT ["/opt/bytehawks/core/shaker/bin/shaker", "run", "myapp"]
```
`bin/shaker` uses `#!/usr/bin/env bash`. busybox `adduser/addgroup` and `ls -ldn` are supported.

## Physical path rule

Binaries and generated configuration always use the **real** path (`/opt/bytehawks/...`). `/opt/bh` is
for humans and PATH convenience only; if it were baked in, relocating the tree would break RPATHs and
configs. Distillery builds with the real prefix for this reason.

## Package name mapping

`share/pkgmap.map` translates logical names:

```
openssl-dev|debian|libssl-dev
openssl-dev|rhel|openssl-devel
build-essential|rhel|gcc make        # one logical name, several packages
x|alpine|-                           # not needed on that family
```
A name without a mapping is passed through unchanged, so `pkg_install curl` works everywhere curl has the same name.
Add entries with a pull request; keep the logical name = the Debian name unless there is a reason not to.
