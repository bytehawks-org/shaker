# Distillery -> Shaker contract, end to end: Distillery builds a package from a local tarball
# and writes the bundle, Shaker installs/inits/verifies it. Skipped without a Distillery checkout.
DISTILLERY_HOME="${DISTILLERY_HOME:-${TESTS_DIR}/../../distillery}"
if [[ -f "${DISTILLERY_HOME}/scripts/autobuilder.py" ]] && command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; then
    t="$(new_tmp)"
    mkdir -p "${t}/src/demo-1.0" "${t}/assets/demo"
    printf '#!/bin/sh\necho "demo says $1"\n' > "${t}/src/demo-1.0/demo.sh"
    chmod +x "${t}/src/demo-1.0/demo.sh"
    tar -czf "${t}/demo.tgz" -C "${t}/src" demo-1.0
    sum="$(sha256_of_file "${t}/demo.tgz")"
    printf 'port={{ BH_DEMO_PORT }}\nprefix={{ BH_PKG_PREFIX }}\n' > "${t}/assets/demo/demo.conf.tmpl"
    cat > "${t}/packages.yaml" <<YAML
package:
  demo:
    variant:
      - {name: stable, major_version: 1, patch_version: 0, full_version: "1.0", sha256: ${sum}}
    git:
      repo: file://local
      release_download_url_template: "file://${t}/demo.tgz"
    commands:
      install: |
        mkdir -p {{ prefix }}/bin
        cp demo.sh {{ prefix }}/bin/demo
    runtime:
      dirs:
        - {path: "{{ prefix }}/conf", mode: "0750"}
      templates:
        - {src: demo.conf.tmpl, dest: "{{ prefix }}/conf/demo.conf", mode: "0640"}
      run: {command: ["{{ prefix }}/bin/demo", "\${BH_DEMO_GREETING}"]}
      env:
        - {name: BH_DEMO_PORT, type: port, default: 7000, aliases: [DEMO_PORT], cli: --port}
        - {name: BH_DEMO_GREETING, type: string, default: hi, cli: --greeting}
    tags: [application]
YAML
    root="${t}/root"
    python3 "${DISTILLERY_HOME}/scripts/autobuilder.py" build --package demo --root "${root}" \
        --packages "${t}/packages.yaml" --assets "${t}/assets" >/dev/null 2>&1
    assert_ok "integration: distillery wrote the bundle" test -f "${root}/demo/.bytehawks/runtime.spec"

    export BH_ROOT="${root}" BH_SHAKER_ALLOW_NONROOT=true BH_SHAKER_LOG_LEVEL=warn
    "${SHAKER_BIN}" install demo >/dev/null 2>&1
    DEMO_PORT=7100 "${SHAKER_BIN}" init demo >/dev/null 2>&1
    assert_eq $'port=7100\nprefix='"${root}/demo" "$(cat "${root}/demo/conf/demo.conf")" "integration: alias env reaches the template"
    assert_eq "demo says yo" "$("${SHAKER_BIN}" run demo --greeting=yo 2>/dev/null)" "integration: run executes the built artifact"
    DEMO_PORT=7100 "${SHAKER_BIN}" verify demo --no-health >/dev/null 2>&1 && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL: integration verify"; }
    unset BH_ROOT BH_SHAKER_ALLOW_NONROOT BH_SHAKER_LOG_LEVEL
else
    echo "  (skipped: no Distillery checkout or PyYAML)"
fi
