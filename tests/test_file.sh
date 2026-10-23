t="$(new_tmp)"
printf 'a=1\nb=$x & [y]\n' > "${t}/f"
replace_in_file "${t}/f" 'b=$x & [y]' 'b=2/3'
assert_eq $'a=1\nb=2/3' "$(cat "${t}/f")" "replace literal"
ensure_line_in_file "${t}/f" "a=1"; ensure_line_in_file "${t}/f" "c=3"
assert_eq "3" "$(wc -l < "${t}/f" | tr -d ' ')" "ensure_line idempotent"
printf 'port={{ P }}\nhost={{ H:-localhost }}\nraw={{X}} and {{ P }}\n' > "${t}/tpl"
out="$(P=80 X= render_template "${t}/tpl")"
assert_eq $'port=80\nhost=localhost\nraw= and 80' "${out%$'\n'}" "render with default"
out="$(P=80 X='$(id)' H='h&\1' render_template "${t}/tpl")"
assert_contains 'host=h&\1' "${out}" "values inserted verbatim"
assert_contains 'raw=$(id) and 80' "${out}" "no evaluation"
assert_fail "missing var" env -u P bash -c ". ${TESTS_DIR}/../lib/shaker.libsh; render_template ${t}/tpl"
is_dir_empty "${t}/nonexistent" && PASS=$((PASS+1))
wait_for_port 127.0.0.1 1 1 2>/dev/null && FAIL=$((FAIL+1)) || PASS=$((PASS+1))
