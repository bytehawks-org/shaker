# seal.libsh: platform, bundle digest, signature, installed files. No Distillery needed: bundles are written by hand.

_seal_bundle() {  # <dir> : a minimal sealed bundle whose installed files live under $BH_ROOT/demo
    local dir="$1"
    mkdir -p "${dir}" "${BH_ROOT}/demo/bin" "${BH_ROOT}/demo/conf"
    printf 'tool\n' > "${BH_ROOT}/demo/bin/tool"
    printf 'conf=1\n' > "${BH_ROOT}/demo/conf/app.conf"
    ln -sf tool "${BH_ROOT}/demo/bin/alias"
    printf 'BH_PKG_NAME=demo\nBH_PKG_VERSION=1.0\nBH_PKG_PREFIX=%s/demo\nBH_PKG_ARCH=amd64\nBH_PKG_LIBC=glibc\n' "${BH_ROOT}" > "${dir}/manifest.env"
    printf '{}\n' > "${dir}/manifest.json"
    printf 'mutable|%s/demo/conf\n' "${BH_ROOT}" > "${dir}/runtime.spec"
    : > "${dir}/rosetta.map"
    {
        printf '%s  demo/bin/tool\n' "$(sha256_of_file "${BH_ROOT}/demo/bin/tool")"
        printf '%s  demo/bin/alias\n' "$(sha256_of_string tool)"
        printf '%s  demo/conf/app.conf\n' "$(sha256_of_file "${BH_ROOT}/demo/conf/app.conf")"
        printf '%s  demo/bin/\n' "$(printf '%64s' | tr ' ' '-')"
    } > "${dir}/files.sha256"
    local f
    for f in manifest.json manifest.env rosetta.map runtime.spec files.sha256; do
        printf '%s  %s\n' "$(sha256_of_file "${dir}/${f}")" "${f}"
    done > "${dir}/bundle.sha256"
}

t="$(new_tmp)"; export BH_ROOT="${t}/root"
bundle="${t}/bundle"; _seal_bundle "${bundle}"

# platform
out="$(BH_PKG_ARCH=amd64 BH_PKG_LIBC=glibc BH_SHAKER_ARCH=amd64 BH_SHAKER_LIBC=glibc seal_check_platform)"; rc=$?
assert_eq "0:amd64/glibc" "${rc}:${out}" "platform: same arch and libc"
out="$(BH_PKG_ARCH=amd64 BH_PKG_LIBC=glibc BH_SHAKER_ARCH=amd64 BH_SHAKER_LIBC=musl seal_check_platform)" && rc=0 || rc=$?
assert_eq "1:built for glibc, this host uses musl" "${rc}:${out}" "platform: glibc build on a musl host"
out="$(BH_PKG_ARCH=arm64 BH_PKG_LIBC=glibc BH_SHAKER_ARCH=amd64 BH_SHAKER_LIBC=glibc seal_check_platform)" && rc=0 || rc=$?
assert_eq "1:built for arm64, this host is amd64" "${rc}:${out}" "platform: other architecture"
out="$(BH_PKG_ARCH= BH_PKG_LIBC= seal_check_platform)" && rc=0 || rc=$?
assert_eq "2" "${rc}" "platform: bundle without platform fields is not an error"
out="$(BH_PKG_ARCH=amd64 BH_PKG_LIBC=glibc BH_SHAKER_ARCH=amd64 BH_SHAKER_LIBC=unknown seal_check_platform)" && rc=0 || rc=$?
assert_eq "0" "${rc}" "platform: undetected host libc is not a mismatch"

# digest
out="$(seal_check_digest "${bundle}")" && rc=0 || rc=$?
assert_eq "0:5 files match" "${rc}:${out}" "digest: intact bundle"
echo "# x" >> "${bundle}/runtime.spec"
out="$(seal_check_digest "${bundle}")" && rc=0 || rc=$?
assert_eq "1:modified runtime.spec" "${rc}:${out}" "digest: modified file"
_seal_bundle "${bundle}"
mv "${bundle}/rosetta.map" "${bundle}/rosetta.gone"
out="$(seal_check_digest "${bundle}")" && rc=0 || rc=$?
assert_eq "1:missing rosetta.map" "${rc}:${out}" "digest: missing file"
mv "${bundle}/rosetta.gone" "${bundle}/rosetta.map"
printf '%s  ../etc/passwd\n' "$(printf '%64s' | tr ' ' 0)" >> "${bundle}/bundle.sha256"
out="$(seal_check_digest "${bundle}")" && rc=0 || rc=$?
assert_contains "unsafe path" "${out}" "digest: path outside the bundle is refused"
rm "${bundle}/bundle.sha256"
out="$(seal_check_digest "${bundle}")" && rc=0 || rc=$?
assert_eq "2" "${rc}" "digest: older bundle without bundle.sha256 is skipped"
_seal_bundle "${bundle}"

