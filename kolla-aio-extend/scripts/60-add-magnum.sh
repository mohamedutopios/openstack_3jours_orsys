#!/usr/bin/env bash
# Phase 6 — Magnum (orchestration de clusters Kubernetes)
# Pré-requis : Heat (Phase 2) + Barbican (Phase 1).
# Pré-requis dans /etc/kolla/globals.yml :
#   enable_magnum: "yes"
#   enable_horizon_magnum: "yes"
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

check_enabled "enable_heat"
check_enabled "enable_barbican"
check_enabled "enable_magnum"

deploy_kolla --tags common,magnum,horizon

source /etc/kolla/admin-openrc.sh
echo "==> Test Magnum"
openstack coe service list
