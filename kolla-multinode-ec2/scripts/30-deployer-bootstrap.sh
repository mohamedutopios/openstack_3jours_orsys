#!/usr/bin/env bash
# Sur node1 : installe Docker et configure les hôtes (étape "bootstrap-servers").
# Idempotent.
set -euo pipefail
# shellcheck disable=SC1091
source "$HOME/kolla-venv/bin/activate"
INVENTORY="${INVENTORY:-./multinode}"
[ -f "$INVENTORY" ] || { echo "Inventaire $INVENTORY introuvable"; exit 1; }

kolla-ansible -i "$INVENTORY" bootstrap-servers
