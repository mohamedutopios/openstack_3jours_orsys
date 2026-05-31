#!/usr/bin/env bash
# Phase 2 — Heat
# Pré-requis dans /etc/kolla/globals.yml :
#   enable_heat: "yes"
#   enable_horizon_heat: "yes"
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

check_enabled "enable_heat"
deploy_kolla --tags common,heat,horizon

source /etc/kolla/admin-openrc.sh
echo "==> Test Heat"
openstack orchestration service list
openstack stack list
