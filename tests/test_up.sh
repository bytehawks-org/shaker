# up.libsh: dependency order, recipe check, cycles, set-up of units with and without a runtime. Hand-written bundles.

_up_bundle_make() {  # <pkg> <recipe> <deps "a=r b=r"> [runtime.spec line...]
    local pkg="$1" recipe="$2" deps="$3"; shift 3
    local dir="${BH_ROOT}/${pkg}/.bytehawks"
    mkdir -p "${dir}"
    printf '{}\n' > "${dir}/manifest.json"
    { printf 'BH_PKG_NAME=%s\nBH_PKG_VERSION=1.0\nBH_PKG_PREFIX=%s/%s\nBH_PKG_RECIPE=%s\n' "${pkg}" "${BH_ROOT}" "${pkg}" "${recipe}"
      [[ -n "${deps}" ]] && printf 'BH_PKG_DEPENDS=%s\n' "${deps}"; } > "${dir}/manifest.env"
    : > "${dir}/rosetta.map"
    printf '%s\n' "$@" > "${dir}/runtime.spec"
    [[ $# -gt 0 ]] || : > "${dir}/runtime.spec"
}

t="$(new_tmp)"; export BH_ROOT="${t}/root" BH_DEPS="${t}/root/deps" BH_ETC="${t}/root/etc" BH_VAR="${t}/root/var" BH_STATE="${t}/state"
export BH_SHAKER_ALLOW_NONROOT=true BH_SHAKER_QUIET=true
# hand-written bundles record no platform: do not inherit one from the environment (glibc build vs musl host)
unset BH_PKG_ARCH BH_PKG_LIBC
r_lib="$(printf 'a%.0s' {1..64})"; r_mid="$(printf 'b%.0s' {1..64})"; r_app="$(printf 'c%.0s' {1..64})"

_up_bundle_make lib "${r_lib}" ""
_up_bundle_make mid "${r_mid}" "lib=${r_lib}" "dir|${BH_ROOT}/mid/data|0750|"
_up_bundle_make app "${r_app}" "mid=${r_mid} lib=${r_lib}" "dir|${BH_ROOT}/app/data|0750|" "run|/bin/true"

up_plan app
assert_eq "lib mid app" "${UP_ORDER[*]}" "up: dependencies first, each once, the package last"
up_plan lib
assert_eq "lib" "${UP_ORDER[*]}" "up: a package without dependencies is its own plan"

# a bundle without BH_PKG_DEPENDS (hand-written, older Distillery) has no dependencies
_up_bundle_make solo "${r_app}" ""
up_plan solo
assert_eq "solo" "${UP_ORDER[*]}" "up: no BH_PKG_DEPENDS = no dependencies"

# missing dependency
_up_bundle_make orphan "${r_app}" "ghost=${r_lib}"
assert_fail "up: dependency that is not installed" up_plan orphan

# installed dependency is not the build the package was made against
_up_bundle_make stale "${r_app}" "lib=$(printf 'd%.0s' {1..64})"
out="$(BH_SHAKER_QUIET=false up_plan stale 2>&1)" && rc=0 || rc=$?
assert_eq "1" "${rc}" "up: dependency recipe mismatch is refused"
assert_contains "was built against lib dddddddddddd, but aaaaaaaaaaaa is installed" "${out}" "up: the mismatch is explained"

# cycle
_up_bundle_make c1 "${r_app}" "c2=${r_app}"
_up_bundle_make c2 "${r_app}" "c1=${r_app}"
out="$(BH_SHAKER_QUIET=false up_plan c1 2>&1)" && rc=0 || rc=$?
assert_eq "1" "${rc}" "up: dependency cycle is refused"
assert_contains "cycle" "${out}" "up: cycle is named"

# set-up: the library has no runtime and is skipped, the others get their directories
out="$(BH_SHAKER_QUIET=false up_all app 2>&1)" && rc=0 || rc=$?
assert_eq "0" "${rc}" "up: whole chain (${out//$'\n'/ | })"
assert_ok "up: dependency with a runtime was set up" test -d "${BH_ROOT}/mid/data"
assert_ok "up: the package itself was set up" test -d "${BH_ROOT}/app/data"
assert_eq "750" "$(stat -c %a "${BH_ROOT}/mid/data")" "up: directory mode applied"
assert_contains "installed_at=" "$(cat "$(state_file mid)")" "up: dependency state recorded"
assert_eq "" "$(cat "$(state_file lib)" 2>/dev/null)" "up: a library without runtime leaves no state"
assert_ok "up: running it again is harmless" up_all app

# a failing unit stops the chain
rm -rf "${BH_ROOT}/app/data" "${BH_ROOT}/mid/data" "${BH_STATE}"
_up_bundle_make mid "${r_mid}" "lib=${r_lib}" "dir|/proc/forbidden/nope|0750|"
assert_fail "up: stops at the first failing unit" up_all app
assert_fail "up: ... without touching what comes after" test -d "${BH_ROOT}/app/data"

# CLI
_up_bundle_make mid "${r_mid}" "lib=${r_lib}" "dir|${BH_ROOT}/mid/data|0750|"
assert_eq $'lib\nmid\napp' "$("${SHAKER_BIN}" up app --plan 2>/dev/null)" "up: shaker up --plan prints the order"
assert_ok "up: shaker up" "${SHAKER_BIN}" up app
assert_fail "up: shaker up of an unknown package" "${SHAKER_BIN}" up nothing
unset BH_SHAKER_QUIET BH_SHAKER_ALLOW_NONROOT BH_DEPS BH_ETC BH_VAR BH_STATE
export BH_ROOT="${TESTS_DIR}/.tmp/root"
