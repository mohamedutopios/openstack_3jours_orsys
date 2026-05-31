#!/usr/bin/env bash
# Crée et attache une 2ᵉ ENI à chaque instance, dans le subnet ext.
# Désactive le source/destination check sur cette ENI (indispensable pour
# que Neutron puisse forwarder du trafic avec des IPs arbitraires).
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
source "$STATE_FILE"

declare -A INSTANCE_IDS=( [node1]=$NODE1_ID [node2]=$NODE2_ID [node3]=$NODE3_ID )

for n in node1 node2 node3; do
  IID="${INSTANCE_IDS[$n]}"

  echo "==> Création ENI ext pour $n"
  ENI_ID=$(aws ec2 create-network-interface --region "$AWS_REGION" \
    --subnet-id "$SUBNET_EXT_ID" \
    --groups "$SG_INTRA_ID" \
    --description "kolla-ext-$n" \
    --tag-specifications \
      "ResourceType=network-interface,Tags=[{Key=Name,Value=kolla-ext-$n},{Key=Project,Value=$PROJECT_TAG}]" \
    --query 'NetworkInterface.NetworkInterfaceId' --output text)

  echo "==> Désactivation source/dest check sur $ENI_ID"
  aws ec2 modify-network-interface-attribute --region "$AWS_REGION" \
    --network-interface-id "$ENI_ID" --no-source-dest-check

  echo "==> Attachement à $IID en device-index 1"
  aws ec2 attach-network-interface --region "$AWS_REGION" \
    --instance-id "$IID" \
    --network-interface-id "$ENI_ID" \
    --device-index 1 >/dev/null

  echo "    [OK] $n ext ENI = $ENI_ID"
done

echo
echo "Sur chaque nœud, l'ENI #2 apparaîtra en 'ens6' après un :"
echo "   sudo ip link set ens6 up"
echo "(pas d'IP à configurer côté OS — Neutron utilise l'interface en L2 brut)"
