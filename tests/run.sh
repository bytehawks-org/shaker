#!/usr/bin/env bash
# Minimal dependency-free test runner: tests/run.sh [test_*.sh ...]
set -o nounset -o pipefail

TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BH_SHAKER_COLOR=false BH_ROOT="${TESTS_DIR}/.tmp/root" BH_LINK="${TESTS_DIR}/.tmp/link"
PASS=0; FAIL=0

# shellcheck source=../lib/shaker.libsh
. "${TESTS_DIR}/../lib/shaker.libsh"
SHAKER_BIN="${TESTS_DIR}/../bin/shaker"

assert_eq() {  # expected actual message
    if [[ "$1" == "$2" ]]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$3" "$1" "$2"; fi
}
assert_ok()   { if "${@:2}" >/dev/null 2>&1; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL: $1 (expected success)"; fi; }
assert_fail() { if "${@:2}" >/dev/null 2>&1; then FAIL=$((FAIL + 1)); echo "FAIL: $1 (expected failure)"; else PASS=$((PASS + 1)); fi; }
assert_contains() {  # needle haystack message
    if [[ "$2" == *"$1"* ]]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); printf 'FAIL: %s\n  missing: %q\n  in:      %q\n' "$3" "$1" "$2"; fi
}
new_tmp() { rm -rf "${TESTS_DIR}/.tmp"; mkdir -p "${TESTS_DIR}/.tmp"; echo "${TESTS_DIR}/.tmp"; }

files=("$@"); (( ${#files[@]} )) || files=("${TESTS_DIR}"/test_*.sh)
for f in "${files[@]}"; do
    echo "== $(basename "${f}")"
    # shellcheck disable=SC1090
    . "${f}"
done
rm -rf "${TESTS_DIR}/.tmp"
echo "passed: ${PASS}  failed: ${FAIL}"
(( FAIL == 0 ))
