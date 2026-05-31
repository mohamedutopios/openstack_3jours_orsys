#!/usr/bin/env bash
# Sur node1 : installe Kolla-Ansible 2024.1 dans un venv, copie les exemples
# de conf, et installe les clients OpenStack.
set -euo pipefail

VENV="$HOME/kolla-venv"

[ -d "$VENV" ] || python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"

pip install -U pip
pip install 'ansible-core>=2.16,<2.17.99'
pip install git+https://opendev.org/openstack/kolla-ansible@stable/2024.1
kolla-ansible install-deps

pip install python-openstackclient python-neutronclient python-cinderclient \
            python-swiftclient python-barbicanclient python-heatclient

sudo mkdir -p /etc/kolla
sudo chown "$USER:$USER" /etc/kolla
cp -r "$VENV/share/kolla-ansible/etc_examples/kolla/." /etc/kolla/

echo "[OK] Kolla-Ansible installé."
echo "    source $VENV/bin/activate"
echo "    Suivant : copier kolla/globals.yml -> /etc/kolla/globals.yml"
echo "             copier kolla/multinode    -> ./multinode"
