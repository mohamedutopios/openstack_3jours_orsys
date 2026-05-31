#!/usr/bin/env bash
# Phase 3.1 — Prépare 3 disques loopback pour Swift (LAB).
# Crée /srv/swift-disk-{0,1,2}.img, formate XFS avec label KOLLA_SWIFT_DATA,
# monte sous /srv/node/d{0,1,2}.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Doit être lancé en root (sudo)"; exit 1
fi

SIZE="${SIZE:-10G}"

apt install -y xfsprogs >/dev/null

mkdir -p /srv/node

for i in 0 1 2; do
  IMG="/srv/swift-disk-${i}.img"
  LOOP="/dev/loop$((20+i))"
  MNT="/srv/node/d${i}"

  if mountpoint -q "$MNT"; then
    echo "[SKIP] $MNT déjà monté"
    continue
  fi

  [ -f "$IMG" ] || truncate -s "$SIZE" "$IMG"

  losetup -d "$LOOP" 2>/dev/null || true
  losetup "$LOOP" "$IMG"

  if ! blkid -o value -s LABEL "$LOOP" 2>/dev/null | grep -q KOLLA_SWIFT_DATA; then
    mkfs.xfs -f -L KOLLA_SWIFT_DATA "$LOOP"
  fi

  mkdir -p "$MNT"
  mount -o noatime "$LOOP" "$MNT"
  chown -R 42445:42445 "$MNT" 2>/dev/null || true   # uid swift dans les images Kolla
done

echo
echo "==> État final :"
lsblk -o NAME,SIZE,LABEL,MOUNTPOINT | grep -E 'loop2[0-2]|swift|d[0-2]'
df -h /srv/node/d0 /srv/node/d1 /srv/node/d2
echo
echo "Pour la persistance au reboot :"
echo "  sudo cp systemd/swift-loopback.service /etc/systemd/system/"
echo "  sudo systemctl enable --now swift-loopback.service"
