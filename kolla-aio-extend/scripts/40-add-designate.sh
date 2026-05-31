#!/usr/bin/env bash
# Phase 4 — Designate (DNSaaS) avec backend BIND9
# Pré-requis dans /etc/kolla/globals.yml :
#   enable_designate: "yes"
#   designate_backend: "bind9"
#   designate_ns_record:
#     - "ns1.example.org"
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

check_enabled "enable_designate"
deploy_kolla --tags common,designate

source /etc/kolla/admin-openrc.sh
echo "==> Test Designate"
openstack zone create --email admin@example.org example.org. || true
openstack zone list
