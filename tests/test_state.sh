t="$(new_tmp)"
BH_STATE="${t}/state"
state_set demo a=1 b=two
assert_eq "1" "$(state_get demo a)" "state get"
state_set demo a=3 c=x=y
assert_eq "3" "$(state_get demo a)" "state overwrite"
assert_eq "two" "$(state_get demo b)" "state keeps other keys"
assert_eq "x=y" "$(state_get demo c)" "state value with ="
state_set demo tpl.0.sha256=aa tpl.1.sha256=bb
state_unset demo tpl.
assert_fail "state_unset prefix" state_get demo tpl.0.sha256
assert_eq "3" "$(state_get demo a)" "state_unset keeps others"
assert_fail "missing key" state_get demo nope
state_event demo init ok 1.0
assert_contains " demo init ok 1.0" "$(cat "${BH_STATE}/events.log")" "event log"
# unwritable state dir falls back to a private temp dir
BH_STATE="/proc/nonexistent/state"; TMPDIR="${t}"
assert_contains "bytehawks-state-" "$(state_dir)" "state dir fallback"
unset TMPDIR

# expand_vars
FOO=bar
assert_eq "x-bar-y" "$(expand_vars 'x-${FOO}-y')" "expand_vars"
assert_eq "d" "$(expand_vars '${NOPE_UNSET:-d}')" "expand_vars default"
assert_fail "expand_vars unset" expand_vars '${NOPE_UNSET}'
assert_eq '$(id)' "$(FOO='$(id)' expand_vars '${FOO}')" "expand_vars does not evaluate"

# sha256
assert_eq "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" "$(sha256_of_string abc)" "sha256 string"

# service pid helpers
sleep 30 & pid=$!
echo "${pid}" > "${t}/p.pid"
assert_ok "service running" is_service_running "${t}/p.pid"
service_stop "${t}/p.pid" TERM 5
wait "${pid}" 2>/dev/null
assert_fail "service stopped" is_service_running "${t}/p.pid"
echo garbage > "${t}/bad.pid"
assert_fail "bad pid file" is_service_running "${t}/bad.pid"
unset BH_STATE FOO
