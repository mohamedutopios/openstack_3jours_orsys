#!/bin/bash
# Bootstrap idempotent - détecte dynamiquement les interfaces
# (compatible eth0/eth1/eth2 ET enp0s3/enp0s8/enp0s9)
set -e

echo "===> Détection des interfaces réseau"

# Liste toutes les interfaces ethernet (hors lo), dans l'ordre
INTERFACES=$(ls /sys/class/net/ | grep -E '^(eth|en)' | sort)
echo "    Interfaces détectées : $INTERFACES"

NAT_IF=$(echo "$INTERFACES" | sed -n '1p')
MGMT_IF=$(echo "$INTERFACES" | sed -n '2p')
PROVIDER_IF=$(echo "$INTERFACES" | sed -n '3p')

if [ -z "$NAT_IF" ] || [ -z "$MGMT_IF" ] || [ -z "$PROVIDER_IF" ]; then
  echo "!! Erreur : 3 interfaces attendues, trouvées : NAT=$NAT_IF MGMT=$MGMT_IF PROVIDER=$PROVIDER_IF"
  exit 1
fi

echo "    NAT      : $NAT_IF"
echo "    Mgmt     : $MGMT_IF"
echo "    Provider : $PROVIDER_IF"

# Mémorise les noms pour usage ultérieur
echo "$MGMT_IF"     > /etc/kolla-mgmt-interface
echo "$PROVIDER_IF" > /etc/kolla-provider-interface

# Détecte le hostname cible via /tmp/vagrant_hostname (déposé par Vagrant)
if [ -f /tmp/vagrant_hostname ]; then
  TARGET_HOST=$(cat /tmp/vagrant_hostname)
  hostnamectl set-hostname "$TARGET_HOST"
else
  TARGET_HOST=$(hostname)
fi

case "$TARGET_HOST" in
  vm1) MGMT_IP="192.168.56.10" ;;
  vm2) MGMT_IP="192.168.56.11" ;;
  vm3) MGMT_IP="192.168.56.12" ;;
  *)
    echo "!! Hostname inconnu : $TARGET_HOST"
    exit 1
    ;;
esac

echo "===> Hostname: $TARGET_HOST, Mgmt IP: $MGMT_IP"

echo "===> Reconfiguration netplan complète"
rm -f /etc/netplan/*.yaml
cat > /etc/netplan/01-kolla.yaml <<EOF
network:
  version: 2
  ethernets:
    $NAT_IF:
      dhcp4: true
    $MGMT_IF:
      addresses: [$MGMT_IP/24]
    $PROVIDER_IF:
      dhcp4: false
      dhcp6: false
      optional: true
      accept-ra: false
EOF
chmod 600 /etc/netplan/01-kolla.yaml
netplan apply
ip link set "$PROVIDER_IF" up

echo "===> Paquets de base"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  python3-dev python3-venv python3-pip \
  libffi-dev gcc libssl-dev \
  git curl jq net-tools \
  lvm2 thin-provisioning-tools

echo "===> /etc/hosts"
sed -i '/vm1$/d; /vm2$/d; /vm3$/d' /etc/hosts
cat >> /etc/hosts <<EOF
192.168.56.10  vm1
192.168.56.11  vm2
192.168.56.12  vm3
EOF

echo "===> SSH"
mkdir -p /home/vagrant/.ssh
chmod 700 /home/vagrant/.ssh
if [ -f /home/vagrant/.ssh/id_rsa ]; then
  chmod 600 /home/vagrant/.ssh/id_rsa
  chmod 644 /home/vagrant/.ssh/id_rsa.pub
  PUB_KEY=$(cat /home/vagrant/.ssh/id_rsa.pub)
  touch /home/vagrant/.ssh/authorized_keys
  grep -qF "$PUB_KEY" /home/vagrant/.ssh/authorized_keys || echo "$PUB_KEY" >> /home/vagrant/.ssh/authorized_keys
  chmod 600 /home/vagrant/.ssh/authorized_keys
fi

cat > /home/vagrant/.ssh/config <<EOF
Host vm1 vm2 vm3 192.168.56.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
chmod 600 /home/vagrant/.ssh/config
chown -R vagrant:vagrant /home/vagrant/.ssh

echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
chmod 440 /etc/sudoers.d/vagrant

echo "===> Firewall et swap"
systemctl stop ufw 2>/dev/null || true
systemctl disable ufw 2>/dev/null || true
swapoff -a || true
sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo ""
echo "============================================================"
echo " Bootstrap OK sur $TARGET_HOST"
echo "   Mgmt     : $MGMT_IF ($MGMT_IP)"
echo "   Provider : $PROVIDER_IF (UP, sans IP)"
if [ "$TARGET_HOST" = "vm3" ]; then
  echo "   Disque Cinder : /dev/sdb (à préparer LVM manuellement)"
fi
echo "============================================================"
