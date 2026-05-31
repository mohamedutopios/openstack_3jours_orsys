#!/usr/bin/env bash
# À EXÉCUTER SUR CHAQUE NŒUD.
# Formate 3 devices en XFS avec label KOLLA_SWIFT_DATA et les monte
# de manière persistante (UUID + /etc/fstab) sous /srv/node/d0..d2.
# Usage : sudo bash 11-each-node-swift-disks.sh /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage : sudo $0 <dev0> <dev1> <dev2>  (3 block devices)"
  exit 1
fi
for d in "$@"; do
  [ -b "$d" ] || { echo "Pas un block device : $d"; exit 1; }
done

apt install -y xfsprogs >/dev/null

mkdir -p /srv/node

i=0
for DEV in "$@"; do
  MNT="/srv/node/d${i}"

  if mountpoint -q "$MNT"; then
    echo "[SKIP] $MNT déjà monté"; ((i++)); continue
  fi

  if ! blkid -o value -s LABEL "$DEV" 2>/dev/null | grep -q KOLLA_SWIFT_DATA; then
    mkfs.xfs -f -L KOLLA_SWIFT_DATA "$DEV"
  fi

  UUID=$(blkid -o value -s UUID "$DEV")
  mkdir -p "$MNT"

  # Persistance : remplace toute ancienne entrée pour ce mountpoint
  sed -i "\|[[:space:]]${MNT}[[:space:]]|d" /etc/fstab
  echo "UUID=$UUID  $MNT  xfs  noatime  0  2" >> /etc/fstab

  mount "$MNT"
  chown -R 42445:42445 "$MNT" 2>/dev/null || true
  ((i++))
done

echo
df -h /srv/node/d0 /srv/node/d1 /srv/node/d2
echo "[OK] 3 disques Swift montés (persistants)."
