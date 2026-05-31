#!/usr/bin/env bash
# Vue d'ensemble : conteneurs Kolla + endpoints Keystone
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"
source /etc/kolla/admin-openrc.sh

echo "=== Conteneurs Kolla ==="
sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | sort

echo
echo "=== Services Keystone ==="
openstack service list

echo
echo "=== Endpoints ==="
openstack endpoint list
