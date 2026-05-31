# Kolla-Ansible All-in-One — Kit formation

Déploiement OpenStack **2024.1 Caracal** en all-in-one, services :
**Keystone, Nova, Neutron (OVS+VXLAN), Cinder (LVM), Horizon**.

## Variables à adapter AVANT de lancer

À remplacer dans `etc-kolla/globals.yml` et `netplan/00-installer-config.yaml` :

| Variable | Valeur d'exemple | Description |
|---|---|---|
| `network_interface` | `ens3` | NIC management (avec IP) |
| `neutron_external_interface` | `ens4` | NIC pour réseau externe (sans IP, UP) |
| IP hôte | `192.168.10.50/24` | IP du serveur |
| Gateway | `192.168.10.1` | Passerelle |
| `kolla_internal_vip_address` | `192.168.10.250` | VIP **libre** sur le LAN management |

## Ordre d'exécution sur l'hôte Ubuntu 22.04

```bash
# 0) Réseau (à adapter puis appliquer)
sudo cp netplan/00-installer-config.yaml /etc/netplan/
sudo netplan apply

# 1) Préparation système
bash scripts/00-prepare-host.sh

# 2) Kolla-Ansible dans un venv
bash scripts/01-install-kolla.sh

# 3) Copier la conf et générer les mots de passe
sudo mkdir -p /etc/kolla && sudo chown $USER:$USER /etc/kolla
cp -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
cp etc-kolla/globals.yml /etc/kolla/globals.yml
source ~/kolla-venv/bin/activate
kolla-genpwd
cp ~/kolla-venv/share/kolla-ansible/ansible/inventory/all-in-one ./all-in-one

# 4) Volume group Cinder (CHOISIR UNE OPTION)
bash scripts/02-cinder-vg-loopback.sh    # lab : fichier loopback
# OU
sudo bash scripts/03-cinder-vg-disk.sh /dev/sdb   # disque réel

# 5) Bootstrap + prechecks + deploy + post-deploy
bash scripts/04-deploy.sh

# 6) Test
bash scripts/05-test.sh
```

## Accès Horizon

- URL : `http://<VIP>/`  (ex. `http://192.168.10.250/`)
- User : `admin` / Domain : `default`
- Password : `grep keystone_admin_password /etc/kolla/passwords.yml`

## Reset complet

```bash
source ~/kolla-venv/bin/activate
kolla-ansible -i ./all-in-one destroy --yes-i-really-really-mean-it
```
