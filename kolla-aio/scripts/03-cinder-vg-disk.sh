#!/usr/bin/env bash
# Crée le VG cinder-volumes sur un disque réel.
# Usage : sudo bash 03-cinder-vg-disk.sh /dev/sdb
set -euo pipefail

DISK="${1:-}"
if [ -z "$DISK" ] || [ ! -b "$DISK" ]; then
  echo "Usage : sudo $0 /dev/sdX  (disque dédié, sera ÉCRASÉ)"
  exit 1
fi

read -r -p "ATTENTION : $DISK va être effacé. Confirmer ? (yes/NO) " ans
[ "$ans" = "yes" ] || { echo "Annulé."; exit 1; }

pvcreate -ff -y "$DISK"
vgcreate cinder-volumes "$DISK"
vgs cinder-volumes
echo "[OK] VG cinder-volumes créé sur $DISK"
