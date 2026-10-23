# Lifecycle verbs against a hand-written bundle (no Distillery needed).
export BH_SHAKER_ALLOW_NONROOT=true BH_SHAKER_LOG_LEVEL=warn

t="$(new_tmp)"
export BH_ROOT="${t}/root" BH_DEPS="${t}/root/deps" BH_ETC="${t}/root/etc" BH_VAR="${t}/root/var" BH_STATE="${t}/root/var/lib/shaker"
P="${BH_ROOT}/demo"; B="${P}/.bytehawks"
mkdir -p "${B}/assets" "${P}/bin" "${P}/seed" "${t}/vol"
printf 'seed-data\n' > "${P}/seed/file.txt"

cat > "${B}/manifest.json" <<JSON
{"package": "demo", "version": "1.0.0"}
JSON
printf 'BH_PKG_NAME=demo\nBH_PKG_VERSION=1.0.0\nBH_PKG_VARIANT=stable\nBH_PKG_PREFIX=%s\nBH_PKG_RECIPE=abc123\n' "${P}" > "${B}/manifest.env"
cat > "${B}/rosetta.map" <<'MAP'
BH_DEMO_PORT|port|9000||DEMO_PORT|server.port|--port||listen port
BH_DEMO_MSG|string|hello||||--msg|DEMO_NATIVE_MSG|message
MAP
printf 'port={{ BH_DEMO_PORT }}\nmsg={{ BH_DEMO_MSG }}\nprefix={{ BH_PKG_PREFIX }}\n' > "${B}/assets/demo.conf.tmpl"
mkdir -p "${P}/hooks/first" "${P}/hooks/pre"
printf '#!/bin/sh\necho x >> "%s/first.count"\n' "${t}" > "${P}/hooks/first/10-count.sh"
printf '#!/bin/sh\necho x >> "%s/pre.count"\n' "${t}" > "${P}/hooks/pre/10-count.sh"
chmod +x "${P}"/hooks/*/*.sh
cat > "${B}/runtime.spec" <<SPEC
dir|${P}/conf|0750|
dir|${P}/data|g+rwX|
dir|${P}/hooks/post|0755|
persist|${P}/seed|${t}/vol
template|demo.conf.tmpl|${P}/conf/demo.conf|0640
hook|pre_init|${P}/hooks/pre
hook|first_init|${P}/hooks/first
run|printf|%s\n|\${BH_DEMO_MSG}|\${BH_DEMO_PORT}
stopsignal|TERM
pidfile|${P}/run/demo.pid
health|tcp|127.0.0.1|\${BH_DEMO_PORT}
requires|bash
SPEC

SH="${SHAKER_BIN}"

# install
"${SH}" install demo >/dev/null 2>&1
assert_eq "750" "$(ls -ld "${P}/conf" | cut -c2-10 | tr 'rwx-' '4210' | awk '{split($0,a,""); printf "%d%d%d", a[1]+a[2]+a[3], a[4]+a[5]+a[6], a[7]+a[8]+a[9]}')" "install: numeric mode"
assert_ok "install: state recorded" test -n "$("${SH}" status demo | grep installed_version=1.0.0)"

# init: render, hooks, persistence, state
"${SH}" init demo --port=9100 >/dev/null 2>&1
assert_eq $'port=9100\nmsg=hello\nprefix='"${P}" "$(cat "${P}/conf/demo.conf")" "init: template rendered from CLI + defaults + BH_PKG_*"
assert_eq "1" "$(wc -l < "${t}/pre.count" | tr -d ' ')" "init: pre_init hook ran"
assert_eq "1" "$(wc -l < "${t}/first.count" | tr -d ' ')" "init: first_init hook ran"
assert_eq "seed-data" "$(cat "${t}/vol/file.txt")" "persistence: volume seeded"
assert_ok "persistence: path is a symlink to the volume" test "$(readlink "${P}/seed")" = "${t}/vol"
"${SH}" init demo --port=9100 >/dev/null 2>&1
assert_eq "2" "$(wc -l < "${t}/pre.count" | tr -d ' ')" "re-init: pre_init runs every time"
assert_eq "1" "$(wc -l < "${t}/first.count" | tr -d ' ')" "re-init: first_init runs once"
"${SH}" init demo --port=9100 --reinit >/dev/null 2>&1
assert_eq "2" "$(wc -l < "${t}/first.count" | tr -d ' ')" "--reinit: first_init runs again"

# verify: in sync, drift, parameter change, health
out="$("${SH}" verify demo --port=9100 --no-health 2>&1)"; rc=$?
assert_eq "0" "${rc}" "verify rc"
assert_contains "in sync" "${out}" "verify: template in sync"
out="$("${SH}" verify demo --port=9999 --no-health 2>&1)"
assert_contains "parameters changed since last init" "${out}" "verify: parameter change warning"
"${SH}" verify demo --port=9999 --no-health --strict >/dev/null 2>&1 && FAIL=$((FAIL+1)) || PASS=$((PASS+1))
echo '# hand edit' >> "${P}/conf/demo.conf"
out="$("${SH}" verify demo --port=9100 --no-health 2>&1)"; rc=$?
assert_eq "1" "${rc}" "verify: drift is a failure"
assert_contains "DRIFT" "${out}" "verify: drift reported"
"${SH}" init demo --port=9100 >/dev/null 2>&1
"${SH}" verify demo --port=9100 --no-health >/dev/null 2>&1 && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: verify after re-init"; }
out="$("${SH}" verify demo --port=9100 2>&1 || true)"
assert_contains "health tcp" "${out}" "verify: health checked"
assert_contains "closed" "${out}" "verify: closed port detected"
assert_contains "init ok" "$("${SH}" status demo)" "status: event log"

# run (foreground exec, native twin, expansion) and parameter errors
out="$("${SH}" run demo --msg=ciao --port=9100 2>/dev/null)"
assert_eq "ciao"$'\n'"9100" "${out}" "run: exec with expanded argv"
"${SH}" run demo --port=notaport >/dev/null 2>&1 && FAIL=$((FAIL+1)) || PASS=$((PASS+1))
"${SH}" run demo --port=9100 --no-init -- extra 2>/dev/null | grep -q extra && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: run extra args"; }

# daemon + stop
cat > "${B}/runtime.spec.d" <<SPEC
SPEC
sed -i.bak "s#^run|.*#run|sleep|300#" "${B}/runtime.spec" && rm -f "${B}/runtime.spec.bak" "${B}/runtime.spec.d"
mkdir -p "${P}/run"
"${SH}" run demo --port=9100 --daemon >/dev/null 2>&1
assert_ok "daemon: pid file written" test -s "${P}/run/demo.pid"
assert_ok "daemon: process alive" is_service_running "${P}/run/demo.pid"
"${SH}" stop demo >/dev/null 2>&1
assert_fail "daemon: process stopped" is_service_running "${P}/run/demo.pid"

# systemd unit
out="$("${SH}" unit demo 2>/dev/null)"
assert_contains "ExecStart=${SHAKER_HOME}/bin/shaker run demo --no-init" "${out}" "unit: ExecStart"
assert_contains "ExecStartPre=" "${out}" "unit: init before start"
assert_contains "NoNewPrivileges=true" "${out}" "unit: hardening"

# missing bundle
"${SH}" verify nosuchpkg >/dev/null 2>&1 && FAIL=$((FAIL+1)) || PASS=$((PASS+1))
unset BH_SHAKER_ALLOW_NONROOT BH_SHAKER_LOG_LEVEL BH_DEPS BH_ETC BH_VAR BH_STATE
