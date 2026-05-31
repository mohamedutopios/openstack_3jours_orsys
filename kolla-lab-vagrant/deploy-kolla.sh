#!/bin/bash
# Installation et déploiement Kolla-Ansible automatisé
# À exécuter sur vm1 en tant qu'utilisateur vagrant : ./deploy-kolla.sh
set -e

KOLLA_BRANCH="stable/2024.1"
VENV_DIR="$HOME/kolla-venv"
LAB_DIR="$HOME/kolla-lab"

echo "===> Installation des paquets système"
sudo apt-get update -qq
sudo apt-get install -y -qq python3-venv python3-dev libffi-dev gcc libssl-dev git

echo "===> Création du virtualenv Python"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install -U pip

echo "===> Installation d'Ansible et Kolla-Ansible ($KOLLA_BRANCH)"
pip install 'ansible-core>=2.16,<2.17.99'
pip install "git+https://opendev.org/openstack/kolla-ansible@$KOLLA_BRANCH"

echo "===> Préparation de /etc/kolla"
sudo mkdir -p /etc/kolla
sudo chown "$USER":"$USER" /etc/kolla
cp -r "$VENV_DIR"/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/

echo "===> Copie des fichiers de configuration du lab"
cp "$LAB_DIR/globals.yml.example" /etc/kolla/globals.yml
cp "$LAB_DIR/multinode.example" "$HOME/multinode"

echo "===> Installation des dépendances Ansible (collections)"
kolla-ansible install-deps

echo "===> Génération des mots de passe"
kolla-genpwd

echo "===> Test de connectivité Ansible"
ansible -i "$HOME/multinode" all -m ping

echo "===> Bootstrap des serveurs (5-10 min)"
kolla-ansible -i "$HOME/multinode" bootstrap-servers

echo "===> Prechecks"
kolla-ansible -i "$HOME/multinode" prechecks

echo "===> Pull des images Docker (long, 15-30 min selon bande passante)"
kolla-ansible -i "$HOME/multinode" pull

echo "===> Déploiement OpenStack (30-60 min)"
kolla-ansible -i "$HOME/multinode" deploy

echo "===> Post-déploiement (génère admin-openrc.sh)"
kolla-ansible -i "$HOME/multinode" post-deploy

echo "===> Installation du client OpenStack CLI"
pip install python-openstackclient

echo ""
echo "================================================================"
echo " Déploiement Kolla terminé !"
echo ""
echo " Activer l'environnement :"
echo "   source $VENV_DIR/bin/activate"
echo "   source /etc/kolla/admin-openrc.sh"
echo ""
echo " Vérifier les services :"
echo "   openstack service list"
echo "   openstack compute service list"
echo ""
echo " Initialiser le réseau provider :"
echo "   $LAB_DIR/init-openstack-network.sh"
echo ""
echo " Horizon (dashboard web) :"
echo "   http://192.168.56.100/"
echo "   Login : admin"
echo "   Mot de passe : voir 'grep keystone_admin_password /etc/kolla/passwords.yml'"
echo "================================================================"
