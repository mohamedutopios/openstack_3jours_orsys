#!/usr/bin/env bash
# Phase 1 — Barbican
# Pré-requis dans /etc/kolla/globals.yml :
#   enable_barbican: "yes"
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

check_enabled "enable_barbican"
deploy_kolla --tags common,barbican

source /etc/kolla/admin-openrc.sh
echo "==> Test Barbican"
openstack secret store --name kolla-test --payload "S3cr3t!"
openstack secret list
