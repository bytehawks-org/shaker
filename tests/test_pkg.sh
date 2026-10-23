export BH_SHAKER_DRY_RUN=true
for case in debian:apt-get alpine:apk rhel:dnf suse:zypper arch:pacman; do
    BH_SHAKER_OS_FAMILY="${case%%:*}" BH_SHAKER_OS_PKG_MANAGER="${case##*:}"
    BH_SHAKER_OS_FAMILY="${case%%:*}"; BH_SHAKER_OS_PKG_MANAGER="${case##*:}"
    out="$(pkg_install openssl-dev curl 2>&1)"
    assert_contains "${case##*:}" "${out}" "dry-run uses ${case##*:}"
done
BH_SHAKER_OS_FAMILY=rhel; BH_SHAKER_OS_PKG_MANAGER=dnf
assert_contains "openssl-devel" "$(pkg_install openssl-dev 2>&1)" "pkgmap rhel"
assert_contains "gcc make" "$(pkg_install build-essential 2>&1)" "multi package mapping"
BH_SHAKER_OS_FAMILY=alpine; BH_SHAKER_OS_PKG_MANAGER=apk
assert_contains "build-base" "$(pkg_install build-essential 2>&1)" "pkgmap alpine"
BH_SHAKER_OS_PKG_MANAGER=nope
assert_fail "unsupported manager" pkg_update
unset BH_SHAKER_DRY_RUN
