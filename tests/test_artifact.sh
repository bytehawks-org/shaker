# artifact.libsh: `shaker restore` of a Distillery artifact. The artifacts are written by hand (tar + sidecar): no Distillery.

_artifact_make() {  # <dir> [name] : <name>.tar.gz + <name>.json for package "demo" 1.0, root = $BH_ROOT
    local dir="$1" name="${2:-bh_demo_stable_application_amd64_1.0_abcdef012345}" src
    src="$(mktemp -d "${dir}/src.XXXXXX")"
    mkdir -p "${src}/demo/bin" "${src}/demo/.bytehawks"
    printf '#!/bin/sh\n' > "${src}/demo/bin/tool"; chmod 755 "${src}/demo/bin/tool"
    ln -s tool "${src}/demo/bin/alias"
    printf 'BH_PKG_NAME=demo\nBH_PKG_RECIPE=%s\n' "$(printf 'ab%.0s' {1..32})" > "${src}/demo/.bytehawks/manifest.env"
    tar -czf "${dir}/${name}.tar.gz" -C "${src}" demo
    rm -rf "${src}"
    _artifact_sidecar "${dir}" "${name}"
}

_artifact_sidecar() {  # <dir> <name> [arch] [libc] [root]
    local dir="$1" name="$2" arch="${3:-amd64}" libc="${4:-glibc}" root="${5:-${BH_ROOT}}"
    cat > "${dir}/${name}.json" <<JSON
{
  "arch": "${arch}",
  "libc": "${libc}",
  "name": "${name}",
  "package": "demo",
  "prefix": "${root}/demo",
  "recipe_sha256": "$(printf 'ab%.0s' {1..32})",
  "root": "${root}",
  "schema": 1,
  "sha256": "$(sha256_of_file "${dir}/${name}.tar.gz")",
  "tag": "application",
  "version": "1.0"
}
JSON
}

t="$(new_tmp)"; export BH_ROOT="${t}/root"; mkdir -p "${t}/a"
detect_arch; detect_libc
art="${t}/a/bh_demo_stable_application_amd64_1.0_abcdef012345"

_artifact_make "${t}/a"; _artifact_sidecar "${t}/a" "$(basename "${art}")" "${BH_SHAKER_ARCH}" "${BH_SHAKER_LIBC}"
assert_eq "demo" "$(_artifact_field "${art}.json" package)" "restore: sidecar fields are read"
assert_eq "${BH_ROOT}" "$(_artifact_field "${art}.json" root)" "restore: root field"

assert_ok "restore: a valid artifact is unpacked" artifact_restore "${art}.tar.gz"
assert_ok "restore: the files are there, with their modes" test -x "${BH_ROOT}/demo/bin/tool"
assert_eq "tool" "$(readlink "${BH_ROOT}/demo/bin/alias")" "restore: symlinks are kept"
assert_eq "" "$(ls -A "${BH_ROOT}" | grep '^\.restore\.' || true)" "restore: no staging directory is left behind"
out="$(artifact_restore "${art}.tar.gz" 2>&1)"
assert_contains "already installed" "${out}" "restore: the same recipe is not unpacked twice"

# integrity
rm -rf "${BH_ROOT}/demo"
cp "${art}.tar.gz" "${t}/bad.tar.gz"; cp "${art}.json" "${t}/bad.json"; echo x >> "${t}/bad.tar.gz"
assert_fail "restore: tarball that does not match its sha256" artifact_restore "${t}/bad.tar.gz" --sidecar="${t}/bad.json"
assert_fail "restore: missing sidecar" artifact_restore "${t}/bad.tar.gz" --sidecar="${t}/none.json"
assert_eq "" "$(ls -A "${BH_ROOT}/demo" 2>/dev/null)" "restore: nothing written when a check fails"

# platform and root
n="bh_demo_stable_application_arm64_1.0_abcdef012345"; mkdir -p "${t}/b"
_artifact_make "${t}/b" "${n}"; _artifact_sidecar "${t}/b" "${n}" "arm64" "${BH_SHAKER_LIBC}"
if [[ "${BH_SHAKER_ARCH}" != "arm64" ]]; then
    assert_fail "restore: artifact of another architecture" artifact_restore "${t}/b/${n}.tar.gz"
    assert_ok "restore: ... unless the mismatch is allowed" env BH_SHAKER_ALLOW_PLATFORM_MISMATCH=true BH_ROOT="${BH_ROOT}" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; detect_arch; detect_libc; artifact_restore '${t}/b/${n}.tar.gz'"
    rm -rf "${BH_ROOT}/demo"
fi
n="bh--demo--stable--application--amd64--1.0--000000000000"; mkdir -p "${t}/c"
_artifact_make "${t}/c" "${n}"; _artifact_sidecar "${t}/c" "${n}" "${BH_SHAKER_ARCH}" "${BH_SHAKER_LIBC}" "/somewhere/else"
assert_fail "restore: artifact built for another root" artifact_restore "${t}/c/${n}.tar.gz"

# Two fixtures need GNU tar to be crafted (--transform to write "../x", -r to append behind a symlink); BusyBox cannot build
# them, so they are skipped there. `restore` itself must work with whatever tar the host has.
_gnu_tar() { tar --version 2>/dev/null | grep -q 'GNU tar'; }

