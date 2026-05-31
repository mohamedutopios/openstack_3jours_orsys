#!/usr/bin/env bash
# Crée 2 SG :
#  - kolla-sg-intra : tout autorisé entre membres du SG (intra-cluster)
#  - kolla-sg-admin : SSH/HTTP/HTTPS/9999 depuis ADMIN_IP_CIDR
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"
source "$STATE_FILE"

aws_tag() {
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=$PROJECT_TAG}]"
}

echo "==> SG intra-cluster"
SG_INTRA_ID=$(aws ec2 create-security-group --region "$AWS_REGION" \
  --group-name kolla-sg-intra --description "Kolla intra-cluster all-allow" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(aws_tag security-group kolla-sg-intra)" \
  --query 'GroupId' --output text)

# Tout autorisé entre membres du SG
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
  --group-id "$SG_INTRA_ID" \
  --ip-permissions "IpProtocol=-1,UserIdGroupPairs=[{GroupId=$SG_INTRA_ID}]" >/dev/null

echo "==> SG admin (depuis $ADMIN_IP_CIDR)"
SG_ADMIN_ID=$(aws ec2 create-security-group --region "$AWS_REGION" \
  --group-name kolla-sg-admin --description "SSH+HTTP+HTTPS+Skyline from admin IP" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(aws_tag security-group kolla-sg-admin)" \
  --query 'GroupId' --output text)

for port in 22 80 443 9999 6080; do
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
    --group-id "$SG_ADMIN_ID" \
    --protocol tcp --port "$port" --cidr "$ADMIN_IP_CIDR" >/dev/null
done

{
  echo "export SG_INTRA_ID=$SG_INTRA_ID"
  echo "export SG_ADMIN_ID=$SG_ADMIN_ID"
} >> "$STATE_FILE"

echo "[OK] SG_INTRA=$SG_INTRA_ID  SG_ADMIN=$SG_ADMIN_ID"
