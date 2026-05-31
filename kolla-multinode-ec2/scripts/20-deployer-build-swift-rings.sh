#!/usr/bin/env bash
# Sur node1 : génère les rings Swift (account/container/object) avec
# les 3 disques /d0,/d1,/d2 sur chacun des 3 nodes (= 9 devices par ring).
#
# Pré-requis : docker présent (installé par bootstrap-servers, mais on peut
#              aussi l'avoir via apt).
#
# Variables :
#   NODE_IPS  (obligatoire)  : "10.0.1.11 10.0.1.12 10.0.1.13"
#   KOLLA_IMG (optionnel)    : tag image swift-base
#
# Sorties : /etc/kolla/config/swift/{account,container,object}.{builder,ring.gz}
set -euo pipefail

NODE_IPS="${NODE_IPS:?Définir NODE_IPS=\"ip1 ip2 ip3\"}"
RING_DIR="/etc/kolla/config/swift"
IMG="${KOLLA_IMG:-quay.io/openstack.kolla/swift-base:2024.1-ubuntu-jammy}"
PARTITIONS=10
REPLICAS=3
MIN_PART_HOURS=1

sudo mkdir -p "$RING_DIR"
sudo chown "$USER:$USER" "$RING_DIR"

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

  zone=1
  for ip in $NODE_IPS; do
    for d in 0 1 2; do
      run_srb "$builder" add "r1z${zone}-${ip}:${PORT[$ring]}/d${d}" 1
    done
    zone=$((zone+1))
  done

  run_srb "$builder" rebalance
done

ls -l "$RING_DIR"
echo "[OK] Rings prêts (3 nodes × 3 disques = 9 devices par ring)"