# hostile archives (the sha256 matches: the archive itself is the attack)
mkdir -p "${t}/h" "${t}/h/src/demo"
n="bh--demo--stable--application--amd64--1.0--111111111111"
printf 'x' > "${t}/h/src/demo/f"
if _gnu_tar; then
    tar -czf "${t}/h/${n}.tar.gz" --transform 's,^,../,' -C "${t}/h/src" demo
    _artifact_sidecar "${t}/h" "${n}" "${BH_SHAKER_ARCH}" "${BH_SHAKER_LIBC}"
    assert_fail "restore: member with .. is refused" artifact_restore "${t}/h/${n}.tar.gz"
else
    echo "  (skipped: a '..' member needs GNU tar to craft)"
fi

n="bh--demo--stable--application--amd64--1.0--222222222222"
rm -rf "${t}/h/src"; mkdir -p "${t}/h/src/demo"; ln -s ../../../../etc/passwd "${t}/h/src/demo/escape"
tar -czf "${t}/h/${n}.tar.gz" -C "${t}/h/src" demo
_artifact_sidecar "${t}/h" "${n}" "${BH_SHAKER_ARCH}" "${BH_SHAKER_LIBC}"
assert_fail "restore: symlink that leaves the tree is refused" artifact_restore "${t}/h/${n}.tar.gz"
assert_eq "" "$(ls -A "${BH_ROOT}" | grep -v '^demo$' || true)" "restore: staging removed after a refusal"

n="bh--demo--stable--application--amd64--1.0--333333333333"
rm -rf "${t}/h/src"; mkdir -p "${t}/h/src/demo"; ln -s /etc/passwd "${t}/h/src/demo/abs"
tar -czf "${t}/h/${n}.tar.gz" -C "${t}/h/src" demo
_artifact_sidecar "${t}/h" "${n}" "${BH_SHAKER_ARCH}" "${BH_SHAKER_LIBC}"
assert_fail "restore: absolute symlink is refused" artifact_restore "${t}/h/${n}.tar.gz"
assert_fail "restore: neither is anything of it installed" test -e "${BH_ROOT}/demo/abs"

n="bh--demo--stable--application--amd64--1.0--444444444444"
if _gnu_tar; then
    rm -rf "${t}/h/src" "${t}/h/src2"; mkdir -p "${t}/h/src/demo" "${t}/h/src2/demo/l"
    ln -s ../../../../tmp "${t}/h/src/demo/l"; printf 'x' > "${t}/h/src2/demo/l/evil"
    tar -cf "${t}/h/${n}.tar" -C "${t}/h/src" demo/l; tar -rf "${t}/h/${n}.tar" -C "${t}/h/src2" demo/l/evil
    gzip -f "${t}/h/${n}.tar"
    _artifact_sidecar "${t}/h" "${n}" "${BH_SHAKER_ARCH}" "${BH_SHAKER_LIBC}"
    assert_fail "restore: member written through an archive symlink is refused" artifact_restore "${t}/h/${n}.tar.gz"
    assert_fail "restore: ... and nothing was written outside" test -e /tmp/evil
else
    echo "  (skipped: a member behind a symlink needs GNU tar to craft)"
fi

assert_ok "inside: sibling link" _artifact_stays_inside "demo/bin" "tool"
assert_ok "inside: up one level, still inside" _artifact_stays_inside "demo/bin" "../lib/x.so"
assert_fail "inside: up past the root" _artifact_stays_inside "demo/bin" "../../../etc"
assert_fail "inside: up past the root from the top" _artifact_stays_inside "." ".."

# signatures
if command -v gpg >/dev/null 2>&1; then
    export GNUPGHOME="${t}/gnupg"; mkdir -m 700 "${GNUPGHOME}"
    gpg --batch --quiet --passphrase '' --quick-generate-key 'Artifact Test <art@example.com>' ed25519 sign never 2>/dev/null
    fpr="$(gpg --batch --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"
    rm -rf "${BH_ROOT}/demo" "${t}/s"; mkdir -p "${t}/s"
    n="bh_demo_stable_application_amd64_1.0_abcdef012345"
    _artifact_make "${t}/s"; _artifact_sidecar "${t}/s" "${n}" "${BH_SHAKER_ARCH}" "${BH_SHAKER_LIBC}"

    assert_fail "restore: unsigned artifact when a signature is required" env BH_SHAKER_REQUIRE_SIGNATURE=true BH_ROOT="${BH_ROOT}" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; detect_arch; detect_libc; artifact_restore '${t}/s/${n}.tar.gz'"
    gpg --batch --quiet --armor --detach-sign -o "${t}/s/${n}.json.asc" "${t}/s/${n}.json"
    assert_ok "restore: signed by a pinned signer" env BH_SHAKER_TRUSTED_FINGERPRINTS="${fpr}" BH_SHAKER_REQUIRE_SIGNATURE=true BH_ROOT="${BH_ROOT}" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; detect_arch; detect_libc; artifact_restore '${t}/s/${n}.tar.gz'"
    rm -rf "${BH_ROOT}/demo"
    assert_fail "restore: signed by someone who is not pinned" env BH_SHAKER_TRUSTED_FINGERPRINTS="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" BH_ROOT="${BH_ROOT}" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; detect_arch; detect_libc; artifact_restore '${t}/s/${n}.tar.gz'"
    sed -i 's/"version": "1.0"/"version": "9.9"/' "${t}/s/${n}.json"        # sidecar edited after signing (hash fields still match)
    assert_fail "restore: sidecar changed after signing" env BH_SHAKER_TRUSTED_FINGERPRINTS="${fpr}" BH_ROOT="${BH_ROOT}" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; detect_arch; detect_libc; artifact_restore '${t}/s/${n}.tar.gz'"
    unset GNUPGHOME
else
    echo "  (signature checks skipped: gpg not installed)"
fi
export BH_ROOT="${TESTS_DIR}/.tmp/root"
