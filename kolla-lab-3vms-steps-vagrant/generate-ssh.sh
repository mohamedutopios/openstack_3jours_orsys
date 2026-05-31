#!/bin/bash
set -e
SSH_DIR="$(dirname "$0")/ssh"
mkdir -p "$SSH_DIR"
if [ -f "$SSH_DIR/id_rsa" ]; then
  echo "Les clés existent déjà. Régénération..."
  rm -f "$SSH_DIR"/id_rsa*
fi
ssh-keygen -t rsa -b 4096 -f "$SSH_DIR/id_rsa" -N "" -C "kolla-lab"
echo ""
echo "=============================================="
echo " Clés SSH générées dans : $SSH_DIR"
echo " Tu peux maintenant lancer : vagrant up"
echo "=============================================="
