#!/usr/bin/env bash
# Phase 3.2 — Génère les rings Swift (account/container/object) via l'image
# kolla swift-base. À exécuter APRÈS un premier deploy Kolla (image présente).
#
# Variables :
#   STORAGE_IP   : IP de network_interface (ex. 192.168.10.50)
#   KOLLA_IMG    : tag image swift-base (défaut : 2024.1-ubuntu-jammy)
#
# Crée /etc/kolla/config/swift/{account,container,object}.{builder,ring.gz}
set -euo pipefail

STORAGE_IP="${STORAGE_IP:?Définir STORAGE_IP=<ip_storage>}"
RING_DIR="/etc/kolla/config/swift"
IMG="${KOLLA_IMG:-quay.io/openstack.kolla/swift-base:2024.1-ubuntu-jammy}"
PARTITIONS=10        # 2^10 = 1024 partitions (small lab)
REPLICAS=3
MIN_PART_HOURS=1

sudo mkdir -p "$RING_DIR"
sudo chown "$USER":"$USER" "$RING_DIR"

# Vérifier image disponible (sinon pull)
if ! sudo docker image inspect "$IMG" >/dev/null 2>&1; then
  echo "==> Pull $IMG"
  sudo docker pull "$IMG"
fi

run_srb() {
  sudo docker run --rm \
    -v "$RING_DIR:$RING_DIR" \
    --user "$(id -u):$(id -g)" \
    "$IMG" \
    swift-ring-builder "$@"
}

declare -A PORT=( [account]=6202 [container]=6201 [object]=6200 )

for ring in account container object; do
  builder="$RING_DIR/${ring}.builder"
  ringgz="$RING_DIR/${ring}.ring.gz"
  rm -f "$builder" "$ringgz"

  echo "==> Création $ring (parts=$PARTITIONS replicas=$REPLICAS)"
  run_srb "$builder" create "$PARTITIONS" "$REPLICAS" "$MIN_PART_HOURS"

  for d in 0 1 2; do
    run_srb "$builder" add "r1z1-${STORAGE_IP}:${PORT[$ring]}/d${d}" 1
  done

  run_srb "$builder" rebalance
done

ls -l "$RING_DIR"
echo "[OK] Rings prêts dans $RING_DIR"
