t="$(new_tmp)"
# mode helpers used by verify
assert_eq "755" "$(_mode_to_octal drwxr-xr-x)" "mode octal 755"
assert_eq "750" "$(_mode_to_octal drwxr-x---)" "mode octal 750"
assert_eq "775" "$(_mode_to_octal drwxrwsr-x)" "mode octal with setgid"
assert_ok   "g+rwX satisfied by 775" _mode_satisfies drwxrwxr-x 775 g+rwX
assert_fail "g+rwX not satisfied by 755" _mode_satisfies drwxr-xr-x 755 g+rwX
assert_ok   "g+rX satisfied by 750" _mode_satisfies drwxr-x--- 750 g+rX
assert_ok   "octal 0640" _mode_satisfies -rw-r----- 640 0640

mkdir -p "${t}/d/sub"; touch "${t}/d/f"
configure_permissions_ownership "${t}/d" -d 750 -f 640
assert_eq "750" "$(_mode_to_octal "$(ls -ld "${t}/d/sub" | cut -d' ' -f1)")" "recursive dir mode"
assert_eq "640" "$(_mode_to_octal "$(ls -l "${t}/d/f" | cut -d' ' -f1)")" "recursive file mode"
assert_ok "is_dir_empty on empty" is_dir_empty "${t}/none"
assert_eq "32" "$(generate_random_string 32 | tr -d '\n' | wc -c | tr -d ' ')" "random string length"

# arbitrary uid: writable passwd gets an entry (needs root + setpriv to simulate another uid)
if am_i_root && command -v setpriv >/dev/null 2>&1 \
   && setpriv --reuid=54321 --regid=0 --clear-groups test -r "${TESTS_DIR}/../lib/shaker.libsh" 2>/dev/null; then
    : > "${t}/passwd"; : > "${t}/group"; chmod 666 "${t}/passwd" "${t}/group"
    setpriv --reuid=54321 --regid=0 --clear-groups env SHAKER_PASSWD_FILE="${t}/passwd" SHAKER_GROUP_FILE="${t}/group" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; ensure_passwd_entry svc /tmp" >/dev/null 2>&1
    assert_contains ":54321:0:" "$(cat "${t}/passwd")" "arbitrary uid added to passwd"
    setpriv --reuid=54321 --regid=0 --clear-groups env SHAKER_PASSWD_FILE="${t}/passwd" SHAKER_GROUP_FILE="${t}/group" \
        bash -c ". '${TESTS_DIR}/../lib/shaker.libsh'; ensure_passwd_entry svc /tmp" >/dev/null 2>&1
    assert_eq "1" "$(wc -l < "${t}/passwd" | tr -d ' ')" "passwd entry not duplicated"
fi

# bootstrap: layout + symlink, idempotent, never overwrites a real directory
t="$(new_tmp)"
( BH_ROOT="${t}/bytehawks" BH_LINK="${t}/bh" BH_CORE= BH_DEPS= BH_ETC= BH_VAR= BH_STATE= ;
  unset BH_CORE BH_DEPS BH_ETC BH_VAR BH_STATE; shaker_init_paths; shaker_bootstrap; shaker_bootstrap ) >/dev/null 2>&1
assert_ok "bootstrap: core dir" test -d "${t}/bytehawks/core"
assert_ok "bootstrap: state dir" test -d "${t}/bytehawks/var/lib/shaker"
assert_eq "${t}/bytehawks" "$(readlink "${t}/bh")" "bootstrap: /opt/bh style symlink"
mkdir "${t}/realdir"
( BH_ROOT="${t}/bytehawks" BH_LINK="${t}/realdir"; unset BH_CORE BH_DEPS BH_ETC BH_VAR BH_STATE; shaker_init_paths; shaker_bootstrap ) >/dev/null 2>&1
assert_ok "bootstrap: real directory left untouched" test -d "${t}/realdir" -a ! -L "${t}/realdir"
shaker_init_paths
