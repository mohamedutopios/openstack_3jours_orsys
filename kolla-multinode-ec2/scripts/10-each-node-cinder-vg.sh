#!/usr/bin/env bash
# À EXÉCUTER SUR CHAQUE NŒUD (node1, node2, node3).
# Crée le VG `cinder-volumes` sur le device passé en argument.
# Usage : sudo bash 10-each-node-cinder-vg.sh /dev/nvme1n1
set -euo pipefail

DEV="${1:-}"
[ -b "$DEV" ] || { echo "Usage : sudo $0 /dev/nvmeXn1"; exit 1; }

if vgs cinder-volumes >/dev/null 2>&1; then
  echo "[SKIP] VG cinder-volumes existe déjà."
  exit 0
fi

# Vérifie que le device n'est pas monté ni partitionné
if mount | grep -q "^$DEV"; then
  echo "[ERREUR] $DEV est monté."; exit 1
fi

pvcreate -ff -y "$DEV"
vgcreate cinder-volumes "$DEV"
vgs cinder-volumes
echo "[OK] VG cinder-volumes créé sur $DEV"
