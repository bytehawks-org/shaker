assert_eq true  "$(normalize_boolean Yes)" "bool yes"
assert_eq false "$(normalize_boolean none)" "bool none"
assert_eq false "$(normalize_boolean kvm || true)" "bool unknown -> false"
assert_fail "bool unknown rc" normalize_boolean kvm
assert_eq FOO "$(normalize_case upper foo)" "upper"
assert_eq foo "$(normalize_case LOWER FOO)" "lower"
assert_ok   "port 8080" is_port 8080
assert_fail "port 0" is_port 0
assert_fail "port 70000" is_port 70000
assert_ok   "enum" validate_type enum:a,b,c b
assert_fail "enum bad" validate_type enum:a,b,c d
assert_ok   "secret name" is_secret_name BH_PG_PASSWORD
assert_fail "plain name" is_secret_name BH_PG_PORT
