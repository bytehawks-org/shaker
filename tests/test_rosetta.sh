t="$(new_tmp)"
cat > "${t}/rosetta.map" <<'MAP'
# env|type|default|flags|aliases|file_key|cli|native_env|description
BH_APP_PORT|port|6379||APP_PORT,LEGACY_PORT|server.port|--port|APP_NATIVE_PORT|listen port
BH_APP_PASSWORD|secret||required|APP_PASSWORD|auth.password|--password||password
BH_APP_MODE|enum:fast,safe|safe|||mode|--mode||mode
BH_APP_TLS|bool|false||||--tls||enable tls
MAP
resolve() { rosetta_reset; rosetta_load_map "${t}/rosetta.map" && { [[ -z "${CFG:-}" ]] || rosetta_load_config "${CFG}"; } && rosetta_parse_cli "$@" && rosetta_resolve; }
run() { ( unset BH_APP_PORT BH_APP_PASSWORD BH_APP_MODE BH_APP_TLS APP_PASSWORD APP_PORT LEGACY_PORT; "$@" ); }

# required missing
assert_fail "required password" run resolve
# default + env
out="$(export BH_APP_PASSWORD=s3cret; resolve; rosetta_print explain)"
assert_contains "6379" "${out}" "default port"
assert_contains "default" "${out}" "default source"
assert_contains "********" "${out}" "secret redacted"
case "${out}" in *s3cret*) FAIL=$((FAIL+1)); echo "FAIL: secret leaked in explain";; *) PASS=$((PASS+1));; esac
# alias (upstream dialect) -> canonical + native export
out="$(export APP_PASSWORD=x APP_PORT=7000; resolve; rosetta_print export)"
assert_contains "export BH_APP_PORT=7000" "${out}" "alias to canonical"
assert_contains "export APP_NATIVE_PORT=7000" "${out}" "native twin"
# canonical beats alias; CLI beats env
out="$(export APP_PASSWORD=x APP_PORT=7000 BH_APP_PORT=7100; resolve; rosetta_print export)"
assert_contains "BH_APP_PORT=7100" "${out}" "canonical > alias"
out="$(export APP_PASSWORD=x BH_APP_PORT=7100; resolve --port=7200; rosetta_print export)"
assert_contains "BH_APP_PORT=7200" "${out}" "cli > env"
out="$(export APP_PASSWORD=x; resolve --port 7300 --tls; rosetta_print export)"
assert_contains "BH_APP_PORT=7300" "${out}" "cli separate value"
assert_contains "BH_APP_TLS=true" "${out}" "bare bool flag"
# _FILE secrets (k8s) and conflict
printf 's3cr3t-from-file\n' > "${t}/pw"
out="$(export BH_APP_PASSWORD_FILE="${t}/pw"; resolve; rosetta_print dotenv)"
assert_contains 'BH_APP_PASSWORD="s3cr3t-from-file"' "${out}" "_FILE secret, newline stripped"
( export BH_APP_PASSWORD=a BH_APP_PASSWORD_FILE="${t}/pw"; resolve ) >/dev/null 2>&1 && FAIL=$((FAIL+1)) || PASS=$((PASS+1))
# validation
( export APP_PASSWORD=x BH_APP_PORT=99999; resolve ) >/dev/null 2>&1 && FAIL=$((FAIL+1)) || PASS=$((PASS+1))
( export APP_PASSWORD=x; resolve --mode=turbo ) >/dev/null 2>&1 && FAIL=$((FAIL+1)) || PASS=$((PASS+1))
( export APP_PASSWORD=x; resolve --nope=1 ) >/dev/null 2>&1 && FAIL=$((FAIL+1)) || PASS=$((PASS+1))
# legacy config files: env, ini, json, yaml, drop-in
printf '# c\nexport BH_APP_PASSWORD="from-env-file"\nserver.port=8001\n' > "${t}/app.conf"
mkdir "${t}/app.conf.d"; printf 'server.port=8002\n' > "${t}/app.conf.d/10-override.conf"
out="$(CFG="${t}/app.conf"; resolve; rosetta_print explain)"
assert_contains "8002" "${out}" "drop-in overrides base"
assert_contains "config:server.port" "${out}" "provenance config"
printf '[server]\nport = 9001\n[auth]\npassword = "ini-pw"\n' > "${t}/app.ini"
out="$(CFG="${t}/app.ini"; resolve; rosetta_print export)"
assert_contains "BH_APP_PORT=9001" "${out}" "ini section.key"
assert_contains "BH_APP_PASSWORD=ini-pw" "${out}" "ini quotes stripped"
have_json() { command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; }
have_yaml() { { command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; } || command -v yq >/dev/null 2>&1; }
if have_json; then
printf '{"server":{"port":9002},"auth":{"password":"json-pw"},"mode":"fast"}' > "${t}/app.json"
out="$(CFG="${t}/app.json"; resolve; rosetta_print export)"
assert_contains "BH_APP_PORT=9002" "${out}" "json nested"
assert_contains "BH_APP_MODE=fast" "${out}" "json enum"
else echo "  (json tests skipped: neither jq nor python3)"; fi
if have_yaml; then
printf 'server:\n  port: 9003\nauth:\n  password: yaml-pw\n' > "${t}/app.yaml"
out="$(CFG="${t}/app.yaml"; resolve; rosetta_print export)"
assert_contains "BH_APP_PORT=9003" "${out}" "yaml nested"
else echo "  (yaml tests skipped: neither python3+PyYAML nor yq)"; fi
# env beats config file
out="$(export BH_APP_PORT=1234; CFG="${t}/app.ini"; resolve; rosetta_print export)"
assert_contains "BH_APP_PORT=1234" "${out}" "env > config"
# end to end via bin/shaker exec: clean env, native twin available, framework vars removed
out="$(APP_PASSWORD=pw "${SHAKER_BIN}" exec app --map="${t}/rosetta.map" --port=7777 -- env)"
assert_contains "APP_NATIVE_PORT=7777" "${out}" "exec exports native"
case "${out}" in *BH_SHAKER_OS_ID*) FAIL=$((FAIL+1)); echo "FAIL: BH_SHAKER_* leaked to app";; *) PASS=$((PASS+1));; esac
assert_fail "exec validation" env -i PATH="${PATH}" "${SHAKER_BIN}" exec app --map="${t}/rosetta.map" -- true
