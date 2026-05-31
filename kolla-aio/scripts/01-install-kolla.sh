#!/usr/bin/env bash
# Installation de Kolla-Ansible 2024.1 Caracal dans un venv
set -euo pipefail

VENV="$HOME/kolla-venv"

python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"

pip install -U pip
pip install 'ansible-core>=2.16,<2.17.99'
pip install git+https://opendev.org/openstack/kolla-ansible@stable/2024.1

# Collections Galaxy + dépendances
kolla-ansible install-deps

# Client OpenStack (utile pour la suite)
pip install python-openstackclient python-neutronclient python-cinderclient

echo "[OK] Kolla-Ansible installé dans $VENV"
echo "    Activez le venv :  source $VENV/bin/activate"
