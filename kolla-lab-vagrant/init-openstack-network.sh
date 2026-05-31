#!/bin/bash
# Crée un réseau provider OpenStack sur le subnet host-only 192.168.57.0/24
# Les instances lancées auront des IPs accessibles depuis Windows.
#
# À exécuter sur vm1 APRÈS `kolla-ansible post-deploy` et `source admin-openrc.sh`
set -e

echo "===> Création du réseau provider 'provider-net'"
openstack network create \
  --share \
  --provider-physical-network physnet1 \
  --provider-network-type flat \
  --external \
  provider-net

echo "===> Création du subnet 192.168.57.0/24"
# Important : pool 100-200 pour éviter conflit avec .1 (host Windows) et .10/.11 (VMs)
openstack subnet create \
  --network provider-net \
  --subnet-range 192.168.57.0/24 \
  --allocation-pool start=192.168.57.100,end=192.168.57.200 \
  --gateway 192.168.57.1 \
  --dns-nameserver 8.8.8.8 \
  --no-dhcp \
  provider-subnet

echo "===> Téléchargement et upload de l'image Cirros"
if ! openstack image show cirros >/dev/null 2>&1; then
  wget -q http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img -O /tmp/cirros.img
  openstack image create \
    --container-format bare \
    --disk-format qcow2 \
    --public \
    --file /tmp/cirros.img \
    cirros
fi

echo "===> Création des flavors"
openstack flavor create --id 1 --vcpus 1 --ram 256  --disk 1 m1.tiny  2>/dev/null || true
openstack flavor create --id 2 --vcpus 1 --ram 512  --disk 5 m1.small 2>/dev/null || true

echo "===> Configuration security group 'default' (autoriser ICMP et SSH)"
ADMIN_PROJECT=$(openstack project show admin -f value -c id)
DEFAULT_SG=$(openstack security group list --project "$ADMIN_PROJECT" -f value -c ID | head -1)

openstack security group rule create --proto icmp "$DEFAULT_SG" 2>/dev/null || true
openstack security group rule create --proto tcp --dst-port 22 "$DEFAULT_SG" 2>/dev/null || true

echo "===> Création d'une clé SSH 'mykey' (optionnel)"
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi
openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey 2>/dev/null || true

echo ""
echo "================================================================"
echo " Réseau provider prêt !"
echo ""
echo " Lance une instance test :"
echo "   openstack server create --image cirros --flavor m1.tiny \\"
echo "     --network provider-net --key-name mykey test-vm"
echo ""
echo " Récupère son IP :"
echo "   openstack server list"
echo ""
echo " Puis depuis WINDOWS (PowerShell ou cmd) :"
echo "   ping 192.168.57.XXX"
echo "   ssh cirros@192.168.57.XXX   (mot de passe: gocubsgo)"
echo "================================================================"
