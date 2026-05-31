# OpenStack Kolla-Ansible Multinode sur 3 EC2 Ubuntu

Déploiement OpenStack **2024.1 Caracal** sur **3 instances EC2 Ubuntu 22.04**
avec **services collapsés** (chaque nœud = control + compute + network + storage).

**Services** : Keystone, Nova, Neutron, Cinder (LVM), Swift, Barbican, Heat, Horizon.

---

## 1. Architecture

```
                ┌────────────────────────────────────────────────────────┐
                │                  AWS VPC  10.0.0.0/16                  │
                │                                                        │
                │  Subnet "mgmt"  10.0.1.0/24    (privé, NAT vers IGW)   │
                │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
                │  │   node1      │  │   node2      │  │   node3      │  │
                │  │ ENI1: ens5   │  │ ENI1: ens5   │  │ ENI1: ens5   │  │
                │  │ 10.0.1.11    │  │ 10.0.1.12    │  │ 10.0.1.13    │  │
                │  │              │  │              │  │              │  │
                │  │ +VIP (sec.IP)│  │              │  │              │  │
                │  │ 10.0.1.10    │  │              │  │              │  │
                │  │              │  │              │  │              │  │
                │  │ ENI2: ens6   │  │ ENI2: ens6   │  │ ENI2: ens6   │  │
                │  │ src/dst=off  │  │ src/dst=off  │  │ src/dst=off  │  │
                │  └──────────────┘  └──────────────┘  └──────────────┘  │
                │                                                        │
                │  Subnet "ext" 10.0.99.0/24 (public, IGW)               │
                │   ↑ pour le réseau externe Neutron (FIP pool)          │
                └────────────────────────────────────────────────────────┘

  Rôles Kolla : control, network, compute, storage, monitoring → sur les 3 nodes
  Deployer    : node1 (Kolla-Ansible y est installé, c'est lui qui SSH vers node2/3)
```

### Pourquoi cette architecture

- **3 nodes collapsés** : avec 3 VM seulement, on co-localise tous les rôles.
  Le control plane est en HA (3 instances de chaque service API), le compute
  est réparti, et le stockage Cinder/Swift est répliqué.
- **VIP = IP secondaire sur node1** : EC2 VPC **ne supporte pas** le multicast
  ni VRRP, donc keepalived ne peut pas faire de failover automatique.
  On désactive keepalived et on attribue une IP secondaire sur l'ENI primaire
  de node1. **HAProxy reste actif** sur les 3 nodes (load-balancing API), mais
  le VIP lui-même est un SPOF en cas de perte de node1 (acceptable pour
  formation ; production = AWS NLB devant HAProxy).
- **2ᵉ ENI pour Neutron externe** : OVS a besoin d'une interface **brute** pour
  bridger le réseau externe. La 2ᵉ ENI doit avoir **source/dest check
  désactivé** sinon AWS bloque le trafic dont l'IP source ≠ IP de l'ENI.
- **QEMU pour Nova** : EC2 hors instances `*.metal` ne supporte pas la
  virtualisation imbriquée (KVM). On force `nova_compute_virt_type: qemu`
  (TCG, lent mais fonctionnel ; utilisez Cirros pour les démos).

---

## 2. Pré-requis AWS

| Ressource | Valeur recommandée |
|---|---|
| Region | au choix (ex. `eu-west-3`) |
| AMI | Ubuntu 22.04 LTS (`ami-xxx` Canonical officielle) |
| Instance type | **m5.2xlarge** (8 vCPU, 32 GB) ou t3.2xlarge |
| Key pair | une keypair SSH créée au préalable |
| Volumes EBS | par nœud : 50 GB root + 50 GB Cinder + 3×20 GB Swift |
| Security Group | tout-tout-ouvert entre les 3 nodes ; SSH (22) et HTTP/HTTPS (80/443) depuis votre IP |
| ENIs | 2 par nœud (mgmt + ext) |

**Coût estimatif (eu-west-3, on-demand)** : 3 × m5.2xlarge ≈ 1.4 €/h, plus EBS ≈ 0.10 €/h
→ ~1.5 €/h. **Stoppez les instances entre les sessions** pour ne payer que les EBS.

---

## 3. Vue d'ensemble des étapes

| # | Quoi | Où | Script |
|---|---|---|---|
| 1 | Créer VPC + subnets + SG + ENIs | poste local (aws CLI) | `aws/01-create-vpc.sh` etc. |
| 2 | Lancer 3 EC2 + attacher volumes | poste local | `aws/03-launch-instances.sh` |
| 3 | Désactiver source/dest check ENI ext | poste local | `aws/05-attach-external-eni.sh` |
| 4 | Assigner VIP comme IP secondaire | poste local | `aws/06-assign-vip.sh` |
| 5 | Préparer chaque nœud (apt, time, hosts) | sur chaque nœud | `ansible/prep-hosts.yml` |
| 6 | Préparer disques Cinder + Swift | sur chaque nœud | `scripts/10-...`, `scripts/11-...` |
| 7 | Installer Kolla-Ansible sur node1 | node1 (deployer) | `scripts/00-deployer-install-kolla.sh` |
| 8 | Mettre en place inventaire + globals | node1 | manuel (`kolla/multinode`, `kolla/globals.yml`) |
| 9 | Générer mots de passe + rings Swift | node1 | `scripts/01-...`, `scripts/20-...` |
| 10 | bootstrap-servers + prechecks + deploy | node1 | `scripts/30-...`, `31-...`, `32-...` |
| 11 | post-deploy + tests | node1 | `scripts/33-...`, `40-...` |

