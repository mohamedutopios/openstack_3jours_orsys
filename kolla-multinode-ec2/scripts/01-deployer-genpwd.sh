#!/usr/bin/env bash
# Génère /etc/kolla/passwords.yml (auto-rempli).
# Affiche le mot de passe admin Horizon à la fin.
set -euo pipefail
# shellcheck disable=SC1091
source "$HOME/kolla-venv/bin/activate"

if grep -q '^keystone_admin_password:.*[a-zA-Z0-9]' /etc/kolla/passwords.yml 2>/dev/null; then
  echo "[SKIP] /etc/kolla/passwords.yml semble déjà rempli."
else
  kolla-genpwd
fi

echo
echo "Mot de passe admin Horizon :"
grep '^keystone_admin_password:' /etc/kolla/passwords.yml
