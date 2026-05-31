#!/usr/bin/env bash
# Sourcé par les autres scripts. Active venv + admin-openrc.
set -euo pipefail

VENV="${KOLLA_VENV:-$HOME/kolla-venv}"
INVENTORY="${KOLLA_INVENTORY:-./all-in-one}"

[ -f "$VENV/bin/activate" ] || { echo "Venv introuvable : $VENV"; exit 1; }
# shellcheck disable=SC1091
source "$VENV/bin/activate"

[ -f "$INVENTORY" ] || { echo "Inventaire introuvable : $INVENTORY (cwd=$(pwd))"; exit 1; }
[ -f /etc/kolla/globals.yml ] || { echo "globals.yml manquant"; exit 1; }

deploy_kolla() {
  echo "==> kolla-ansible deploy ($*)"
  kolla-ansible -i "$INVENTORY" deploy "$@"
}

check_enabled() {
  local key="$1"
  if ! grep -E "^\s*${key}:\s*\"?yes\"?" /etc/kolla/globals.yml >/dev/null; then
    echo "[ERREUR] '${key}: yes' absent de /etc/kolla/globals.yml"
    echo "        Ajoutez-le puis relancez."
    exit 1
  fi
}
