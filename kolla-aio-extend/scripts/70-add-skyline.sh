#!/usr/bin/env bash
# Phase 7 — Skyline (dashboard alternatif, en parallèle d'Horizon)
# Pré-requis dans /etc/kolla/globals.yml :
#   enable_skyline: "yes"
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

check_enabled "enable_skyline"
deploy_kolla --tags common,skyline

VIP=$(awk '/^kolla_internal_vip_address:/ {gsub(/"/,""); print $2}' /etc/kolla/globals.yml)
echo "[OK] Skyline : http://${VIP}:9999/"
