# 📘 Guide pas-à-pas — Déploiement OpenStack Multinode avec Kolla-Ansible

> **Public** : étudiants M1/M2 — Formation cloud / DevOps
> **Durée** : 3 à 4 heures (selon la connexion Internet)
> **Stack déployée** : Keystone, Glance, Nova, Neutron, Placement, Cinder (LVM), Horizon
> **Architecture** : 2 nœuds (1 controller hyperconvergé + 1 compute)

---

## 📑 Sommaire

1. [Vue d'ensemble et architecture](#1-vue-densemble-et-architecture)
2. [Prérequis](#2-prérequis)
3. [Phase 1 — Provisionnement des VMs avec Vagrant](#3-phase-1--provisionnement-des-vms-avec-vagrant)
4. [Phase 2 — Vérifications post-démarrage](#4-phase-2--vérifications-post-démarrage)
5. [Phase 3 — Préparation du disque Cinder (LVM)](#5-phase-3--préparation-du-disque-cinder-lvm)
6. [Phase 4 — Installation de Kolla-Ansible](#6-phase-4--installation-de-kolla-ansible)
7. [Phase 5 — Configuration du déploiement](#7-phase-5--configuration-du-déploiement)
8. [Phase 6 — Tests préliminaires](#8-phase-6--tests-préliminaires)
9. [Phase 7 — Déploiement d'OpenStack](#9-phase-7--déploiement-dopenstack)
10. [Phase 8 — Validation des services](#10-phase-8--validation-des-services)
11. [Phase 9 — Initialisation OpenStack (réseau, image, flavors)](#11-phase-9--initialisation-openstack)
12. [Phase 10 — Test d'une instance de bout en bout](#12-phase-10--test-dune-instance)
13. [Phase 11 — Test Cinder (volumes persistants)](#13-phase-11--test-cinder)
14. [Phase 12 — Accès à Horizon depuis Windows](#14-phase-12--accès-à-horizon)
15. [Annexes](#15-annexes)

---

## 1. Vue d'ensemble et architecture

### 1.1 Composants OpenStack déployés

| Service | Rôle | Conteneurs principaux |
|---|---|---|
| **Keystone** | Authentification, gestion des utilisateurs et tokens | `keystone` |
| **Glance** | Catalogue d'images de VMs (Cirros, Ubuntu...) | `glance_api` |
| **Placement** | Suivi de l'inventaire des ressources (CPU/RAM/disque) | `placement_api` |
| **Nova** | Compute : gestion du cycle de vie des instances | `nova_api`, `nova_compute`, `nova_scheduler`, `nova_conductor` |
| **Neutron** | Réseau : SDN, security groups, routeurs | `neutron_server`, `neutron_openvswitch_agent`, `neutron_dhcp_agent`, `neutron_l3_agent`, `neutron_metadata_agent` |
| **Cinder** | Stockage bloc persistant | `cinder_api`, `cinder_scheduler`, `cinder_volume` |
| **Horizon** | Dashboard web | `horizon` |

### 1.2 Services techniques (sous-jacents)

| Service | Rôle |
|---|---|
| **MariaDB** | Base de données pour tous les services OpenStack |
| **RabbitMQ** | Bus de messages AMQP entre les services |
| **Memcached** | Cache (tokens Keystone, sessions) |
| **HAProxy / Keepalived** | Load-balancer et VIP haute disponibilité |
| **Open vSwitch** | Commutateur virtuel pour Neutron |

### 1.3 Topologie réseau

```
┌─────────────────────────── Windows Host ───────────────────────────┐
│                                                                    │
│   192.168.56.1 (auto)           192.168.57.1 (auto)                │
│       │                              │                             │
│       │ Réseau host-only             │ Réseau host-only            │
│       │ "Management/API"             │ "Provider/External"         │
│       │                              │                             │
│   ┌───┴────────────────┐         ┌───┴────────────────┐            │
│   │  vm1               │         │  vm1               │            │
│   │  enp0s8            │         │  enp0s9 (sans IP)  │            │
│   │  192.168.56.10     │         │                    │            │
│   │                    │         │  Instances OpenStack:           │
│   │  - Keystone        │         │  192.168.57.100-200             │
│   │  - Glance          │         │                                 │
│   │  - Nova ctrl + cpu │         └────────────────────┘            │
│   │  - Neutron server  │                                           │
│   │  - Cinder + LVM    │         ┌────────────────────┐            │
│   │  - Horizon         │         │  vm2               │            │
│   │  - MariaDB / RMQ   │         │  enp0s8            │            │
│   │  - HAProxy (VIP)   │         │  192.168.56.11     │            │
│   │  /dev/sdb (30Go)   │         │                    │            │
│   └────────────────────┘         │  - Nova compute    │            │
│                                  │  - Neutron OVS     │            │
│   VIP : 192.168.56.100           │  - iSCSI initiator │            │
│   (Horizon, APIs)                └────────────────────┘            │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 1.4 Pourquoi cette architecture ?

- **Hyperconvergence sur vm1** : on regroupe controller + network + compute + storage pour économiser la RAM. En production, ces rôles seraient séparés.
- **Deuxième compute (vm2)** : démontre le scheduling Nova multi-nœuds et la communication inter-nœuds via RabbitMQ et iSCSI (Cinder).
- **Réseau provider en host-only** : permet aux instances OpenStack d'être accessibles directement depuis Windows, sans NAT complexe.
- **Cinder LVM** : backend de stockage simple à comprendre pour de la pédagogie (un disque physique → un volume group → des LVs exposés en iSCSI).

---

## 2. Prérequis

### 2.1 Matériel

- **CPU** : au moins 4 cœurs physiques avec VT-x/AMD-V
- **RAM** : 16 Go minimum (14 Go pour les VMs, 2 Go pour Windows)
- **Disque** : 80 Go libres minimum (boxes + disques VMs + images Docker)
- **Réseau** : connexion Internet stable (les pulls d'images Docker font ~5 Go)

### 2.2 Logiciels

| Logiciel | Version | Lien |
|---|---|---|
| VirtualBox | ≥ 7.0 | https://www.virtualbox.org/wiki/Downloads |
| Vagrant | ≥ 2.4 | https://developer.hashicorp.com/vagrant/downloads |
| Git Bash ou PowerShell | - | Pour exécuter les scripts |
| OpenSSH Client | - | Présent par défaut sur Windows 10/11 |

### 2.3 Configuration Windows

**Vérifier que VT-x est activé** dans le BIOS/UEFI (souvent appelé "Intel Virtualization Technology" ou "SVM" pour AMD).

**Désactiver Hyper-V** s'il est actif (sinon VirtualBox sera très lent) :

```powershell
# PowerShell en administrateur
bcdedit /set hypervisorlaunchtype off
# Puis redémarrer Windows
```

Pour vérifier ensuite :
```powershell
bcdedit /enum {current} | findstr hypervisor
# Doit afficher : hypervisorlaunchtype  Off
```

---

## 3. Phase 1 — Provisionnement des VMs avec Vagrant

### 3.1 Récupérer le lab

Décompresse le zip dans un dossier (exemple : `C:\labs\kolla-lab`).

Tu dois avoir cette structure :

```
kolla-lab/
├── Vagrantfile
├── bootstrap.sh
├── generate-ssh.ps1
├── generate-ssh.sh
├── globals.yml.example
├── multinode.example
└── GUIDE-OPENSTACK.md  (ce fichier)
```

### 3.2 Générer les clés SSH partagées

Ouvre PowerShell dans le dossier `kolla-lab` :

```powershell
.\generate-ssh.ps1
```

**Résultat attendu** :
```
Generating public/private rsa key pair.
Your identification has been saved in ssh\id_rsa
Your public key has been saved in ssh\id_rsa.pub
==============================================
 Clés SSH générées dans : .\ssh
 Tu peux maintenant lancer : vagrant up
==============================================
```

**Pourquoi** : ces clés serviront à ce que vm1 puisse se connecter en SSH à vm2 sans mot de passe (Ansible en a besoin pour le déploiement multinode).

### 3.3 Démarrer les VMs

```powershell
vagrant up
```

**Ce qui se passe** :
1. Vagrant télécharge la box `bento/ubuntu-22.04` (~600 Mo, première fois uniquement)
2. Crée les 2 VMs dans VirtualBox avec les adaptateurs réseau configurés
3. Démarre les VMs et exécute `bootstrap.sh` sur chacune

**Durée** : 10-15 min la première fois, 3-5 min ensuite.

**Si tu vois cette erreur** : `VERR_VMX_NO_VMX` → VT-x désactivé, retour au BIOS.

**Vérification** :
```powershell
vagrant status
```
Doit afficher :
```
vm1     running (virtualbox)
vm2     running (virtualbox)
```

### 3.4 Premier snapshot recommandé

```powershell
vagrant snapshot save vm1 fresh
vagrant snapshot save vm2 fresh
```

⚠️ Si tu casses quelque chose plus tard : `vagrant snapshot restore vm1 fresh` te ramène à cet état en 30 secondes.

---

## 4. Phase 2 — Vérifications post-démarrage

### 4.1 Se connecter à vm1

```powershell
vagrant ssh vm1
```

Tu es maintenant en tant que `vagrant@vm1`.

### 4.2 Vérifier le réseau

```bash
# Doit voir 3 interfaces: enp0s3 (NAT), enp0s8 (mgmt), enp0s9 (provider, UP sans IP)
ip -br a
```

**Résultat attendu** :
```
lo               UNKNOWN   127.0.0.1/8
enp0s3           UP        10.0.2.15/24
enp0s8           UP        192.168.56.10/24
enp0s9           UP        <pas d'IP>
```

🚨 Si `enp0s9` n'est pas `UP` ou a une IP, il y a un problème de provisioning. Refaire `vagrant reload --provision`.

### 4.3 Vérifier la connectivité avec vm2

```bash
ping -c 2 vm2
ssh vm2 hostname
```

Le `ssh vm2` doit afficher `vm2` sans demander de mot de passe.

### 4.4 Vérifier le disque Cinder

```bash
lsblk
```

**Résultat attendu** :
```
NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda       8:0    0   64G  0 disk
├─sda1    8:1    0   63G  0 part /
├─sda2    8:2    0    1K  0 part
└─sda5    8:5    0  975M  0 part
sdb       8:16   0   30G  0 disk         ← le disque Cinder
```

✅ Le disque `/dev/sdb` de 30 Go est bien là, vide, prêt à être configuré pour LVM.

---

## 5. Phase 3 — Préparation du disque Cinder (LVM)

### 5.1 Comprendre le rôle de LVM dans Cinder

Cinder avec backend LVM fonctionne ainsi :
1. Un disque physique (ici `/dev/sdb`) devient un **Physical Volume** (PV)
2. Le PV est ajouté à un **Volume Group** (VG) nommé `cinder-volumes`
3. Cinder crée des **Logical Volumes** (LV) dans ce VG → un LV = un volume OpenStack
4. Cinder expose ces LVs aux compute nodes via **iSCSI**

### 5.2 Créer le Physical Volume

Toujours sur vm1, en root :

```bash
sudo pvcreate /dev/sdb
```

**Résultat attendu** :
```
Physical volume "/dev/sdb" successfully created.
```

Vérification :
```bash
sudo pvs
```
```
PV         VG  Fmt  Attr PSize  PFree
/dev/sdb       lvm2 ---  30.00g 30.00g
```

### 5.3 Créer le Volume Group

```bash
sudo vgcreate cinder-volumes /dev/sdb
```

**Résultat attendu** :
```
Volume group "cinder-volumes" successfully created
```

⚠️ Le nom **`cinder-volumes`** est important : c'est le nom par défaut attendu par Kolla. Si tu utilises un autre nom, il faudra l'override dans `globals.yml`.

Vérification :
```bash
sudo vgs
```
```
VG             #PV #LV #SN Attr   VSize   VFree
cinder-volumes   1   0   0 wz--n- <30.00g <30.00g
```

### 5.4 Filtrer les autres disques (important !)

Par défaut LVM scanne tous les disques. Sur certains setups, ça peut causer des warnings ou des conflits. On va dire à LVM de ne scanner QUE `/dev/sdb` :

```bash
sudo nano /etc/lvm/lvm.conf
```

Cherche la ligne `# filter = [ ... ]` (commentée), et en dessous ajoute :

```
filter = [ "a|/dev/sdb|", "r|.*|" ]
```

- `a|/dev/sdb|` = accepter /dev/sdb
- `r|.*|` = rejeter tout le reste

Puis reconstruis le cache :
```bash
sudo vgscan --cache
```

> 💡 **Note** : cette étape n'est pas strictement nécessaire pour que Cinder fonctionne, mais elle évite des warnings dans les logs en production.

---

## 6. Phase 4 — Installation de Kolla-Ansible

### 6.1 Créer un environnement Python isolé

Toujours sur vm1 :

```bash
cd ~
python3 -m venv kolla-venv
source kolla-venv/bin/activate
```

**Ton prompt change** : `(kolla-venv) vagrant@vm1:~$`

**Pourquoi un venv ?** Pour ne pas polluer le Python système et pouvoir supprimer/recréer facilement.

### 6.2 Mettre à jour pip

```bash
pip install -U pip
```

### 6.3 Installer Ansible

```bash
pip install 'ansible-core>=2.16,<2.17.99'
```

Vérifier :
```bash
ansible --version
# ansible [core 2.16.x]
```

### 6.4 Installer Kolla-Ansible

On utilise la branche **stable/2024.1** (Caracal) qui est stable et bien documentée :

```bash
pip install git+https://opendev.org/openstack/kolla-ansible@stable/2024.1
```

Cette commande télécharge le code depuis OpenDev et l'installe. Compte 2-3 minutes.

Vérifier :
```bash
kolla-ansible --version
# kolla-ansible 18.x.x
```

### 6.5 Préparer /etc/kolla

```bash
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla
```

### 6.6 Copier les exemples de configuration

```bash
cp -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
ls /etc/kolla/
```

**Résultat** :
```
globals.yml  passwords.yml
```

### 6.7 Installer les dépendances Ansible (collections)

Kolla utilise des collections Ansible (ansible.posix, community.general, etc.) :

```bash
kolla-ansible install-deps
```

Compte 1-2 minutes. Les collections sont installées dans `~/.ansible/collections/`.

---

## 7. Phase 5 — Configuration du déploiement

### 7.1 Configurer l'inventaire `multinode`

Copie le modèle depuis le dossier partagé :

```bash
cp /vagrant/multinode.example ~/multinode
```

> 💡 Le dossier où se trouve le Vagrantfile est automatiquement monté dans `/vagrant` sur les VMs.

Ouvre-le pour comprendre la structure :

```bash
nano ~/multinode
```

**Sections clés à comprendre** :

```ini
[control]                       # Services API + orchestration
vm1 ansible_host=192.168.56.10 ansible_user=vagrant

[network]                       # Agents Neutron (DHCP, L3, metadata)
vm1 ansible_host=192.168.56.10 ansible_user=vagrant

[compute]                       # Hyperviseurs (nova-compute, neutron-ovs-agent)
vm1 ansible_host=192.168.56.10 ansible_user=vagrant
vm2 ansible_host=192.168.56.11 ansible_user=vagrant

[storage]                       # cinder-volume (où le VG cinder-volumes existe)
vm1 ansible_host=192.168.56.10 ansible_user=vagrant
```

📝 **Question pédagogique** : pourquoi vm2 n'est-il pas dans `[storage]` ?
> Parce que vm2 n'a pas de disque Cinder. Seul vm1 a `/dev/sdb` et le VG `cinder-volumes`. vm2 sera **client** iSCSI des volumes hébergés sur vm1.

### 7.2 Configurer `globals.yml`

```bash
cp /vagrant/globals.yml.example /etc/kolla/globals.yml
```

Examine le contenu :

```bash
cat /etc/kolla/globals.yml
```

**Sections critiques à comprendre** :

**a) Versions et distribution**
```yaml
kolla_base_distro: "ubuntu"
openstack_release: "2024.1"
```

**b) Réseau** (le plus important à comprendre)
```yaml
kolla_internal_vip_address: "192.168.56.100"
```
→ Adresse IP virtuelle (VIP) portée par HAProxy/Keepalived sur vm1. Tous les APIs (Keystone, Nova, Glance...) répondent sur cette IP.

```yaml
network_interface: "enp0s8"
```
→ Interface utilisée pour la communication entre services OpenStack (RabbitMQ, MariaDB, APIs).

```yaml
neutron_external_interface: "enp0s9"
```
→ Interface "physique" mappée au réseau provider Neutron. Doit être UP sans IP.

**c) Cinder**
```yaml
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "cinder-volumes"
```
→ Active Cinder avec backend LVM, utilise le VG qu'on a créé.

**d) Nova**
```yaml
nova_compute_virt_type: "qemu"
```
→ Émulation pure (pas de KVM) car la nested virtualization VirtualBox est peu fiable.

### 7.3 Générer les mots de passe

```bash
kolla-genpwd
```

Cette commande remplit `/etc/kolla/passwords.yml` avec des mots de passe aléatoires forts pour tous les comptes (admin Keystone, MariaDB, RabbitMQ, etc.).

Récupère le mot de passe admin Keystone (tu en auras besoin pour Horizon) :

```bash
grep keystone_admin_password /etc/kolla/passwords.yml
```

Exemple :
```
keystone_admin_password: kPpZx9wXcVnB...
```

📌 **Note-le quelque part**, tu en auras besoin pour te connecter à Horizon.

---

## 8. Phase 6 — Tests préliminaires

### 8.1 Test de connectivité Ansible

```bash
ansible -i ~/multinode all -m ping
```

**Résultat attendu** :
```
vm1 | SUCCESS => { "changed": false, "ping": "pong" }
vm2 | SUCCESS => { "changed": false, "ping": "pong" }
localhost | SUCCESS => { ... }
```

🚨 Si ça échoue :
- `Permission denied` → problème de clé SSH, revoir étape 3.2
- `Could not resolve hostname` → revoir `/etc/hosts` sur vm1

### 8.2 Bootstrap des serveurs

Cette étape prépare les hôtes : installation de Docker, création de l'utilisateur `kolla`, configuration du kernel, etc.

```bash
kolla-ansible -i ~/multinode bootstrap-servers
```

**Durée** : 5-10 min.

**Ce qui est fait** :
- Installation de Docker CE sur vm1 et vm2
- Création de l'utilisateur système `kolla` (qui exécutera les conteneurs)
- Configuration de modules kernel (`br_netfilter`, etc.)
- Désactivation de `systemd-resolved` sur les ports 53

**À la fin** :
```
PLAY RECAP ************************************
vm1   : ok=XX changed=YY unreachable=0 failed=0
vm2   : ok=XX changed=YY unreachable=0 failed=0
```

### 8.3 Prechecks (ÉTAPE CRITIQUE)

```bash
kolla-ansible -i ~/multinode prechecks
```

**Durée** : 2-3 min.

Cette étape vérifie que **tout est prêt avant le déploiement** :
- VIP libre et non utilisée
- Interfaces réseau configurées correctement
- RAM/CPU/disque suffisants
- Volume Group Cinder existe
- Docker fonctionne
- Pas de conflits de ports

🚨 **Si les prechecks échouent, ne pas passer à l'étape suivante !** Corrige d'abord.

**Erreurs fréquentes** :

| Erreur | Cause | Solution |
|---|---|---|
| `The VIP is currently in use` | VIP déjà prise sur le réseau | Changer `kolla_internal_vip_address` |
| `Interface enp0s9 is not configured` | Interface provider DOWN | `sudo ip link set enp0s9 up` |
| `Free RAM not sufficient` | < 4 Go libres | Fermer des apps Windows, rebooter VM |
| `Volume group cinder-volumes not found` | VG pas créé | Refaire Phase 3 |

### 8.4 Snapshot avant déploiement (recommandé)

Avant le gros déploiement, prends un snapshot :

```bash
# Sortir de la VM
exit

# Sur Windows
vagrant snapshot save vm1 pre-deploy
vagrant snapshot save vm2 pre-deploy

# Revenir dans vm1
vagrant ssh vm1
source ~/kolla-venv/bin/activate
```

---

## 9. Phase 7 — Déploiement d'OpenStack

### 9.1 Pull des images Docker (LONG)

Avant de déployer, on télécharge toutes les images Docker (~4-5 Go) :

```bash
kolla-ansible -i ~/multinode pull
```

**Durée** : 15-30 min selon la bande passante.

**Pourquoi le faire séparément ?** Pour pouvoir relancer `deploy` plus rapidement en cas d'échec (les images sont déjà là).

📊 Vérifie pendant ce temps que tout pull bien :
```bash
# Dans un autre terminal vagrant ssh vm1
docker images | wc -l
# Doit progresser jusqu'à ~25-30 images
```

### 9.2 Déploiement principal

```bash
kolla-ansible -i ~/multinode deploy
```

**Durée** : 30-60 min.

**Ce qui se passe** (résumé) :
1. Démarrage MariaDB, RabbitMQ, Memcached, HAProxy → infra de base
2. Bootstrap Keystone → création des comptes admin, des services et endpoints
3. Démarrage Glance, Placement, Nova, Neutron, Cinder, Horizon
4. Configuration des agents (DHCP, L3, OVS, metadata, cinder-volume...)

📊 **Pour suivre en temps réel** dans un 2e terminal `vagrant ssh vm1` :
```bash
watch -n 5 'docker ps --format "table {{.Names}}\t{{.Status}}" | head -30'
```

**Résultat final attendu** :
```
PLAY RECAP ************************************
vm1   : ok=XXX changed=YYY unreachable=0 failed=0
vm2   : ok=XX changed=YY unreachable=0 failed=0
```

🚨 **Si `failed >= 1`** :
- Note le nom de la tâche en échec
- Va voir les logs : `sudo ls /var/log/kolla/<service>/`
- Cherche l'erreur dans le log du conteneur problématique
- Relance `deploy` (idempotent)

### 9.3 Post-déploiement

```bash
kolla-ansible -i ~/multinode post-deploy
```

**Durée** : < 1 min.

**Ce qui est fait** :
- Génère `/etc/kolla/admin-openrc.sh` avec les variables d'environnement pour la CLI
- Génère `/etc/kolla/clouds.yaml` pour openstacksdk

### 9.4 Installer le client OpenStack

```bash
pip install python-openstackclient
```

Charger les variables d'environnement admin :

```bash
source /etc/kolla/admin-openrc.sh
```

Désormais ton terminal a `OS_USERNAME=admin`, `OS_PASSWORD=...`, etc. configurés.

---

## 10. Phase 8 — Validation des services

### 10.1 Liste des services Keystone

```bash
openstack service list
```

**Résultat attendu** :
```
+---------+-----------+----------------+
| ID      | Name      | Type           |
+---------+-----------+----------------+
| xxx     | keystone  | identity       |
| xxx     | glance    | image          |
| xxx     | nova      | compute        |
| xxx     | neutron   | network        |
| xxx     | placement | placement      |
| xxx     | cinderv3  | volumev3       |
+---------+-----------+----------------+
```

✅ Tous les services de la stack sont enregistrés.

### 10.2 Endpoints

```bash
openstack endpoint list --service keystone
```

Doit afficher 3 endpoints (admin, internal, public) pour chaque service, tous sur `192.168.56.100`.

### 10.3 Compute services (Nova)

```bash
openstack compute service list
```

**Résultat attendu** :
```
+----+----------------+------+----------+---------+
| ID | Binary         | Host | Status   | State   |
+----+----------------+------+----------+---------+
| 1  | nova-scheduler | vm1  | enabled  | up      |
| 2  | nova-conductor | vm1  | enabled  | up      |
| 3  | nova-compute   | vm1  | enabled  | up      |  ← vm1 héberge des instances
| 4  | nova-compute   | vm2  | enabled  | up      |  ← vm2 aussi
+----+----------------+------+----------+---------+
```

✅ Les 2 computes sont en `up` → Nova scheduler peut placer des instances sur l'un ou l'autre.

### 10.4 Agents Neutron

```bash
openstack network agent list
```

**Résultat attendu** : doit voir DHCP agent, L3 agent, Metadata agent, Open vSwitch agent — tous `:-)` (alive).

### 10.5 Services Cinder

```bash
openstack volume service list
```

**Résultat attendu** :
```
+------------------+------------+------+---------+-------+
| Binary           | Host       | Zone | Status  | State |
+------------------+------------+------+---------+-------+
| cinder-scheduler | vm1        | nova | enabled | up    |
| cinder-volume    | vm1@lvm-1  | nova | enabled | up    |
+------------------+------------+------+---------+-------+
```

✅ Le backend LVM est reconnu.

### 10.6 Snapshot après validation

```bash
exit
vagrant snapshot save vm1 post-deploy
vagrant snapshot save vm2 post-deploy
vagrant ssh vm1
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
```

---

## 11. Phase 9 — Initialisation OpenStack

Maintenant qu'OpenStack est déployé, il faut créer les ressources de base : réseau provider, image, flavors, security groups.

### 11.1 Créer le réseau provider

```bash
openstack network create \
  --share \
  --provider-physical-network physnet1 \
  --provider-network-type flat \
  --external \
  provider-net
```

**Explication** :
- `--share` : utilisable par tous les projets
- `--provider-physical-network physnet1` : nom logique mappé à `enp0s9` (défini par Kolla)
- `--provider-network-type flat` : pas de VLAN, pas de VXLAN, juste du L2 direct
- `--external` : réseau routable vers l'extérieur (depuis le point de vue OpenStack)

### 11.2 Créer le subnet associé

```bash
openstack subnet create \
  --network provider-net \
  --subnet-range 192.168.57.0/24 \
  --allocation-pool start=192.168.57.100,end=192.168.57.200 \
  --gateway 192.168.57.1 \
  --dns-nameserver 8.8.8.8 \
  --no-dhcp \
  provider-subnet
```

**Explication** :
- `--subnet-range 192.168.57.0/24` : le subnet host-only VirtualBox
- `--allocation-pool 100-200` : Neutron donnera des IPs dans cette plage (.1 = Windows, .10/.11 = vm1/vm2)
- `--gateway 192.168.57.1` : c'est l'IP de Windows sur ce réseau (utile pour le routage)
- `--no-dhcp` : pas de DHCP Neutron (pour simplifier ; cloud-init utilisera la metadata)

⚠️ Note : `--no-dhcp` signifie que les instances **n'auront pas d'IP automatique au boot via DHCP**. Pour Cirros, on utilise le cloud-init qui récupère l'IP via le service metadata sur 169.254.169.254. Si tu préfères DHCP simple, omet `--no-dhcp`.

### 11.3 Vérifier

```bash
openstack network list
openstack subnet list
```

### 11.4 Télécharger et uploader Cirros

Cirros est une mini-distribution Linux (~20 Mo) parfaite pour tester.

```bash
wget http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img -O /tmp/cirros.img

openstack image create \
  --container-format bare \
  --disk-format qcow2 \
  --public \
  --file /tmp/cirros.img \
  cirros
```

Vérifier :
```bash
openstack image list
```

### 11.5 Créer des flavors

Les "flavors" définissent la taille des instances (CPU/RAM/disque) :

```bash
openstack flavor create --id 1 --vcpus 1 --ram 256  --disk 1 m1.tiny
openstack flavor create --id 2 --vcpus 1 --ram 512  --disk 5 m1.small
openstack flavor create --id 3 --vcpus 2 --ram 1024 --disk 10 m1.medium
```

Vérifier :
```bash
openstack flavor list
```

### 11.6 Security groups

Le security group `default` n'autorise rien par défaut. On va autoriser ICMP et SSH :

```bash
# Récupère l'ID du security group default
DEFAULT_SG=$(openstack security group list --project admin -f value -c ID | head -1)

# Autoriser le ping (ICMP)
openstack security group rule create --proto icmp $DEFAULT_SG

# Autoriser SSH (TCP 22)
openstack security group rule create --proto tcp --dst-port 22 $DEFAULT_SG
```

### 11.7 Créer une keypair

```bash
# Génère une paire de clés sur vm1 (si pas déjà fait)
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa

# Importe la clé publique dans OpenStack
openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
```

---

## 12. Phase 10 — Test d'une instance

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

### 12.2 Suivre son démarrage

```bash
watch -n 2 openstack server list
```

Statuts successifs :
- `BUILD` (création)
- `ACTIVE` (en cours d'exécution) ✅

Compte 30-60 secondes en QEMU pur.

### 12.3 Récupérer son IP

```bash
openstack server list
```

```
+----+----------+--------+-------------------------------+
| ID | Name     | Status | Networks                      |
+----+----------+--------+-------------------------------+
| xx | test-vm1 | ACTIVE | provider-net=192.168.57.105   |
+----+----------+--------+-------------------------------+
```

### 12.4 Voir sur quel compute elle tourne

```bash
openstack server show test-vm1 -c OS-EXT-SRV-ATTR:host
```

Tu verras `vm1` ou `vm2` → Nova scheduler a choisi.

### 12.5 Tester depuis Windows

Ouvre PowerShell (ou cmd) sur **Windows** :

```powershell
ping 192.168.57.105
```

✅ Doit répondre.

```powershell
ssh cirros@192.168.57.105
# Mot de passe Cirros : gocubsgo
```

🎉 Tu es maintenant connecté en SSH à une instance OpenStack depuis Windows !

### 12.6 Console depuis Horizon ou CLI

Tu peux aussi accéder à la console série :

```bash
openstack console url show test-vm1
```

Donne une URL VNC à ouvrir dans un navigateur (via Horizon).

### 12.7 Tester le scheduling multi-nœuds

Lance une deuxième instance et regarde où elle tombe :

```bash
openstack server create --image cirros --flavor m1.tiny \
  --network provider-net --key-name mykey test-vm2

openstack server list --long -c Name -c Host
```

Tu devrais voir une instance sur vm1 et une sur vm2 (le scheduler équilibre).

---

## 13. Phase 11 — Test Cinder

### 13.1 Créer un volume

```bash
openstack volume create --size 1 mon-volume
```

**Résultat attendu** :
```
+---------------------+--------------------------------------+
| Field               | Value                                |
+---------------------+--------------------------------------+
| status              | creating                             |
| size                | 1                                    |
| ...                 | ...                                  |
+---------------------+--------------------------------------+
```

Vérifie après 5 secondes :
```bash
openstack volume list
```

Doit être en statut `available`.

### 13.2 Voir le LV correspondant

Côté Linux (vm1) :
```bash
sudo lvs
```

```
LV                                              VG             Attr       LSize
volume-<uuid>                                   cinder-volumes -wi-a----- 1.00g
```

✅ Cinder a créé un Logical Volume LVM correspondant !

### 13.3 Attacher le volume à une instance

```bash
openstack server add volume test-vm1 mon-volume
```

### 13.4 Vérifier l'attachement dans l'instance

Depuis Windows :
```powershell
ssh cirros@192.168.57.105
```

Dans Cirros :
```bash
sudo fdisk -l
```

Tu devrais voir `/dev/vdb` de 1 Go : c'est ton volume Cinder !

### 13.5 Tester la persistance

```bash
# Dans cirros
sudo mkfs.ext4 /dev/vdb
sudo mount /dev/vdb /mnt
sudo sh -c "echo 'Hello OpenStack' > /mnt/test.txt"
sudo umount /mnt
exit
```

Détache le volume :
```bash
openstack server remove volume test-vm1 mon-volume
```

Lance une nouvelle instance et attache-y le volume :
```bash
openstack server create --image cirros --flavor m1.tiny \
  --network provider-net --key-name mykey test-vm3

# Attendre ACTIVE
openstack server add volume test-vm3 mon-volume
```

SSH dans test-vm3, monte le volume et vérifie :
```bash
sudo mount /dev/vdb /mnt
cat /mnt/test.txt
# -> Hello OpenStack
```

🎉 **Tu viens de prouver la persistance des volumes Cinder à travers les instances !**

### 13.6 Vérifier l'iSCSI inter-nœuds (bonus)

Si test-vm3 a été placé sur vm2, le volume (sur vm1) est exposé via iSCSI à vm2 :

```bash
# Sur vm2
sudo iscsiadm -m session
```

Doit afficher une session iSCSI vers vm1 (192.168.56.10).

---

## 14. Phase 12 — Accès à Horizon

### 14.1 Récupérer le mot de passe admin

Sur vm1 :
```bash
grep keystone_admin_password /etc/kolla/passwords.yml
```

### 14.2 Se connecter

Sur **Windows**, ouvre un navigateur :

```
http://192.168.56.100/
```

- **Domaine** : `default`
- **Utilisateur** : `admin`
- **Mot de passe** : celui récupéré ci-dessus

🎉 Tu as accès à Horizon avec toutes les ressources qu'on a créées en CLI !

### 14.3 Explorer

- **Compute → Instances** : voir test-vm1, test-vm2, test-vm3
- **Volumes → Volumes** : voir mon-volume
- **Network → Network Topology** : graphique du réseau provider
- **Identity → Users / Projects** : voir les comptes Keystone

---

## 15. Annexes

### 15.1 Commandes utiles au quotidien

```bash
# Activer l'environnement (à refaire à chaque session)
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh

# État des conteneurs
docker ps
docker ps -a | grep -v Up   # voir les conteneurs en erreur

# Logs d'un service
sudo tail -f /var/log/kolla/nova/nova-compute.log
sudo tail -f /var/log/kolla/neutron/neutron-server.log
sudo tail -f /var/log/kolla/cinder/cinder-volume.log

# Redémarrer un conteneur
docker restart nova_compute
docker restart cinder_volume

# Reconfigurer un service après modification
kolla-ansible -i ~/multinode reconfigure --tags nova
kolla-ansible -i ~/multinode reconfigure --tags neutron
kolla-ansible -i ~/multinode reconfigure --tags cinder

# Tout reconfigurer
kolla-ansible -i ~/multinode reconfigure
```

### 15.2 Ajouter des services plus tard (Swift, Heat...)

Édite `/etc/kolla/globals.yml` :

```yaml
enable_swift: "yes"   # ou enable_heat: "yes", enable_octavia: "yes", etc.
```

Puis :
```bash
# Pour Swift : nécessite des disques dédiés et un setup spécifique (rings)
# Voir la doc officielle pour Swift : plus complexe que les autres

# Pour un service simple (Heat par exemple)
kolla-ansible -i ~/multinode pull --tags heat
kolla-ansible -i ~/multinode deploy --tags heat
```

### 15.3 Détruire et recommencer

**Soft reset** (relancer Kolla sur les mêmes VMs) :
```bash
kolla-ansible -i ~/multinode destroy --yes-i-really-really-mean-it
# puis re-deploy
```

**Hard reset** (recréer les VMs) :
```powershell
# Sur Windows
vagrant destroy -f
vagrant up
```

**Restore snapshot** :
```powershell
vagrant snapshot restore vm1 post-deploy
vagrant snapshot restore vm2 post-deploy
```

### 15.4 Dépannage par symptôme

| Symptôme | Diagnostic | Solution |
|---|---|---|
| Instance reste en `BUILD` | `openstack server show <name>` → fault | Logs nova-compute |
| Instance `ACTIVE` mais pas pingeable | `--no-dhcp` sans cloud-init OK ? Security group ICMP ? | Vérifier SG + console pour voir si l'IP est assignée |
| Volume reste en `creating` | LVM problème ? | `docker logs cinder_volume` |
| Horizon 504 Gateway Timeout | HAProxy ne joint pas le backend | `docker ps` → tous up ? `docker logs horizon` |
| RabbitMQ erreurs partout | Réseau cassé après reboot | `kolla-ansible reconfigure` ou redémarrer le conteneur |
| "No valid host was found" | Pas assez de ressources / scheduler buggé | `openstack hypervisor stats show` |

### 15.5 Glossaire

| Terme | Définition |
|---|---|
| **AIO** | All-In-One : tout sur une seule machine |
| **VIP** | Virtual IP : IP flottante portée par HAProxy/Keepalived |
| **Provider network** | Réseau Neutron mappé à une interface physique réelle |
| **Flat network** | Réseau L2 sans VLAN ni tunneling |
| **Flavor** | Gabarit d'instance (CPU/RAM/disque) |
| **Keypair** | Paire de clés SSH injectée dans les instances via cloud-init |
| **Security group** | Pare-feu distribué au niveau de chaque vNIC d'instance |
| **Tenant / Project** | Espace d'isolation logique (utilisateurs, quotas, ressources) |
| **Hypervisor** | Hôte qui exécute des instances (= nova-compute) |
| **Placement** | Service qui inventorie les ressources disponibles |
| **iSCSI** | Protocole pour exposer du stockage bloc sur le réseau |
| **PV / VG / LV** | Physical / Volume / Logical Volume LVM |

---

## 🎓 Pour aller plus loin

- **Documentation officielle Kolla-Ansible** : https://docs.openstack.org/kolla-ansible/latest/
- **Documentation OpenStack** : https://docs.openstack.org/
- **Ajouter Swift** : stockage objet S3-compatible (nécessite disques dédiés)
- **Ajouter Heat** : orchestration (templates HOT)
- **Ajouter Magnum** : Kubernetes-as-a-Service sur OpenStack
- **Passer en OVN** : `neutron_plugin_agent: "ovn"` (SDN moderne)
- **Activer le TLS** : `kolla_enable_tls_internal: "yes"` + certificats

Bon courage ! 🚀
