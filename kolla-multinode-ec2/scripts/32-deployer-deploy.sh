#!/usr/bin/env bash
# Déploiement complet — long (30-60 min).
set -euo pipefail
# shellcheck disable=SC1091
source "$HOME/kolla-venv/bin/activate"
INVENTORY="${INVENTORY:-./multinode}"

# Vérifs critiques avant de partir
[ -f /etc/kolla/globals.yml ]   || { echo "globals.yml manquant"; exit 1; }
[ -f /etc/kolla/passwords.yml ] || { echo "passwords.yml manquant"; exit 1; }
for f in account container object; do
  [ -f "/etc/kolla/config/swift/${f}.ring.gz" ] || {
    echo "[ERREUR] /etc/kolla/config/swift/${f}.ring.gz manquant"
    echo "         Lancez d'abord scripts/20-deployer-build-swift-rings.sh"
    exit 1
  }
done

kolla-ansible -i "$INVENTORY" deploy
