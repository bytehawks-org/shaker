#!/bin/bash

set -o errexit  # Esci subito se un comando fallisce (set -e)
set -o nounset  # Esci se usi una variabile non dichiarata (set -u)
set -o pipefail # Esci se un comando in una pipe fallisce (non solo l'ultimo)

. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/shaker.libsh"
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/os.libsh"
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/log.libsh"

shaker_base_path
shaker_assets_path
shaker_lib_path

print_welcome_banner

detect_deployment_environment
detect_os
detect_package_manager

debug_bh_shaker_env_vars

echo ""
echo " --> QUA LE VARIABILI DEFINITE"
echo ""
cleanup_bh_shaker_env_vars
echo ""
echo " --> QUA PULIZIA!"
echo ""
debug_bh_shaker_env_vars


