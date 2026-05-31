#!/usr/bin/env bash
# Crée un VG cinder-volumes sur un fichier loopback (LAB UNIQUEMENT)
# Pour la persistance au reboot, installer le service systemd fourni.
set -euo pipefail

IMG="/var/lib/cinder-volumes.img"
SIZE="40G"
LOOP="/dev/loop10"

if sudo vgs cinder-volumes >/dev/null 2>&1; then
  echo "[SKIP] VG cinder-volumes existe déjà."
  exit 0
fi

if [ ! -f "$IMG" ]; then
  sudo truncate -s "$SIZE" "$IMG"
fi

# Détache si déjà attaché
sudo losetup -d "$LOOP" 2>/dev/null || true
sudo losetup "$LOOP" "$IMG"
sudo pvcreate -f "$LOOP"
sudo vgcreate cinder-volumes "$LOOP"

sudo vgs cinder-volumes
echo "[OK] VG cinder-volumes créé sur $LOOP ($IMG)"
echo "[INFO] Pour la persistance : sudo cp systemd/cinder-loopback.service /etc/systemd/system/"
echo "                             sudo systemctl enable --now cinder-loopback.service"
