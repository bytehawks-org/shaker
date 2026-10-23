for id in ubuntu:debian alpine:alpine fedora:rhel rocky:rhel opensuse:suse arch:arch custom:debian; do
    BH_SHAKER_OS_RELEASE_FILE="${TESTS_DIR}/fixtures/os-release.${id%%:*}" detect_os
    assert_eq "${id##*:}" "${BH_SHAKER_OS_FAMILY}" "family of ${id%%:*}"
done
BH_SHAKER_OS_RELEASE_FILE="${TESTS_DIR}/fixtures/os-release.ubuntu" detect_os
assert_eq "ubuntu" "${BH_SHAKER_OS_ID}" "os id"
assert_eq "22.04" "${BH_SHAKER_OS_VERSION_ID}" "os version id"
# deployment detection through markers, with systemd-detect-virt hidden
systemd-detect-virt() { echo none; return 1; }
t="$(new_tmp)"; mkdir -p "${t}/proc" "${t}/run"; touch "${t}/.dockerenv"
( unset KUBERNETES_SERVICE_HOST container; BH_SHAKER_PROC_ROOT="${t}" detect_deployment_environment
  echo "${BH_SHAKER_DEPLOYMENT_ENVIRONMENT}:${BH_SHAKER_DEPLOYMENT_ENVIRONMENT_TYPE}" ) > "${t}/out"
assert_eq "container:docker" "$(cat "${t}/out")" "docker marker"
rm "${t}/.dockerenv"; mkdir -p "${t}/sys/class/dmi/id"; echo "VMware, Inc." > "${t}/sys/class/dmi/id/sys_vendor"
( unset KUBERNETES_SERVICE_HOST container; BH_SHAKER_PROC_ROOT="${t}" detect_deployment_environment
  echo "${BH_SHAKER_DEPLOYMENT_ENVIRONMENT}:${BH_SHAKER_DEPLOYMENT_ENVIRONMENT_TYPE}" ) > "${t}/out"
assert_eq "vm:vmware" "$(cat "${t}/out")" "dmi vmware"
rm "${t}/sys/class/dmi/id/sys_vendor"
( unset KUBERNETES_SERVICE_HOST container; BH_SHAKER_PROC_ROOT="${t}" detect_deployment_environment
  echo "${BH_SHAKER_DEPLOYMENT_ENVIRONMENT}" ) > "${t}/out"
assert_eq "physical" "$(cat "${t}/out")" "bare metal fallback"
( unset KUBERNETES_SERVICE_HOST; container=podman BH_SHAKER_PROC_ROOT="${t}" detect_deployment_environment
  echo "${BH_SHAKER_DEPLOYMENT_ENVIRONMENT_TYPE}" ) > "${t}/out"
assert_eq "podman" "$(cat "${t}/out")" "container env var"
( KUBERNETES_SERVICE_HOST=10.0.0.1 BH_SHAKER_PROC_ROOT="${t}" detect_deployment_environment
  echo "${BH_SHAKER_DEPLOYMENT_ENVIRONMENT_ORCHESTRATOR}" ) > "${t}/out"
assert_eq "kubernetes" "$(cat "${t}/out")" "kubernetes orchestrator"
unset -f systemd-detect-virt