---

## 4. Étape par étape

### 4.1 Provisionnement AWS

#### Option A — scripts (depuis votre poste local avec `aws` CLI configuré)

```bash
cd aws/
cp 00-vars.sh.example 00-vars.sh
$EDITOR 00-vars.sh        # adapter region, AMI ID, keypair
source 00-vars.sh

bash 01-create-vpc.sh             # crée VPC, 2 subnets, IGW, route tables
bash 02-create-security-group.sh  # SG ouvert intra + SSH/HTTP depuis votre IP
bash 03-launch-instances.sh       # lance 3 instances + EBS + tags
bash 05-attach-external-eni.sh    # crée et attache l'ENI #2 sur subnet ext, src/dst=off
bash 06-assign-vip.sh             # ajoute 10.0.1.10 en IP secondaire sur node1 ENI1
```

Chaque script écrit ses IDs dans `aws/state.env` (lu par le suivant).

#### Option B — console AWS

Suivre [docs/aws-console-howto.md](docs/aws-console-howto.md) (étapes équivalentes en clics).

À la fin, vous avez 3 IPs publiques (Elastic IPs) et vous pouvez SSH :
```bash
ssh -i ~/.ssh/votre-key.pem ubuntu@<eip-node1>
```

### 4.2 Préparation système des 3 nodes

Depuis **node1**, en tant qu'utilisateur `ubuntu` :

```bash
# Copier votre clé SSH privée sur node1 pour qu'il puisse joindre node2/3
scp -i ~/.ssh/votre-key.pem ~/.ssh/votre-key.pem ubuntu@<eip-node1>:~/.ssh/id_rsa
ssh -i ~/.ssh/votre-key.pem ubuntu@<eip-node1>

# Sur node1 :
chmod 600 ~/.ssh/id_rsa

# Cloner / copier ce kit sur node1
# (depuis votre poste : scp -r kolla-multinode-ec2/ ubuntu@<eip-node1>:~/)
cd ~/kolla-multinode-ec2

# Adapter ansible/prep-inventory.ini avec les IPs privées des 3 nodes
$EDITOR ansible/prep-inventory.ini

# Tester la connectivité
ansible -i ansible/prep-inventory.ini all -m ping

# Lancer la préparation : apt, chrony, /etc/hosts, sysctl
ansible-playbook -i ansible/prep-inventory.ini ansible/prep-hosts.yml
```

Ce playbook fait sur **chaque nœud** :
- `apt update && upgrade`
- installe `git python3-venv chrony xfsprogs lvm2`
- définit le timezone Europe/Paris
- pose `/etc/hosts` avec node1/node2/node3 (utile pour Kolla)
- désactive UFW
- charge les modules kernel (`br_netfilter`, `nf_conntrack`)

### 4.3 Préparation des disques (Cinder + Swift)

Sur **chaque nœud**, exécuter :

```bash
sudo bash scripts/10-each-node-cinder-vg.sh /dev/nvme1n1
sudo bash scripts/11-each-node-swift-disks.sh /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1
```

Adapter les noms de devices : sur EC2 Nitro, les EBS apparaissent en
`/dev/nvme[1..N]n1` dans l'ordre d'attachement. Vérifier avec `lsblk`.

Pour la persistance des montages Swift au reboot, le script ajoute des
entrées `/etc/fstab` via UUID.

### 4.4 Installation Kolla-Ansible sur node1 (deployer)

```bash
cd ~/kolla-multinode-ec2
bash scripts/00-deployer-install-kolla.sh
source ~/kolla-venv/bin/activate
```

### 4.5 Configuration Kolla

Copier les fichiers fournis vers `/etc/kolla` :

```bash
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla
cp -r ~/kolla-venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
cp kolla/globals.yml /etc/kolla/globals.yml
cp kolla/multinode .                    # à la racine du dossier de travail

# Adapter dans /etc/kolla/globals.yml :
#   - kolla_internal_vip_address (10.0.1.10 par défaut)
#   - network_interface (ens5 par défaut sur Nitro)
#   - neutron_external_interface (ens6 par défaut)

# Adapter dans ./multinode :
#   - les IPs privées des 3 nodes
$EDITOR /etc/kolla/globals.yml ./multinode
```

Générer les mots de passe :
```bash
bash scripts/01-deployer-genpwd.sh
grep keystone_admin_password /etc/kolla/passwords.yml
```

