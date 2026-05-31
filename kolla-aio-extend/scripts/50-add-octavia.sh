#!/usr/bin/env bash
# Phase 5 — Octavia (LBaaS)
# Pré-requis : Phase 1 (Barbican) déjà en place.
# Pré-requis dans /etc/kolla/globals.yml :
#   enable_octavia: "yes"
#   octavia_auto_configure: "yes"
#   octavia_amp_flavor: { ... }
#   octavia_amp_network: { ... }
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

check_enabled "enable_barbican"
check_enabled "enable_octavia"

deploy_kolla --tags common,octavia

source /etc/kolla/admin-openrc.sh
echo "==> Test Octavia"
openstack loadbalancer provider list
openstack image list --tag amphora || true
