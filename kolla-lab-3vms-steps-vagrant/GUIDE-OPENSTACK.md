# 📘 Guide pas-à-pas — Déploiement OpenStack Multinode (3 VMs, rôles séparés)

> **Public** : étudiants M1/M2 — Formation cloud / DevOps
> **Durée** : 3 à 4 heures (selon la connexion Internet)
> **Stack déployée** : Keystone, Glance, Nova, Neutron, Placement, Cinder (LVM), Horizon
> **Architecture** : 3 nœuds **avec rôles séparés** (controller + compute + network/storage)

---

## 📑 Sommaire

1. [Vue d'ensemble et architecture](#1-vue-densemble-et-architecture)
2. [Prérequis](#2-prérequis)
3. [Phase 1 — Provisionnement des VMs avec Vagrant](#3-phase-1)
4. [Phase 2 — Vérifications post-démarrage](#4-phase-2)
5. [Phase 3 — Préparation du disque Cinder sur vm3 (LVM)](#5-phase-3)
6. [Phase 4 — Installation de Kolla-Ansible sur vm1](#6-phase-4)
7. [Phase 5 — Configuration du déploiement](#7-phase-5)
8. [Phase 6 — Tests préliminaires](#8-phase-6)
9. [Phase 7 — Déploiement d'OpenStack](#9-phase-7)
10. [Phase 8 — Validation des services et de la répartition](#10-phase-8)
11. [Phase 9 — Initialisation OpenStack](#11-phase-9)
12. [Phase 10 — Test d'une instance et démonstration du scheduling](#12-phase-10)
13. [Phase 11 — Test Cinder et iSCSI inter-nœuds](#13-phase-11)
14. [Phase 12 — Accès à Horizon depuis Windows](#14-phase-12)
15. [Annexes (ajout d'un compute vm4, dépannage, glossaire)](#15-annexes)

---

## 1. Vue d'ensemble et architecture

### 1.1 Pourquoi cette architecture en 3 nœuds ?

Dans une vraie infrastructure OpenStack, les **rôles sont séparés** sur des machines distinctes. Cela permet :
- D'isoler les **plans** (contrôle, calcul, données réseau, stockage)
- D'avoir des dimensionnements adaptés à chaque rôle
- De faire évoluer chaque plan indépendamment
- De localiser les pannes (un compute qui tombe ≠ tout OpenStack qui tombe)

Notre lab reproduit cette séparation à petite échelle.

### 1.2 Répartition des rôles

| VM | RAM | vCPU | Rôle Kolla | Plan |
|---|---|---|---|---|
| **vm1** | 8 Go | 4 | `control` + `monitoring` + `loadbalancer` | **Contrôle** (APIs + DB + MQ + LB) |
| **vm2** | 6 Go | 2 | `compute` | **Calcul** (hyperviseur) |
| **vm3** | 4 Go | 2 | `network` + `storage` | **Données** (réseau + stockage bloc) |

### 1.3 Services déployés par VM

**🧠 vm1 — Controller (plan de contrôle)**
| Service | Rôle |
|---|---|
| MariaDB | Base de données partagée |
| RabbitMQ | Bus de messages AMQP |
| Memcached | Cache (tokens Keystone) |
| HAProxy + Keepalived | Load-balancer + VIP `192.168.56.100` |
| Keystone | Authentification, catalogue services |
| Glance API | API catalogue d'images |
| Nova API, Scheduler, Conductor | Plan de contrôle Nova |
| Neutron Server | API réseau |
| Placement API | Inventaire ressources |
| Cinder API + Scheduler | API stockage bloc |
| Horizon | Dashboard web |

**⚡ vm2 — Compute (plan de calcul)**
| Service | Rôle |
|---|---|
| nova-compute | Exécute les instances QEMU |
| neutron-openvswitch-agent | Branche les vNICs au réseau OVS |
| iSCSI initiator | Client iSCSI pour monter les volumes Cinder de vm3 |

**🌐 vm3 — Network + Storage (plan de données)**
| Service | Rôle |
|---|---|
| neutron-dhcp-agent | DHCP pour les réseaux |
| neutron-l3-agent | Routeurs virtuels, NAT, floating IPs |
| neutron-metadata-agent | Service metadata sur 169.254.169.254 |
| neutron-openvswitch-agent | Programme les flux OVS |
| cinder-volume | Crée des LVs LVM, expose en iSCSI |
| iscsi-target (tgtd) | Cible iSCSI consommée par vm2 |

### 1.4 Topologie réseau

```
                  ┌────────── Windows Host ──────────┐
                  │  192.168.56.1     192.168.57.1   │
                  └──────┬─────────────┬─────────────┘
                         │             │
                ┌────────┴─────────────┴────────┐
                │  Mgmt 192.168.56.0/24         │
                │  Provider 192.168.57.0/24     │
                └────────┬────────────┬─────────┘
                         │            │
       ┌─────────────────┼────────────┼─────────────────┐
       │                 │            │                 │
       ▼                 ▼            ▼                 ▼
   ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐
   │   vm1        │  │   vm2        │  │   vm3            │
   │ 192.168.56.10│  │ 192.168.56.11│  │ 192.168.56.12    │
   │              │  │              │  │                  │
   │ CONTROLLER   │  │ COMPUTE      │  │ NETWORK+STORAGE  │
   │              │  │              │  │                  │
   │ - Keystone   │◄─┤ - nova-cpu   ├─►│ - Neutron agents │
   │ - Nova API   │  │ - OVS agent  │  │   (DHCP/L3/Meta) │
   │ - Neutron sv │  │              │  │ - cinder-volume  │
   │ - Cinder API │  │   (instances)│  │ - OVS agent      │
   │ - MariaDB    │  │              │  │ - iSCSI target   │
   │ - RabbitMQ   │  │              │  │                  │
   │ - HAProxy    │  │              │  │ /dev/sdb (30Go)  │
   │ - Horizon    │  │              │  │ VG cinder-vols   │
   └──────────────┘  └──────────────┘  └──────────────────┘
                          │                   │
                          └──── iSCSI ────────┘
                              (volumes)
```

### 1.5 Flux types

**Lancement d'une instance** :
1. Tu tapes `openstack server create` → Nova API (vm1, VIP `.100`)
2. Nova-scheduler (vm1) choisit vm2 (seul hyperviseur ici)
3. Nova-conductor publie un message RabbitMQ → nova-compute (vm2) le consomme
4. Nova-compute (vm2) crée la VM QEMU
5. OVS-agent (vm2) branche la vNIC ; DHCP/Metadata sont servis depuis vm3

**Attachement d'un volume Cinder à une instance vm2** :
1. Cinder API (vm1) reçoit la demande
2. Cinder-volume (vm3) crée un LV LVM dans `cinder-volumes`
3. vm3 expose ce LV en iSCSI sur `192.168.56.12`
4. vm2 (initiator iSCSI) s'y connecte, présente `/dev/vdb` à l'instance

**Accès Horizon depuis Windows** :
1. Navigateur Windows → `http://192.168.56.100/`
2. HAProxy (vm1, VIP) → Horizon (vm1) → APIs (vm1) → DB (vm1)

---

## 2. Prérequis

### 2.1 Matériel

- **CPU** : 4+ cœurs physiques avec VT-x/AMD-V
- **RAM** : **20 Go minimum recommandé** (18 Go pour les VMs + 2 Go Windows). Sur 16 Go c'est juste : ferme un maximum d'applications.
- **Disque** : 100 Go libres
- **Réseau** : Internet stable (pulls Docker ~5 Go)

### 2.2 Logiciels Windows

| Logiciel | Version |
|---|---|
| VirtualBox | ≥ 7.0 |
| Vagrant | ≥ 2.4 |
| PowerShell ou Git Bash | - |
| OpenSSH Client (intégré Windows 10/11) | - |

### 2.3 Configuration

- Activer **VT-x** dans le BIOS
- Désactiver **Hyper-V** :
  ```powershell
  # PowerShell admin
  bcdedit /set hypervisorlaunchtype off
  # Redémarrer Windows
  ```

---

## 3. Phase 1 — Provisionnement des VMs avec Vagrant <a id="3-phase-1"></a>

### 3.1 Structure du lab

Dézippe le lab dans `C:\labs\kolla-lab` (ou ailleurs). Tu dois avoir :

```
kolla-lab/
├── Vagrantfile
├── bootstrap.sh
├── generate-ssh.ps1
├── generate-ssh.sh
├── globals.yml.example
├── multinode.example
├── README.md
└── GUIDE-OPENSTACK.md  ← ce fichier
```

### 3.2 Générer les clés SSH partagées

```powershell
.\generate-ssh.ps1
```

Ces clés permettront à vm1 (où tournera Ansible) de SSH vers vm1, vm2, vm3 sans mot de passe.

### 3.3 Démarrer les 3 VMs

```powershell
vagrant up
```

⏱️ 15-20 min la première fois. Vagrant :
1. Télécharge la box Ubuntu (1 fois)
2. Crée 3 VMs dans VirtualBox
3. Configure les 3 interfaces réseau de chacune
4. Crée le disque Cinder sur vm3
5. Exécute `bootstrap.sh` sur chaque VM

### 3.4 Vérifier l'état

```powershell
vagrant status
```

```
vm1     running (virtualbox)
vm2     running (virtualbox)
vm3     running (virtualbox)
```

### 3.5 Snapshot "fresh"

```powershell
vagrant snapshot save vm1 fresh
vagrant snapshot save vm2 fresh
vagrant snapshot save vm3 fresh
```

---

## 4. Phase 2 — Vérifications post-démarrage <a id="4-phase-2"></a>

### 4.1 Se connecter à vm1

```powershell
vagrant ssh vm1
```

### 4.2 Test connectivité vers vm2 et vm3

```bash
ping -c 2 vm2
ping -c 2 vm3
ssh vm2 hostname    # doit afficher vm2 sans mot de passe
ssh vm3 hostname    # doit afficher vm3 sans mot de passe
```

### 4.3 Vérifier le réseau sur chaque VM

Sur vm1 :
```bash
ip -br a
```
Attendu :
```
enp0s3   UP   10.0.2.15/24            ← NAT (Internet)
enp0s8   UP   192.168.56.10/24        ← Management
enp0s9   UP   <pas d'IP>              ← Provider
```

Sur vm2 (depuis vm1) :
```bash
ssh vm2 ip -br a
# enp0s8 → 192.168.56.11/24
```

Sur vm3 :
```bash
ssh vm3 ip -br a
# enp0s8 → 192.168.56.12/24
```

✅ Toutes les VMs ont :
- enp0s3 (NAT, sortie Internet)
- enp0s8 (management, IP en .56.x)
- enp0s9 (provider, UP sans IP)

### 4.4 Vérifier que seule vm3 a un 2e disque

```bash
ssh vm1 lsblk | grep sdb     # vide → vm1 n'a qu'un disque
ssh vm2 lsblk | grep sdb     # vide → vm2 n'a qu'un disque
ssh vm3 lsblk | grep sdb     # doit afficher sdb 30G
```

---

## 5. Phase 3 — Préparation du disque Cinder sur vm3 (LVM) <a id="5-phase-3"></a>

🚨 **Attention : cette étape se fait sur vm3, pas sur vm1 !**

C'est ici que la séparation des rôles devient concrète : le storage backend (LVM) doit être sur la machine où s'exécutera `cinder-volume`.

### 5.1 Se connecter à vm3

Depuis vm1 (où tu es actuellement) :
```bash
ssh vm3
```

(Ou depuis Windows : `vagrant ssh vm3`)

### 5.2 Vérifier le disque

```bash
sudo lsblk
```

```
sda       8:0    0   64G  0 disk
├─sda1    8:1    0   63G  0 part /
...
sdb       8:16   0   30G  0 disk         ← celui qu'on va préparer
```

### 5.3 Créer le Physical Volume

```bash
sudo pvcreate /dev/sdb
```

```
Physical volume "/dev/sdb" successfully created.
```

### 5.4 Créer le Volume Group `cinder-volumes`

```bash
sudo vgcreate cinder-volumes /dev/sdb
```

```
Volume group "cinder-volumes" successfully created
```

Vérifier :
```bash
sudo vgs
```
```
VG             #PV #LV #SN Attr   VSize   VFree
cinder-volumes   1   0   0 wz--n- <30.00g <30.00g
```

### 5.5 (Optionnel) Filtrer les autres disques

```bash
sudo nano /etc/lvm/lvm.conf
```

Décommente et modifie la ligne `filter` :
```
filter = [ "a|/dev/sdb|", "r|.*|" ]
```

```bash
sudo vgscan --cache
```

### 5.6 Retourner sur vm1

```bash
exit    # quitter vm3, retour sur vm1
```

✅ vm3 a maintenant son VG `cinder-volumes` de 30 Go prêt pour Cinder. La suite se fait depuis vm1, qui est notre **nœud de déploiement** (c'est là qu'Ansible tournera).

---

## 6. Phase 4 — Installation de Kolla-Ansible sur vm1 <a id="6-phase-4"></a>

> 💡 vm1 cumule deux casquettes : **nœud de déploiement** (Ansible tourne ici) **et** nœud controller. Dans une vraie infra on séparerait ces deux rôles.

### 6.1 Virtualenv Python

```bash
cd ~
python3 -m venv kolla-venv
source kolla-venv/bin/activate
pip install -U pip
```

### 6.2 Installer Ansible

```bash
pip install 'ansible-core>=2.16,<2.17.99'
ansible --version
```

### 6.3 Installer Kolla-Ansible

```bash
pip install git+https://opendev.org/openstack/kolla-ansible@stable/2024.1
kolla-ansible --version
```

### 6.4 Préparer /etc/kolla

```bash
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla
cp -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
```

### 6.5 Installer les collections Ansible

```bash
kolla-ansible install-deps
```

---

## 7. Phase 5 — Configuration du déploiement <a id="7-phase-5"></a>

### 7.1 Copier l'inventaire

```bash
cp /vagrant/multinode.example ~/multinode
```

### 7.2 Lire et comprendre l'inventaire

```bash
nano ~/multinode
```

**Sections clés à comprendre** :

```ini
[control]              # APIs OpenStack, DB, MQ, LB
vm1 ansible_host=192.168.56.10 ansible_user=vagrant

[network]              # Agents Neutron (DHCP, L3, metadata, OVS)
vm3 ansible_host=192.168.56.12 ansible_user=vagrant

[compute]              # Hyperviseurs Nova
vm2 ansible_host=192.168.56.11 ansible_user=vagrant

[storage]              # cinder-volume (LVM)
vm3 ansible_host=192.168.56.12 ansible_user=vagrant
```

📝 **Question pédagogique** : pourquoi vm3 est à la fois dans `[network]` et `[storage]` ?
> Parce qu'on cumule volontairement les rôles "data plane" sur la même VM pour économiser. En production, on séparerait souvent network nodes et storage nodes.

📝 **Override important** :
```ini
[loadbalancer]
vm1 ansible_host=192.168.56.10 ansible_user=vagrant
```
Par défaut, le groupe `[loadbalancer:children]` hérite de `network` (donc serait sur vm3). On l'override pour mettre HAProxy/Keepalived sur vm1 avec le reste du plan de contrôle. La VIP `192.168.56.100` sera donc portée par vm1.

### 7.3 Copier le globals.yml

```bash
cp /vagrant/globals.yml.example /etc/kolla/globals.yml
cat /etc/kolla/globals.yml
```

Le contenu est identique à ce qu'on avait en 2 VMs : la magie est dans l'inventaire, pas dans `globals.yml`. Kolla se base sur les groupes Ansible pour savoir où déployer quoi.

### 7.4 Générer les mots de passe

```bash
kolla-genpwd
grep keystone_admin_password /etc/kolla/passwords.yml
```

📌 Note ce mot de passe pour Horizon plus tard.

---

## 8. Phase 6 — Tests préliminaires <a id="8-phase-6"></a>

### 8.1 Connectivité Ansible

```bash
ansible -i ~/multinode all -m ping
```

Attendu :
```
vm1 | SUCCESS => { "ping": "pong" }
vm2 | SUCCESS => { "ping": "pong" }
vm3 | SUCCESS => { "ping": "pong" }
localhost | SUCCESS ...
```

### 8.2 Bootstrap des serveurs

```bash
kolla-ansible -i ~/multinode bootstrap-servers
```

⏱️ 7-10 min. Cette étape :
- Installe Docker CE sur **les 3 VMs**
- Crée l'utilisateur `kolla` partout
- Configure les modules kernel (`br_netfilter`, etc.)

Vérifie après :
```bash
ssh vm2 docker --version
ssh vm3 docker --version
```

### 8.3 Prechecks

```bash
kolla-ansible -i ~/multinode prechecks
```

⏱️ 3-4 min.

**Vérifications importantes faites par les prechecks** :
- VIP `192.168.56.100` libre
- Interfaces `enp0s8` et `enp0s9` présentes sur les hôtes appropriés
- Volume group `cinder-volumes` existe sur **vm3** (le nœud `[storage]`)
- Docker fonctionne sur les 3 VMs
- Pas de conflits de ports

🚨 Si "Volume group cinder-volumes not found on vm3" → revoir Phase 3.

### 8.4 Snapshot avant deploy

```bash
exit
```

```powershell
vagrant snapshot save vm1 pre-deploy
vagrant snapshot save vm2 pre-deploy
vagrant snapshot save vm3 pre-deploy
```

```powershell
vagrant ssh vm1
source ~/kolla-venv/bin/activate
```

---

## 9. Phase 7 — Déploiement d'OpenStack <a id="9-phase-7"></a>

### 9.1 Pull des images Docker

```bash
kolla-ansible -i ~/multinode pull
```

⏱️ 20-40 min. Toutes les images sont téléchargées **sur les 3 VMs** (mais chaque VM ne télécharge que les images des services qu'elle hébergera).

**Vérifie pendant ce temps** (depuis un autre terminal `vagrant ssh vm1`) :
```bash
ssh vm1 docker images | wc -l    # ~25 images
ssh vm2 docker images | wc -l    # ~5 images (nova-compute, openvswitch-agent)
ssh vm3 docker images | wc -l    # ~10 images (cinder, neutron agents)
```

🎯 **Observation pédagogique** : vm2 a très peu d'images. Logique : c'est juste un compute. vm3 en a plus à cause des multiples agents Neutron + Cinder.

### 9.2 Déploiement

```bash
kolla-ansible -i ~/multinode deploy
```

⏱️ 40-70 min.

**Ordre d'exécution Ansible** :
1. Services techniques sur vm1 : MariaDB → RabbitMQ → Memcached → HAProxy/Keepalived
2. Keystone (bootstrap des comptes admin, services, endpoints)
3. Glance, Placement (sur vm1)
4. Nova (vm1 pour le contrôle, vm2 pour le compute)
5. Neutron (vm1 pour neutron-server, vm3 pour les agents, vm2 pour ovs-agent)
6. Cinder (vm1 pour API/scheduler, vm3 pour cinder-volume)
7. Horizon (vm1)

**Résultat attendu** :
```
PLAY RECAP ************************************
vm1   : ok=XXX changed=YYY unreachable=0 failed=0
vm2   : ok=XX  changed=YY  unreachable=0 failed=0
vm3   : ok=XX  changed=YY  unreachable=0 failed=0
localhost : ok=...
```

### 9.3 Post-déploiement

```bash
kolla-ansible -i ~/multinode post-deploy
```

### 9.4 Installer le client OpenStack

```bash
pip install python-openstackclient
source /etc/kolla/admin-openrc.sh
```

---

## 10. Phase 8 — Validation des services et de la répartition <a id="10-phase-8"></a>

### 10.1 Services Keystone

```bash
openstack service list
```

Tu dois voir : keystone, glance, nova, neutron, placement, cinderv3.

### 10.2 Répartition Nova (où tournent les services)

```bash
openstack compute service list
```

```
+----+-----------------+------+----------+---------+
| ID | Binary          | Host | Status   | State   |
+----+-----------------+------+----------+---------+
|  1 | nova-scheduler  | vm1  | enabled  | up      |  ← contrôle sur vm1
|  2 | nova-conductor  | vm1  | enabled  | up      |  ← contrôle sur vm1
|  3 | nova-compute    | vm2  | enabled  | up      |  ← hyperviseur sur vm2
+----+-----------------+------+----------+---------+
```

🎯 **Notez bien** : `nova-compute` n'est **QUE sur vm2**. Contrairement à l'archi 2 VMs précédente où vm1 cumulait controller+compute, ici c'est propre.

### 10.3 Agents Neutron

```bash
openstack network agent list
```

```
+----+-------------------+------+...+-------+--------+
| ID | Agent Type        | Host |   | Alive | State  |
+----+-------------------+------+...+-------+--------+
| .. | DHCP agent        | vm3  |   | :-)   | UP     |
| .. | L3 agent          | vm3  |   | :-)   | UP     |
| .. | Metadata agent    | vm3  |   | :-)   | UP     |
| .. | Open vSwitch agent| vm3  |   | :-)   | UP     |  ← agent OVS sur vm3
| .. | Open vSwitch agent| vm2  |   | :-)   | UP     |  ← agent OVS sur vm2 (compute)
+----+-------------------+------+...+-------+--------+
```

🎯 **Notez** : OVS-agent tourne sur vm2 ET vm3 (partout où il y a du trafic instance ou des agents L3). Mais les agents DHCP/L3/Metadata sont seulement sur vm3.

### 10.4 Services Cinder

```bash
openstack volume service list
```

```
+------------------+------------+------+---------+-------+
| Binary           | Host       | Zone | Status  | State |
+------------------+------------+------+---------+-------+
| cinder-scheduler | vm1        | nova | enabled | up    |  ← contrôle sur vm1
| cinder-volume    | vm3@lvm-1  | nova | enabled | up    |  ← volume sur vm3
+------------------+------------+------+---------+-------+
```

🎯 **Notez** : `cinder-volume` tourne **uniquement sur vm3** (où est le LVM). vm1 a juste l'API et le scheduler.

### 10.5 Vérifier les conteneurs Docker par VM

```bash
ssh vm1 docker ps --format "table {{.Names}}" | sort
# ~25 conteneurs : mariadb, rabbitmq, keystone, nova_api, neutron_server, cinder_api, horizon, haproxy, etc.

ssh vm2 docker ps --format "table {{.Names}}" | sort
# ~5 conteneurs : nova_compute, openvswitch_*, iscsid

ssh vm3 docker ps --format "table {{.Names}}" | sort
# ~10 conteneurs : neutron_dhcp_agent, neutron_l3_agent, neutron_metadata_agent, neutron_openvswitch_agent, cinder_volume, iscsid, tgtd, etc.
```

✅ La répartition est correcte !

### 10.6 Snapshot post-deploy

```bash
exit
```

```powershell
vagrant snapshot save vm1 post-deploy
vagrant snapshot save vm2 post-deploy
vagrant snapshot save vm3 post-deploy
```

```powershell
vagrant ssh vm1
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
```

---

## 11. Phase 9 — Initialisation OpenStack <a id="11-phase-9"></a>

### 11.1 Créer le réseau provider

```bash
openstack network create \
  --share \
  --provider-physical-network physnet1 \
  --provider-network-type flat \
  --external \
  provider-net
```

### 11.2 Créer le subnet

```bash
openstack subnet create \
  --network provider-net \
  --subnet-range 192.168.57.0/24 \
  --allocation-pool start=192.168.57.100,end=192.168.57.200 \
  --gateway 192.168.57.1 \
  --dns-nameserver 8.8.8.8 \
  provider-subnet
```

> 💡 Note : ici j'ai retiré `--no-dhcp` (présent dans la version 2 VMs). En archi 3 VMs avec un vrai network node, **autant utiliser le DHCP Neutron** (qui tournera sur vm3 via neutron-dhcp-agent). Les instances obtiendront automatiquement leur IP au boot.

### 11.3 Image Cirros

```bash
wget http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img -O /tmp/cirros.img

openstack image create \
  --container-format bare \
  --disk-format qcow2 \
  --public \
  --file /tmp/cirros.img \
  cirros
```

### 11.4 Flavors

```bash
openstack flavor create --id 1 --vcpus 1 --ram 256  --disk 1  m1.tiny
openstack flavor create --id 2 --vcpus 1 --ram 512  --disk 5  m1.small
openstack flavor create --id 3 --vcpus 2 --ram 1024 --disk 10 m1.medium
```

### 11.5 Security group

```bash
DEFAULT_SG=$(openstack security group list --project admin -f value -c ID | head -1)
openstack security group rule create --proto icmp $DEFAULT_SG
openstack security group rule create --proto tcp --dst-port 22 $DEFAULT_SG
```

### 11.6 Keypair

```bash
ssh-keygen -t rsa -N "" -f ~/.ssh/openstack_key
openstack keypair create --public-key ~/.ssh/openstack_key.pub mykey
```

---

## 12. Phase 10 — Test d'une instance <a id="12-phase-10"></a>

### 12.1 Lancer une instance

```bash
openstack server create \
  --image cirros \
  --flavor m1.tiny \
  --network provider-net \
  --key-name mykey \
  --security-group default \
  test-vm1
```

### 12.2 Suivre le démarrage

```bash
watch -n 2 openstack server list
```

Attendre `ACTIVE` (30-60 sec en QEMU).

### 12.3 Vérifier sur quel hyperviseur elle tourne

```bash
openstack server show test-vm1 -c OS-EXT-SRV-ATTR:host
```

Tu **devrais voir `vm2`** : c'est le seul compute donc obligatoire.

### 12.4 Vérifier l'IP

```bash
openstack server list
```

```
+----+----------+--------+-------------------------------+
| ID | Name     | Status | Networks                      |
+----+----------+--------+-------------------------------+
| .. | test-vm1 | ACTIVE | provider-net=192.168.57.105   |
+----+----------+--------+-------------------------------+
```

### 12.5 Test depuis Windows

PowerShell :
```powershell
ping 192.168.57.105
ssh cirros@192.168.57.105
# Mot de passe : gocubsgo
```

🎉 Tu es connecté en SSH depuis Windows à une instance OpenStack qui tourne sur vm2 !

### 12.6 Vérifier le chemin réseau

C'est un moment pédagogique riche :
- L'instance tourne sur **vm2**
- Son DHCP a été servi par **vm3** (neutron-dhcp-agent)
- Le trafic ICMP entre Windows et l'instance passe par : Windows → interface host-only VirtualBox → vNIC `enp0s9` de vm2 → port OVS de l'instance

Depuis vm3, regarde le DHCP namespace :
```bash
ssh vm3 sudo ip netns list
# qdhcp-<network_id>
ssh vm3 sudo ip netns exec qdhcp-XXX ip a
# tu vois l'IP DHCP de Neutron (généralement .100)
```

---

## 13. Phase 11 — Test Cinder et iSCSI inter-nœuds <a id="13-phase-11"></a>

C'est la **démonstration la plus pédagogique** de cette archi 3 VMs : un volume créé sur vm3, exporté en iSCSI, monté par une instance qui tourne sur vm2.

### 13.1 Créer un volume

```bash
openstack volume create --size 1 mon-volume
openstack volume list
```

Attendre `available`.

### 13.2 Voir le LV physique sur vm3

```bash
ssh vm3 sudo lvs
```

```
LV                                              VG             Attr       LSize
volume-<uuid>                                   cinder-volumes -wi-a----- 1.00g
```

✅ Le volume Cinder est un Logical Volume LVM sur vm3.

### 13.3 Attacher le volume à l'instance (sur vm2)

```bash
openstack server add volume test-vm1 mon-volume
```

### 13.4 **Voir l'iSCSI s'établir entre vm2 et vm3**

```bash
ssh vm2 sudo iscsiadm -m session
```

```
tcp: [1] 192.168.56.12:3260,1 iqn.2010-10.org.openstack:volume-<uuid> (non-flash)
```

🎯 **C'est le cœur de l'archi distribuée** : vm2 est connecté en iSCSI à vm3 (192.168.56.12) pour accéder au volume. Tout ça s'est fait automatiquement.

Sur vm3 :
```bash
ssh vm3 sudo tgtadm --lld iscsi --op show --mode target
# montre la cible iSCSI exportée
```

### 13.5 Tester depuis l'instance

```powershell
ssh cirros@192.168.57.105
```

Dans cirros :
```bash
sudo fdisk -l
# /dev/vdb apparaît : 1 GB

sudo mkfs.ext4 /dev/vdb
sudo mount /dev/vdb /mnt
sudo sh -c "echo 'Bonjour depuis vm2, volume sur vm3' > /mnt/test.txt"
sudo umount /mnt
exit
```

### 13.6 Tester la persistance

```bash
openstack server remove volume test-vm1 mon-volume

# Crée une 2e instance
openstack server create --image cirros --flavor m1.tiny \
  --network provider-net --key-name mykey --security-group default test-vm2

# Attendre ACTIVE
openstack server add volume test-vm2 mon-volume

# Récupère son IP
openstack server list
```

SSH dans test-vm2, monte le volume :
```bash
sudo mount /dev/vdb /mnt
cat /mnt/test.txt
# -> Bonjour depuis vm2, volume sur vm3
```

🎉 Les données ont survécu au détachement et au transfert à une autre instance. Cinder fait son boulot.

---

## 14. Phase 12 — Accès à Horizon depuis Windows <a id="14-phase-12"></a>

### 14.1 Mot de passe admin

Sur vm1 :
```bash
grep keystone_admin_password /etc/kolla/passwords.yml
```

### 14.2 Navigateur Windows

```
http://192.168.56.100/
```

- Domaine : `default`
- Utilisateur : `admin`
- Mot de passe : celui récupéré

### 14.3 Explorer

- **Compute → Instances** : voir test-vm1, test-vm2
- **Compute → Hypervisors** : voir vm2 (et ses ressources)
- **Volumes → Volumes** : voir mon-volume
- **Network → Network Topology** : graphique
- **Admin → System → System Information** : voir tous les services et où ils tournent

---

## 15. Annexes <a id="15-annexes"></a>

### 15.1 Ajouter une vm4 comme compute supplémentaire

Une des forces d'une archi multinode : ajouter un compute = quelques lignes + un redéploiement ciblé.

**Étape 1 : éditer le Vagrantfile**

Avant le `end` final, ajoute :

```ruby
  config.vm.define "vm4" do |vm4|
    vm4.vm.hostname = "vm4"
    vm4.vm.network "private_network", ip: "192.168.56.13"
    vm4.vm.network "private_network",
                   ip: "192.168.57.13",
                   auto_config: false
    vm4.vm.provider "virtualbox" do |vb|
      vb.name   = "kolla-vm4"
      vb.memory = 4096
      vb.cpus   = 2
      vb.customize ["modifyvm", :id, "--nicpromisc3", "allow-all"]
      vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
    end
  end
```

**Étape 2 : éditer `bootstrap.sh`**

Ajoute la ligne hosts pour vm4 :
```bash
192.168.56.13  vm4
```

(Et mets à jour le `sed -i '/vm1$/d; /vm2$/d; /vm3$/d; /vm4$/d' /etc/hosts`)

**Étape 3 : lancer vm4**

```powershell
vagrant up vm4
```

**Étape 4 : ajouter vm4 dans `/etc/hosts` des autres VMs**

```bash
for h in vm1 vm2 vm3; do
  ssh $h "echo '192.168.56.13 vm4' | sudo tee -a /etc/hosts"
done
```

**Étape 5 : éditer l'inventaire `~/multinode`** sur vm1

```ini
[compute]
vm2 ansible_host=192.168.56.11 ansible_user=vagrant
vm4 ansible_host=192.168.56.13 ansible_user=vagrant
```

**Étape 6 : déployer uniquement sur vm4**

```bash
kolla-ansible -i ~/multinode bootstrap-servers --limit vm4
kolla-ansible -i ~/multinode prechecks --limit vm4
kolla-ansible -i ~/multinode pull --limit vm4
kolla-ansible -i ~/multinode deploy --limit vm4
```

⚠️ Le `--limit vm4` cible uniquement vm4 pour les actions hôte. Mais Kolla a aussi besoin d'agir sur vm1 pour enregistrer le nouveau compute → en pratique, **omets `--limit`** pour le `deploy` initial du nouveau compute, ou utilise `--limit vm1,vm4`.

**Étape 7 : vérifier**

```bash
openstack compute service list
# Tu vois maintenant nova-compute sur vm2 ET vm4
```

Le scheduler Nova va automatiquement utiliser vm4 pour les prochaines instances (selon sa disponibilité).

### 15.2 Commandes utiles

```bash
# Activer l'environnement (à chaque session)
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh

# Voir les conteneurs sur une VM spécifique
ssh vm3 docker ps

# Logs d'un service
ssh vm1 sudo tail -f /var/log/kolla/keystone/keystone-apache-public-error.log
ssh vm2 sudo tail -f /var/log/kolla/nova/nova-compute.log
ssh vm3 sudo tail -f /var/log/kolla/neutron/dhcp-agent.log
ssh vm3 sudo tail -f /var/log/kolla/cinder/cinder-volume.log

# Redémarrer un conteneur
ssh vm2 docker restart nova_compute
ssh vm3 docker restart neutron_l3_agent

# Reconfigurer un service (après modif globals.yml ou /etc/kolla/config/)
kolla-ansible -i ~/multinode reconfigure --tags nova
kolla-ansible -i ~/multinode reconfigure --tags neutron
kolla-ansible -i ~/multinode reconfigure --tags cinder
```

### 15.3 Tests de résilience pédagogiques

Une fois la stack debout, demande aux étudiants ce qui se passe si :

| Scénario | Effet observé | Pourquoi |
|---|---|---|
| `vagrant halt vm2` | Instances perdues, scheduler refuse de créer de nouvelles | Seul hyperviseur HS |
| `vagrant halt vm3` | Instances continuent, plus de DHCP/Metadata, volumes inaccessibles | Network + storage node HS |
| `vagrant halt vm1` | Tout casse | Controller = SPOF |

C'est une excellente illustration de pourquoi en prod on veut **3 controllers en HA** et plusieurs computes/networks/storages.

### 15.4 Dépannage par symptôme

| Symptôme | Diagnostic | Solution |
|---|---|---|
| `prechecks` échoue sur "Volume group cinder-volumes not found" | VG pas créé sur vm3 | Refaire Phase 3 sur vm3 |
| Instance en `BUILD` longtemps puis `ERROR` | Logs nova-compute sur vm2 | `ssh vm2 sudo tail /var/log/kolla/nova/nova-compute.log` |
| Volume créé mais `error` | LVM ou tgtd HS sur vm3 | `ssh vm3 docker logs cinder_volume` |
| Instance n'a pas d'IP DHCP | DHCP agent HS sur vm3 | `ssh vm3 docker logs neutron_dhcp_agent` |
| Horizon 504 Gateway Timeout | HAProxy ne joint pas backend | `ssh vm1 docker logs haproxy` |
| iSCSI ne se connecte pas | tgtd HS ou réseau mgmt cassé | `ssh vm3 docker logs tgtd && ping de vm2 vers vm3` |

### 15.5 Glossaire

| Terme | Définition |
|---|---|
| **AIO** | All-In-One : tout sur une seule machine |
| **Multinode** | Architecture multi-machines avec rôles distribués |
| **Plan de contrôle / data plane** | Séparation entre orchestration (control) et trafic métier (data) |
| **VIP** | Virtual IP : IP flottante portée par HAProxy/Keepalived |
| **Provider network** | Réseau Neutron mappé à une interface physique réelle |
| **Flat network** | Réseau L2 sans VLAN ni tunneling |
| **Network node** | Nœud qui héberge les agents Neutron (DHCP, L3, metadata) |
| **Storage node** | Nœud qui héberge `cinder-volume` (et son backend) |
| **Compute node / Hyperviseur** | Nœud qui exécute les instances |
| **iSCSI initiator / target** | Côté client (initiator) / serveur (target) du protocole iSCSI |
| **PV / VG / LV** | Physical / Volume / Logical Volume LVM |
| **SPOF** | Single Point Of Failure : composant unique dont la panne casse tout |

### 15.6 Pour aller plus loin

- **Activer Swift** : nécessite 2-3 disques par storage node + génération des rings
- **Activer Heat** : `enable_heat: "yes"` + `kolla-ansible deploy --tags heat`
- **Octavia** : LoadBalancer-as-a-Service (nécessite réseau dédié)
- **OVN** au lieu d'OVS : `neutron_plugin_agent: "ovn"`
- **Passer en HA** : 3 controllers en cluster (`[control] vm1 vm5 vm6`)
- **Séparer monitoring** : `[monitoring] vm7` + Prometheus/Grafana

Bonne formation ! 🚀
