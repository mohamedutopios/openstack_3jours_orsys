# 🚀 Lab Kolla-Ansible Multinode (Vagrant + VirtualBox sur Windows)

Lab pédagogique pour déployer OpenStack en multinode avec Kolla-Ansible.
Architecture : **vm1** (controller + network + compute) + **vm2** (compute).

## 📋 Prérequis

- **Windows 10/11** avec **16 Go RAM minimum**, 80 Go disque libre
- **VirtualBox ≥ 7.0** : https://www.virtualbox.org/wiki/Downloads
- **Vagrant ≥ 2.4** : https://developer.hashicorp.com/vagrant/downloads
- **VT-x/AMD-V activé** dans le BIOS
- **Hyper-V désactivé** (sinon VBox sera lent ou plantera) :
  ```powershell
  # En PowerShell admin
  bcdedit /set hypervisorlaunchtype off
  # Puis redémarrer Windows
  ```

## 🎯 Architecture réseau

| Réseau | Type | Subnet | Usage |
|---|---|---|---|
| eth0 | NAT (Vagrant) | auto | Internet (pulls Docker) |
| **eth1** | **Host-Only** | **192.168.56.0/24** | Management/API + Horizon (accessible Windows) |
| **eth2** | **Host-Only** | **192.168.57.0/24** | Provider Neutron — **les instances OpenStack auront des IPs ici, accessibles depuis Windows** |

IPs fixes :
- **vm1** : 192.168.56.10
- **vm2** : 192.168.56.11
- **VIP Kolla / Horizon** : 192.168.56.100
- **Windows (host)** : 192.168.56.1 et 192.168.57.1 (auto)
- **Instances OpenStack** : 192.168.57.100 → 192.168.57.200

## 🏁 Démarrage rapide

### Étape 1 : Générer les clés SSH (une fois)

**PowerShell** :
```powershell
.\generate-ssh.ps1
```

**Git Bash / WSL** :
```bash
chmod +x generate-ssh.sh && ./generate-ssh.sh
```

### Étape 2 : Démarrer les VMs

```bash
vagrant up
```

⏱️ Compter ~10-15 min la première fois (téléchargement de la box Ubuntu).

### Étape 3 : Se connecter à vm1

```bash
vagrant ssh vm1
```

### Étape 4 : Déployer OpenStack (automatique)

Depuis vm1 :

```bash
chmod +x /vagrant/deploy-kolla.sh
/vagrant/deploy-kolla.sh
```

⏱️ Compter **45-90 min** (pull des images Docker + déploiement).

💡 Le dossier du Vagrantfile est monté automatiquement dans `/vagrant` sur chaque VM.

### Étape 5 : Initialiser le réseau OpenStack

Toujours depuis vm1 :

```bash
source ~/kolla-venv/bin/activate
source /etc/kolla/admin-openrc.sh
/vagrant/init-openstack-network.sh
```

### Étape 6 : Lancer une instance et la tester depuis Windows

Depuis vm1 :
```bash
openstack server create --image cirros --flavor m1.tiny \
  --network provider-net --key-name mykey test-vm

openstack server list
# Note l'IP, par exemple 192.168.57.100
```

Depuis **Windows** (PowerShell ou cmd) :
```powershell
ping 192.168.57.100
ssh cirros@192.168.57.100
# Mot de passe : gocubsgo
```

🎉 **Tu as une instance OpenStack accessible depuis Windows !**

## 🌐 Accéder à Horizon depuis Windows

Ouvre dans ton navigateur Windows : **http://192.168.56.100/**

- **Domaine** : `default`
- **Utilisateur** : `admin`
- **Mot de passe** : récupère-le sur vm1 :
  ```bash
  grep keystone_admin_password /etc/kolla/passwords.yml
  ```

## 🛠️ Commandes Vagrant utiles

| Commande | Effet |
|---|---|
| `vagrant up` | Démarre les VMs |
| `vagrant halt` | Arrête proprement |
| `vagrant suspend` | Met en pause (rapide) |
| `vagrant resume` | Reprend après suspend |
| `vagrant ssh vm1` | SSH dans vm1 |
| `vagrant status` | État des VMs |
| `vagrant snapshot save vm1 nom` | Snapshot vm1 |
| `vagrant snapshot restore vm1 nom` | Restaure snapshot |
| `vagrant destroy -f` | Détruit tout |

## 💡 Conseils pédagogiques

### Snapshots stratégiques
**À faire absolument après chaque étape réussie** :

```bash
# Après vagrant up frais
vagrant snapshot save vm1 fresh
vagrant snapshot save vm2 fresh

# Après deploy-kolla.sh réussi
vagrant snapshot save vm1 post-deploy
vagrant snapshot save vm2 post-deploy
```

Si quelque chose casse, retour à l'état précédent en 30 secondes au lieu de tout refaire.

### Performance
- Les instances en émulation QEMU mettent **30-60 sec à booter** : c'est NORMAL.
- Si tu utilises Ubuntu Cloud au lieu de Cirros, compter **2-3 min** par boot.
- Ne lance pas plus de 2-3 instances simultanées avec 6 Go par VM.

## ❗ Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `vagrant up` échoue avec VERR_VMX_NO_VMX | VT-x désactivé | Activer dans BIOS |
| VBox lent / freeze | Hyper-V actif | `bcdedit /set hypervisorlaunchtype off` + reboot |
| Instances OpenStack pas accessibles depuis Windows | Promiscuous mode | Vérifier que adaptateur 3 = "Allow All" |
| `ansible all -m ping` échoue | Clé SSH | Refaire `generate-ssh.ps1` puis `vagrant reload --provision` |
| Disque saturé pendant `deploy` | < 30 Go libre par VM | Vérifier `df -h` sur chaque VM |
| Pull Docker très lent | Connexion | Pré-pull avec `kolla-ansible pull` en dehors des heures |

## 📂 Contenu du zip

```
kolla-lab/
├── Vagrantfile                  # Description des 2 VMs et réseaux
├── bootstrap.sh                 # Provisionnement auto (réseau, SSH, hosts)
├── generate-ssh.sh              # Génération clés SSH (Linux/Mac/WSL)
├── generate-ssh.ps1             # Génération clés SSH (Windows PowerShell)
├── globals.yml.example          # Config Kolla prête à l'emploi
├── multinode.example            # Inventaire Ansible
├── init-openstack-network.sh    # Création réseau provider + image Cirros
├── deploy-kolla.sh              # Déploiement Kolla-Ansible automatisé
└── README.md                    # Ce fichier
```

## 🎓 Pour aller plus loin

- Activer Cinder (stockage bloc) : `enable_cinder: "yes"` + ajouter un disque dédié
- Activer Heat (orchestration) : `enable_heat: "yes"`
- Tester Magnum (Kubernetes-as-a-Service) sur une infra plus costaud
- Passer à OVN au lieu d'OVS : `neutron_plugin_agent: "ovn"`

Bonne formation ! 🎉
