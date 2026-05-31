#!/usr/bin/env bash
# Bootstrap + prechecks + deploy + post-deploy
# Pré-requis :
#   - venv Kolla activé OU présent dans ~/kolla-venv
#   - /etc/kolla/globals.yml et /etc/kolla/passwords.yml en place
#   - inventaire ./all-in-one présent
#   - VG cinder-volumes créé
set -euo pipefail

VENV="$HOME/kolla-venv"
INVENTORY="./all-in-one"

# shellcheck disable=SC1091
source "$VENV/bin/activate"

[ -f /etc/kolla/globals.yml ]  || { echo "globals.yml manquant"; exit 1; }
[ -f /etc/kolla/passwords.yml ] || { echo "passwords.yml manquant — exécuter kolla-genpwd"; exit 1; }
[ -f "$INVENTORY" ]            || { echo "Inventaire $INVENTORY manquant"; exit 1; }
sudo vgs cinder-volumes >/dev/null 2>&1 || { echo "VG cinder-volumes manquant"; exit 1; }

echo "==> bootstrap-servers"
kolla-ansible -i "$INVENTORY" bootstrap-servers

echo "==> prechecks"
kolla-ansible -i "$INVENTORY" prechecks

echo "==> deploy (long, 20-40 min)"
kolla-ansible -i "$INVENTORY" deploy

echo "==> post-deploy (génère /etc/kolla/admin-openrc.sh)"
kolla-ansible -i "$INVENTORY" post-deploy

echo
echo "[OK] Déploiement terminé."
echo "    source /etc/kolla/admin-openrc.sh"
echo "    openstack service list"
