#!/usr/bin/env bash
# Tests de fumée post-déploiement
set -euo pipefail

VENV="$HOME/kolla-venv"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
# shellcheck disable=SC1091
source /etc/kolla/admin-openrc.sh

echo "=== Services Keystone ==="
openstack service list

echo "=== Compute (Nova) ==="
openstack compute service list

echo "=== Réseau (Neutron) ==="
openstack network agent list

echo "=== Volume (Cinder) ==="
openstack volume service list

echo
echo "Pour créer une instance de démo :"
echo "  $VENV/share/kolla-ansible/init-runonce"
