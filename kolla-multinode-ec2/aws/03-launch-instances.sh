#!/usr/bin/env bash
# Lance 3 instances Ubuntu 22.04 dans le subnet mgmt avec :
#  - IP privée fixée (NODE{1,2,3}_IP)
#  - 2 SG (intra + admin)
#  - root EBS + 3 EBS supplémentaires (Cinder, Swift x2 — Swift 3e ajouté plus tard)
#  - cloud-init de bootstrap minimal
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
source "$STATE_FILE"

USERDATA_FILE="$(dirname "$0")/userdata-cloudinit.yaml"
[ -f "$USERDATA_FILE" ] || { echo "userdata file manquant"; exit 1; }
USERDATA_B64=$(base64 -w0 "$USERDATA_FILE" 2>/dev/null || base64 "$USERDATA_FILE" | tr -d '\n')

# Mappings EBS : root /dev/sda1, puis 4 volumes de données /dev/sd[bcde]
# Sur Nitro, ils apparaissent en /dev/nvme0n1 (root), /dev/nvme[1-4]n1 (data)
BLOCK_MAP="DeviceName=/dev/sda1,Ebs={VolumeSize=$ROOT_GB,VolumeType=gp3,DeleteOnTermination=true}"
BLOCK_MAP="$BLOCK_MAP DeviceName=/dev/sdb,Ebs={VolumeSize=$CINDER_GB,VolumeType=gp3,DeleteOnTermination=true}"
BLOCK_MAP="$BLOCK_MAP DeviceName=/dev/sdc,Ebs={VolumeSize=$SWIFT_GB,VolumeType=gp3,DeleteOnTermination=true}"
BLOCK_MAP="$BLOCK_MAP DeviceName=/dev/sdd,Ebs={VolumeSize=$SWIFT_GB,VolumeType=gp3,DeleteOnTermination=true}"
BLOCK_MAP="$BLOCK_MAP DeviceName=/dev/sde,Ebs={VolumeSize=$SWIFT_GB,VolumeType=gp3,DeleteOnTermination=true}"

declare -A IPS=( [node1]=$NODE1_IP [node2]=$NODE2_IP [node3]=$NODE3_IP )
declare -A INST_IDS=()

for n in node1 node2 node3; do
  echo "==> Lancement $n (${IPS[$n]})"
  IID=$(aws ec2 run-instances --region "$AWS_REGION" \
    --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --subnet-id "$SUBNET_MGMT_ID" \
    --private-ip-address "${IPS[$n]}" \
    --security-group-ids "$SG_INTRA_ID" "$SG_ADMIN_ID" \
    --block-device-mappings $BLOCK_MAP \
    --user-data "$(cat "$USERDATA_FILE")" \
    --tag-specifications \
      "ResourceType=instance,Tags=[{Key=Name,Value=$n},{Key=Project,Value=$PROJECT_TAG}]" \
      "ResourceType=volume,Tags=[{Key=Project,Value=$PROJECT_TAG}]" \
    --query 'Instances[0].InstanceId' --output text)
  INST_IDS[$n]=$IID
done

echo "==> Attente état running"
aws ec2 wait instance-running --region "$AWS_REGION" \
  --instance-ids "${INST_IDS[node1]}" "${INST_IDS[node2]}" "${INST_IDS[node3]}"

{
  echo "export NODE1_ID=${INST_IDS[node1]}"
  echo "export NODE2_ID=${INST_IDS[node2]}"
  echo "export NODE3_ID=${INST_IDS[node3]}"
} >> "$STATE_FILE"

echo
echo "==> Récap"
aws ec2 describe-instances --region "$AWS_REGION" \
  --instance-ids "${INST_IDS[node1]}" "${INST_IDS[node2]}" "${INST_IDS[node3]}" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,InstanceId,PrivateIpAddress,PublicIpAddress]' \
  --output table
