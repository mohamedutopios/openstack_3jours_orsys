# 🚀 Lab Kolla-Ansible Multinode

Lab pédagogique pour déployer OpenStack en multinode (vm1 + vm2) avec :
**Keystone, Glance, Nova, Neutron, Placement, Cinder (LVM), Horizon**.

## ⚡ Démarrage ultra-rapide

```powershell
# Windows PowerShell
.\generate-ssh.ps1
vagrant up
vagrant ssh vm1
```

Puis suis le **[GUIDE-OPENSTACK.md](./GUIDE-OPENSTACK.md)** étape par étape pour l'installation manuelle d'OpenStack.

## 📂 Contenu

| Fichier | Rôle |
|---|---|
| `Vagrantfile` | Définition des 2 VMs (réseau, disques, CPU/RAM) |
| `bootstrap.sh` | Provisionnement auto (paquets, SSH, /etc/hosts, interface provider) |
| `generate-ssh.ps1` / `.sh` | Génération des clés SSH partagées |
| `globals.yml.example` | Config Kolla prête à copier dans /etc/kolla/ |
| `multinode.example` | Inventaire Ansible Kolla |
| **`GUIDE-OPENSTACK.md`** | **Guide pas-à-pas complet (12 phases)** |

## 🎯 Architecture

- **vm1** : controller + network + compute + storage (6 Go RAM, 4 vCPU, disque Cinder 30 Go)
- **vm2** : compute (6 Go RAM, 2 vCPU)
- **Réseaux** :
  - 192.168.56.0/24 (management, accessible Windows pour Horizon)
  - 192.168.57.0/24 (provider Neutron, instances accessibles depuis Windows)

## ⚠️ Prérequis Windows

- 16 Go RAM minimum, 80 Go disque libre
- VirtualBox ≥ 7.0 + Vagrant ≥ 2.4
- VT-x activé dans le BIOS
- Hyper-V désactivé : `bcdedit /set hypervisorlaunchtype off` (admin) + reboot

## 🆘 Commandes utiles

```powershell
vagrant up                            # Démarrer
vagrant halt                          # Arrêter proprement
vagrant suspend                       # Pause rapide
vagrant ssh vm1                       # SSH vm1
vagrant snapshot save vm1 nom         # Snapshot
vagrant snapshot restore vm1 nom      # Restaurer
vagrant destroy -f                    # Tout supprimer
```

Bon TP ! 🎓
