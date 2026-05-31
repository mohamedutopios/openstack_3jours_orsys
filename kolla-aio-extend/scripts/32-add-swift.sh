#!/usr/bin/env bash
# Phase 3.3 — Active Swift dans Kolla.
# Pré-requis dans /etc/kolla/globals.yml :
#   enable_swift: "yes"
#   swift_devices_match_mode: "strict"
#   swift_devices_name: "KOLLA_SWIFT_DATA"
# Pré-requis disques : scripts 30- et 31- exécutés.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/_common.sh"

check_enabled "enable_swift"

for f in account container object; do
  [ -f "/etc/kolla/config/swift/${f}.ring.gz" ] || {
    echo "[ERREUR] /etc/kolla/config/swift/${f}.ring.gz manquant — lancez 31-build-swift-rings.sh"
    exit 1
  }
done

for d in 0 1 2; do
  mountpoint -q "/srv/node/d${d}" || {
    echo "[ERREUR] /srv/node/d${d} non monté — lancez 30-prepare-swift-disks.sh"
    exit 1
  }
done

deploy_kolla --tags common,swift

source /etc/kolla/admin-openrc.sh
echo "==> Test Swift"
openstack object store account show
echo "hello swift $(date)" > /tmp/hello.txt
openstack container create demo
openstack object create demo /tmp/hello.txt
openstack object list demo
