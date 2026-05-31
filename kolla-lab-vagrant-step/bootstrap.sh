#!/bin/bash
# Bootstrap automatique exécuté par Vagrant sur vm1 et vm2
set -e

echo "===> [$(hostname)] Mise à jour du système et paquets de base"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  python3-dev python3-venv python3-pip \
  libffi-dev gcc libssl-dev \
  git curl jq net-tools \
  lvm2 thin-provisioning-tools

echo "===> [$(hostname)] Configuration /etc/hosts"
sed -i '/vm1$/d; /vm2$/d' /etc/hosts
cat >> /etc/hosts <<EOF
192.168.56.10  vm1
192.168.56.11  vm2
EOF

echo "===> [$(hostname)] Activation de l'interface provider (eth2) sans IP"
PROVIDER_IF=""
for iface in enp0s9 eth2 ens9 enp0s10; do
  if ip link show "$iface" >/dev/null 2>&1; then
    PROVIDER_IF="$iface"
    break
  fi
done

if [ -z "$PROVIDER_IF" ]; then
  echo "!! Interface provider introuvable. Vérifie avec 'ip a'."
  exit 1
fi

echo "    -> Interface provider détectée : $PROVIDER_IF"
ip link set "$PROVIDER_IF" up

cat > /etc/netplan/99-provider.yaml <<EOF
network:
  version: 2
  ethernets:
    $PROVIDER_IF:
      dhcp4: false
      dhcp6: false
      optional: true
      accept-ra: false
EOF
chmod 600 /etc/netplan/99-provider.yaml
netplan apply || true

echo "$PROVIDER_IF" > /etc/kolla-provider-interface

echo "===> [$(hostname)] Configuration SSH pour l'utilisateur vagrant"
mkdir -p /home/vagrant/.ssh
chmod 700 /home/vagrant/.ssh
chmod 600 /home/vagrant/.ssh/id_rsa
chmod 644 /home/vagrant/.ssh/id_rsa.pub

PUB_KEY=$(cat /home/vagrant/.ssh/id_rsa.pub)
touch /home/vagrant/.ssh/authorized_keys
if ! grep -qF "$PUB_KEY" /home/vagrant/.ssh/authorized_keys; then
  echo "$PUB_KEY" >> /home/vagrant/.ssh/authorized_keys
fi
chmod 600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant:vagrant /home/vagrant/.ssh

cat > /home/vagrant/.ssh/config <<EOF
Host vm1 vm2 192.168.56.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
chmod 600 /home/vagrant/.ssh/config
chown vagrant:vagrant /home/vagrant/.ssh/config

echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
chmod 440 /etc/sudoers.d/vagrant

echo "===> [$(hostname)] Désactivation firewall (lab uniquement)"
systemctl stop ufw 2>/dev/null || true
systemctl disable ufw 2>/dev/null || true

echo "===> [$(hostname)] Désactivation swap (recommandé pour Kolla)"
swapoff -a || true
sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo ""
echo "============================================================"
echo " Bootstrap terminé sur $(hostname)"
echo " Interface management : enp0s8  (192.168.56.x)"
echo " Interface provider   : $PROVIDER_IF  (UP, sans IP)"
if [ "$(hostname)" = "vm1" ]; then
  echo " Disque Cinder        : /dev/sdb (30 Go, à préparer manuellement)"
fi
echo "============================================================"