# installed files, with a mutable path
spec_load "${bundle}" 2>/dev/null
out="$(seal_check_files "${bundle}")" && rc=0 || rc=$?
assert_eq "0:3 paths intact, 1 mutable skipped" "${rc}:${out}" "files: intact tree, conf/ is mutable"
echo "conf=2" > "${BH_ROOT}/demo/conf/app.conf"
out="$(seal_check_files "${bundle}")" && rc=0 || rc=$?
assert_eq "0" "${rc}" "files: a change inside a mutable path is not a violation"
echo "x" >> "${BH_ROOT}/demo/bin/tool"
out="$(seal_check_files "${bundle}")" && rc=0 || rc=$?
assert_contains "modified demo/bin/tool" "${out}" "files: modified file is reported"
_seal_bundle "${bundle}"; spec_load "${bundle}" 2>/dev/null
rm "${BH_ROOT}/demo/bin/tool"
out="$(seal_check_files "${bundle}")" && rc=0 || rc=$?
assert_contains "missing demo/bin/tool" "${out}" "files: missing file is reported"
_seal_bundle "${bundle}"; spec_load "${bundle}" 2>/dev/null
ln -sf elsewhere "${BH_ROOT}/demo/bin/alias"
out="$(seal_check_files "${bundle}")" && rc=0 || rc=$?
assert_contains "modified link demo/bin/alias" "${out}" "files: retargeted symlink is reported"
rm -f "${bundle}/files.sha256"
out="$(seal_check_files "${bundle}")" && rc=0 || rc=$?
assert_eq "2" "${rc}" "files: no files.sha256 is skipped"

# signature (needs gpg)
if command -v gpg >/dev/null 2>&1; then
    _seal_bundle "${bundle}"
    export GNUPGHOME="${t}/gnupg"; mkdir -m 700 "${GNUPGHOME}"
    gpg --batch --quiet --passphrase '' --quick-generate-key 'Seal Test <seal@example.com>' ed25519 sign never 2>/dev/null
    fpr="$(gpg --batch --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"
    other="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

    out="$(seal_check_signature "${bundle}")" && rc=0 || rc=$?
    assert_eq "2:not signed" "${rc}:${out}" "signature: unsigned bundle"

    gpg --batch --quiet --armor --detach-sign -o "${bundle}/bundle.sha256.asc" "${bundle}/bundle.sha256"
    out="$(BH_SHAKER_TRUSTED_FINGERPRINTS="" seal_check_signature "${bundle}")" && rc=0 || rc=$?
    assert_eq "3" "${rc}" "signature: signed but nothing pinned"
    out="$(BH_SHAKER_TRUSTED_FINGERPRINTS="${fpr}" seal_check_signature "${bundle}")" && rc=0 || rc=$?
    assert_eq "0:${fpr}" "${rc}:${out}" "signature: pinned signer"
    out="$(BH_SHAKER_TRUSTED_FINGERPRINTS="${other},${fpr}" seal_check_signature "${bundle}")" && rc=0 || rc=$?
    assert_eq "0" "${rc}" "signature: pinned list may hold several signers (comma separated)"

    # a second keyring that does not hold the signer's key: keys come from BH_SHAKER_TRUSTED_KEYS
    gpg --batch --armor --export "${fpr}" > "${t}/trusted.asc"
    (
        export GNUPGHOME="${t}/empty"; mkdir -m 700 "${GNUPGHOME}"
        out="$(BH_SHAKER_TRUSTED_FINGERPRINTS="${fpr}" seal_check_signature "${bundle}")" && rc=0 || rc=$?
        assert_eq "1" "${rc}" "signature: signer's key unknown to the local keyring"
        out="$(BH_SHAKER_TRUSTED_FINGERPRINTS="${fpr}" BH_SHAKER_TRUSTED_KEYS="${t}/trusted.asc" seal_check_signature "${bundle}")" && rc=0 || rc=$?
        assert_eq "0" "${rc}" "signature: keys file replaces the keyring"
        out="$(BH_SHAKER_TRUSTED_FINGERPRINTS="${other}" BH_SHAKER_TRUSTED_KEYS="${t}/trusted.asc" seal_check_signature "${bundle}")" && rc=0 || rc=$?
        assert_contains "not a pinned signer" "${out}" "signature: valid signature of a key that is not pinned"
    )

    echo "# x" >> "${bundle}/bundle.sha256"
    out="$(BH_SHAKER_TRUSTED_FINGERPRINTS="${fpr}" seal_check_signature "${bundle}")" && rc=0 || rc=$?
    assert_eq "1" "${rc}" "signature: digest changed after signing"

    # install gate
    _seal_bundle "${bundle}"; gpg --batch --quiet --yes --armor --detach-sign -o "${bundle}/bundle.sha256.asc" "${bundle}/bundle.sha256"
    LC_PKG=demo
    assert_ok "gate: signed bundle passes when required" env BH_SHAKER_REQUIRE_SIGNATURE=true BH_SHAKER_TRUSTED_FINGERPRINTS="${fpr}" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; seal_require_trust '${bundle}'"
    assert_fail "gate: unpinned signer is refused when required" env BH_SHAKER_REQUIRE_SIGNATURE=true BH_SHAKER_TRUSTED_FINGERPRINTS="${other}" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; seal_require_trust '${bundle}'"
    rm "${bundle}/bundle.sha256.asc"
    assert_fail "gate: unsigned bundle is refused when required" env BH_SHAKER_REQUIRE_SIGNATURE=true BH_SHAKER_TRUSTED_FINGERPRINTS="${fpr}" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; seal_require_trust '${bundle}'"
    assert_ok "gate: unsigned bundle passes when not required" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; seal_require_trust '${bundle}'"
    unset GNUPGHOME
else
    echo "  (signature checks skipped: gpg not installed)"
fi
export BH_ROOT="${TESTS_DIR}/.tmp/root"
