#!/usr/bin/env bash
# Smoke tests : services up, agents online, Swift et Cinder fonctionnels.
set -euo pipefail
# shellcheck disable=SC1091
source "$HOME/kolla-venv/bin/activate"
source /etc/kolla/admin-openrc.sh

echo "=== Catalogue Keystone ==="
openstack service list

echo "=== Endpoints ==="
openstack endpoint list

echo "=== Compute (Nova) — 3 hyperviseurs attendus ==="
openstack compute service list
openstack hypervisor list

echo "=== Réseau (Neutron) ==="
openstack network agent list

echo "=== Volume (Cinder) — 3 cinder-volume attendus ==="
openstack volume service list

echo "=== Object (Swift) ==="
openstack object store account show

echo "=== Heat ==="
openstack orchestration service list

echo "=== Barbican ==="
openstack secret list || true

echo
echo "=== Test Swift : créer container + upload ==="
echo "hello multinode $(date)" > /tmp/hello.txt
openstack container create demo
openstack object create demo /tmp/hello.txt
openstack object list demo

echo
echo "=== Test Cinder : créer volume 1 GiB ==="
openstack volume create --size 1 demo-vol
openstack volume list

echo
echo "[OK] Tests terminés. Horizon : http://<EIP-node1>/"