### 4.6 Rings Swift

Les rings doivent référencer les **IPs storage** des 3 nodes (= IP mgmt en
collapsed) :

```bash
NODE_IPS="10.0.1.11 10.0.1.12 10.0.1.13" bash scripts/20-deployer-build-swift-rings.sh
```

Le script tire l'image `quay.io/openstack.kolla/swift-base:2024.1-ubuntu-jammy`
et écrit les `.builder` / `.ring.gz` dans `/etc/kolla/config/swift/`.

### 4.7 Bootstrap, prechecks, deploy

```bash
bash scripts/30-deployer-bootstrap.sh    # installe docker sur les 3 nodes
bash scripts/31-deployer-prechecks.sh    # vérifie tout
bash scripts/32-deployer-deploy.sh       # 30-60 min selon réseau
bash scripts/33-deployer-post-deploy.sh  # génère admin-openrc.sh
```

### 4.8 Tests

```bash
source /etc/kolla/admin-openrc.sh
bash scripts/40-deployer-test.sh
```

Doit montrer Keystone/Nova/Neutron/Cinder/Swift/Heat/Barbican tous up.

Horizon : `http://<EIP-node1>/`  (le VIP 10.0.1.10 n'est pas joignable depuis
internet ; on passe par l'EIP de node1 qui héberge le VIP secondaire).

---

## 5. Spécificités EC2 — checklist des pièges

| Piège | Symptôme | Solution |
|---|---|---|
| Source/dest check ENI ext | floating IP injoignable, paquets droppés par AWS | `aws ec2 modify-network-interface-attribute --no-source-dest-check` (script `05-`) |
| Multicast/VRRP non supporté | keepalived flap, deux nodes croient être MASTER | `enable_keepalived: "no"` + IP secondaire manuelle |
| Pas de KVM | `nova-compute` log : `KVM not available` | `nova_compute_virt_type: "qemu"` |
| MTU VXLAN | paquets droppés > 1450 octets | `neutron_global_physnet_mtu: 1450` (déjà dans globals.yml fourni) |
| Security Group trop restrictif | prechecks échouent (rabbitmq, mariadb) | SG : tout autoriser **entre** les 3 nodes (intra-SG) |
| EBS rebrandés au reboot | montages Swift perdus | utiliser **UUID** dans /etc/fstab (le script le fait) |
| IP secondaire perdue au stop/start | VIP disparaît | la ré-attacher avec `aws ec2 assign-private-ip-addresses` (script `06-`) |

---

## 6. Reset / re-deploy

```bash
source ~/kolla-venv/bin/activate
kolla-ansible -i ./multinode destroy --yes-i-really-really-mean-it
# Puis re-lancer scripts/30 → 33
```

---

## 7. Aller plus loin

- **HA réelle de la VIP** : remplacer l'IP secondaire par un AWS NLB
  pointant sur les 3 nodes ; mettre `kolla_internal_vip_address` à l'IP
  privée du NLB.
- **Floating IPs joignables depuis internet** : allouer chaque FIP comme
  IP secondaire de l'ENI ext correspondante (manuel ou via un script
  d'intégration Neutron-EC2 — non fourni ici).
- **Compute dédié** : ajouter des nodes au groupe `[compute]` uniquement
  dans `multinode`, lancer un `kolla-ansible deploy` ; les nouveaux nodes
  seront ajoutés sans toucher au control plane.

---

## 8. Index des fichiers

```
kolla-multinode-ec2/
├── README.md                                ← ce document
├── docs/
│   ├── aws-console-howto.md                 ← équivalent console des scripts AWS
│   └── network-diagram.md                   ← détail réseau / SG
├── aws/
│   ├── 00-vars.sh.example                   ← variables (à copier vers 00-vars.sh)
│   ├── 01-create-vpc.sh
│   ├── 02-create-security-group.sh
│   ├── 03-launch-instances.sh
│   ├── 04-attach-volumes.sh                 ← (intégré au 03 par défaut)
│   ├── 05-attach-external-eni.sh
│   ├── 06-assign-vip.sh
│   └── userdata-cloudinit.yaml              ← cloud-init basique
├── ansible/
│   ├── ansible.cfg
│   ├── prep-inventory.ini
│   └── prep-hosts.yml
├── kolla/
│   ├── globals.yml                          ← conf Kolla multinode
│   └── multinode                            ← inventaire (3 nodes, tous rôles)
├── scripts/
│   ├── 00-deployer-install-kolla.sh
│   ├── 01-deployer-genpwd.sh
│   ├── 10-each-node-cinder-vg.sh
│   ├── 11-each-node-swift-disks.sh
│   ├── 20-deployer-build-swift-rings.sh
│   ├── 30-deployer-bootstrap.sh
│   ├── 31-deployer-prechecks.sh
│   ├── 32-deployer-deploy.sh
│   ├── 33-deployer-post-deploy.sh
│   └── 40-deployer-test.sh
└── systemd/
    └── (fstab par UUID utilisé à la place d'un .service)
```
