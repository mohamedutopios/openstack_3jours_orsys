#!/usr/bin/env bash
# Ajoute la VIP comme IP secondaire sur l'ENI primaire de node1.
# AWS ne supporte pas le VRRP/multicast → keepalived sera désactivé côté Kolla.
# La VIP est donc "fixée" à node1 (SPOF acceptable en formation).
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
source "$STATE_FILE"

echo "==> ENI primaire de node1"
ENI_NODE1=$(aws ec2 describe-instances --region "$AWS_REGION" \
  --instance-ids "$NODE1_ID" \
  --query 'Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==`0`].NetworkInterfaceId' \
  --output text)

echo "    ENI primaire = $ENI_NODE1"
echo "==> Assignation $VIP comme IP secondaire"
aws ec2 assign-private-ip-addresses --region "$AWS_REGION" \
  --network-interface-id "$ENI_NODE1" \
  --private-ip-addresses "$VIP" \
  --allow-reassignment

echo "[OK] VIP $VIP attaché à node1 ($ENI_NODE1)"
echo
echo "Sur node1, ajouter l'IP au niveau OS (sinon Linux ne répond pas) :"
echo "   sudo ip addr add ${VIP}/24 dev ens5"
echo "(persistant via netplan — voir le playbook ansible/prep-hosts.yml)"
