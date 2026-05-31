#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
source "$HOME/kolla-venv/bin/activate"
INVENTORY="${INVENTORY:-./multinode}"

kolla-ansible -i "$INVENTORY" post-deploy

echo
echo "[OK] /etc/kolla/admin-openrc.sh créé."
echo "    source /etc/kolla/admin-openrc.sh"
