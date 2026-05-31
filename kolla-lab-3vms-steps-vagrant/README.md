# 🚀 Lab Kolla-Ansible Multinode (3 VMs, rôles séparés)

Lab pédagogique pour déployer OpenStack en multinode avec **séparation des rôles** :
- **vm1** = controller (8 Go) : APIs, DB, MQ, HAProxy, Horizon
- **vm2** = compute (6 Go) : hyperviseur Nova
- **vm3** = network + storage (4 Go) : agents Neutron + Cinder LVM

Stack déployée : **Keystone, Glance, Nova, Neutron, Placement, Cinder (LVM), Horizon**.

## ⚡ Démarrage rapide

```powershell
# Windows PowerShell
.\generate-ssh.ps1
vagrant up
vagrant ssh vm1
```

Puis suivre **[GUIDE-OPENSTACK.md](./GUIDE-OPENSTACK.md)** étape par étape (12 phases).

## 📂 Contenu

| Fichier | Rôle |
|---|---|
| `Vagrantfile` | Définition des 3 VMs (réseau, disques, CPU/RAM) |
| `bootstrap.sh` | Provisionnement auto |
| `generate-ssh.ps1` / `.sh` | Clés SSH partagées |
| `globals.yml.example` | Config Kolla |
| `multinode.example` | Inventaire Ansible 3 VMs |
| `GUIDE-OPENSTACK.md` | Guide pas-à-pas complet |

## ⚠️ Prérequis Windows

- **20 Go RAM recommandé** (18 Go pour les VMs, 2 Go Windows)
- 100 Go disque libre
- VirtualBox ≥ 7.0 + Vagrant ≥ 2.4
- VT-x activé, Hyper-V désactivé

## 🎯 Différences avec l'archi 2 VMs

| Aspect | 2 VMs | **3 VMs (cette version)** |
|---|---|---|
| vm1 | controller + network + compute + storage | controller pur |
| vm2 | compute | compute pur |
| vm3 | - | network + storage |
| Réalisme | Lab basique | **Reproduit une vraie archi prod** |
| Démonstration iSCSI | Sur la même VM | **Inter-nœuds entre vm2 et vm3** |
| Test scheduling | 2 hyperviseurs | 1 hyperviseur (extension vm4 prévue) |

## 🔧 Ajouter une vm4 compute

Voir **Annexe 15.1** du guide. En résumé : éditer Vagrantfile + multinode, `vagrant up vm4`, `kolla-ansible deploy`.

## 🆘 Commandes Vagrant

```powershell
vagrant up                            # Démarrer
vagrant up vm2                        # Démarrer uniquement vm2
vagrant halt                          # Arrêter
vagrant ssh vm1                       # SSH vers vm1
vagrant snapshot save vm1 nom         # Snapshot
vagrant snapshot restore vm1 nom      # Restaurer
vagrant destroy -f                    # Tout supprimer
```

Bon TP ! 🎓
