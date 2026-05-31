#!/usr/bin/env bash
# Crée VPC + 2 subnets (mgmt et ext) + IGW + Route Tables.
# Écrit les IDs dans state.env.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

aws_tag() {
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=$PROJECT_TAG}]"
}

echo "==> VPC ($VPC_CIDR)"
VPC_ID=$(aws ec2 create-vpc --region "$AWS_REGION" \
  --cidr-block "$VPC_CIDR" \
  --tag-specifications "$(aws_tag vpc kolla-vpc)" \
  --query 'Vpc.VpcId' --output text)

aws ec2 modify-vpc-attribute --region "$AWS_REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames

echo "==> Internet Gateway"
IGW_ID=$(aws ec2 create-internet-gateway --region "$AWS_REGION" \
  --tag-specifications "$(aws_tag internet-gateway kolla-igw)" \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --region "$AWS_REGION" --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"

echo "==> Subnet mgmt ($SUBNET_MGMT_CIDR / $AWS_AZ)"
SUBNET_MGMT_ID=$(aws ec2 create-subnet --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" --cidr-block "$SUBNET_MGMT_CIDR" \
  --availability-zone "$AWS_AZ" \
  --tag-specifications "$(aws_tag subnet kolla-subnet-mgmt)" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --region "$AWS_REGION" --subnet-id "$SUBNET_MGMT_ID" --map-public-ip-on-launch

echo "==> Subnet ext ($SUBNET_EXT_CIDR / $AWS_AZ)"
SUBNET_EXT_ID=$(aws ec2 create-subnet --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" --cidr-block "$SUBNET_EXT_CIDR" \
  --availability-zone "$AWS_AZ" \
  --tag-specifications "$(aws_tag subnet kolla-subnet-ext)" \
  --query 'Subnet.SubnetId' --output text)

echo "==> Route Table publique (0.0.0.0/0 → IGW)"
RT_ID=$(aws ec2 create-route-table --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "$(aws_tag route-table kolla-rt-public)" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --region "$AWS_REGION" --route-table-id "$RT_ID" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 associate-route-table --region "$AWS_REGION" --route-table-id "$RT_ID" --subnet-id "$SUBNET_MGMT_ID" >/dev/null
aws ec2 associate-route-table --region "$AWS_REGION" --route-table-id "$RT_ID" --subnet-id "$SUBNET_EXT_ID" >/dev/null

# Sauver les IDs
{
  echo "export VPC_ID=$VPC_ID"
  echo "export IGW_ID=$IGW_ID"
  echo "export SUBNET_MGMT_ID=$SUBNET_MGMT_ID"
  echo "export SUBNET_EXT_ID=$SUBNET_EXT_ID"
  echo "export RT_ID=$RT_ID"
} > "$STATE_FILE"

echo "[OK] VPC=$VPC_ID  Subnets=$SUBNET_MGMT_ID,$SUBNET_EXT_ID  → $STATE_FILE"
