#!/bin/bash
# À exécuter sur vm1 APRÈS bootstrap, AVANT kolla-ansible deploy.
# Génère ~/host_vars/vmX avec les bons noms d'interface détectés
# sur chaque VM (ce qui résout le problème eth* vs enp0s*).
set -e

mkdir -p ~/host_vars

for host in vm1 vm2 vm3; do
  echo "===> Récupération des interfaces sur $host"
  MGMT_IF=$(ssh "$host" cat /etc/kolla-mgmt-interface)
  PROVIDER_IF=$(ssh "$host" cat /etc/kolla-provider-interface)
  cat > ~/host_vars/$host <<HVARS
---
network_interface: "$MGMT_IF"
neutron_external_interface: "$PROVIDER_IF"
HVARS
  echo "    $host : mgmt=$MGMT_IF provider=$PROVIDER_IF"
done

# Lien symbolique pour que kolla-ansible (qui lit ./host_vars relatif à l'inventaire) trouve
if [ ! -e "$(dirname ~/multinode)/host_vars" ]; then
  ln -sf ~/host_vars "$(dirname ~/multinode)/host_vars" 2>/dev/null || true
fi

echo ""
echo "============================================================"
echo " Fichiers host_vars générés dans ~/host_vars/"
echo " Tu peux maintenant relancer : kolla-ansible -i ~/multinode prechecks"
echo "============================================================"
