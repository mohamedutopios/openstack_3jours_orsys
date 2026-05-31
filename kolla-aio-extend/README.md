# Kolla-Ansible AIO — Extensions progressives

Ce kit ajoute des services à un AIO **déjà déployé** (Keystone, Nova, Neutron,
Cinder, Horizon en 2024.1 Caracal). Chaque phase est **indépendante** et **idempotente** :
on édite `/etc/kolla/globals.yml`, puis on relance `kolla-ansible deploy`.

## Principe d'ajout d'un service avec Kolla-Ansible

1. Activer le service dans `/etc/kolla/globals.yml` (`enable_<service>: "yes"`).
2. Préparer les ressources externes si nécessaire (disques Swift, réseau Octavia…).
3. Relancer le playbook : `kolla-ansible -i ./all-in-one deploy`
   - Idempotent : ne touche pas les services déjà déployés.
   - Préférer `deploy` à `reconfigure` pour la **première** activation d'un service.
   - `--tags <service>` est plus rapide mais risque de manquer une dépendance ;
     utilisez-le seulement après avoir déjà fait un `deploy` complet.
4. Tester avec le client OpenStack.

> Pré-requis pour toutes les phases : venv activé + admin-openrc chargé
> ```bash
> source ~/kolla-venv/bin/activate
> source /etc/kolla/admin-openrc.sh
> cd <dossier qui contient ./all-in-one>
> ```

---

## Phase 1 — Barbican (Key Manager)

**Pourquoi en premier** : prérequis pour le chiffrement des volumes Cinder,
les certificats Octavia, l'intégration Magnum. Activation triviale.

**À ajouter dans `/etc/kolla/globals.yml`** :
```yaml
enable_barbican: "yes"
```

**Déploiement** :
```bash
bash scripts/10-add-barbican.sh
```

**Test** :
```bash
openstack secret store --name test --payload "S3cr3t!"
openstack secret list
```

---

## Phase 2 — Heat (Orchestration)

**Pourquoi** : permet les stacks HOT (templates YAML), base pour Magnum.

**À ajouter dans `globals.yml`** :
```yaml
enable_heat: "yes"
enable_horizon_heat: "yes"
```

**Déploiement** :
```bash
bash scripts/20-add-heat.sh
```

**Test** :
```bash
openstack orchestration service list
openstack stack list
```

---

## Phase 3 — Swift (Object Storage)

Plus complexe : il faut **3 disques** (ou loopback en lab), monter, créer les
**rings** (account/container/object) **avant** le déploiement.

### 3.1 — Préparer les disques

En lab, 3 fichiers loopback étiquetés `KOLLA_SWIFT_DATA`, formatés XFS,
montés sous `/srv/node/d0..d2` :
```bash
sudo bash scripts/30-prepare-swift-disks.sh
```

Persistance au reboot :
```bash
sudo cp systemd/swift-loopback.service /etc/systemd/system/
sudo systemctl enable --now swift-loopback.service
```

### 3.2 — Construire les rings

À exécuter **après** un premier déploiement Kolla (l'image `swift-base` doit
être présente sur l'hôte) :
```bash
STORAGE_IP=192.168.10.50 bash scripts/31-build-swift-rings.sh
```
`STORAGE_IP` = IP de `network_interface` (= storage_interface en AIO).

Les fichiers `account.ring.gz`, `container.ring.gz`, `object.ring.gz` sont
écrits dans `/etc/kolla/config/swift/`.

### 3.3 — Activer Swift

**À ajouter dans `globals.yml`** :
```yaml
enable_swift: "yes"
swift_devices_match_mode: "strict"
swift_devices_name: "KOLLA_SWIFT_DATA"
```

**Déploiement** :
```bash
bash scripts/32-add-swift.sh
```

**Test** :
```bash
openstack object store account show
echo "hello swift" > /tmp/hello.txt
openstack container create demo
openstack object create demo /tmp/hello.txt
openstack object list demo
```

---

## Phase 4 (optionnelle) — Designate (DNSaaS)

**Backend** : BIND9 géré par Kolla.

**À ajouter dans `globals.yml`** :
```yaml
enable_designate: "yes"
designate_backend: "bind9"
designate_ns_record:
  - "ns1.example.org"
```

**Déploiement** :
```bash
bash scripts/40-add-designate.sh
```

**Test** :
```bash
openstack zone create --email admin@example.org example.org.
openstack zone list
```

---

## Phase 5 (optionnelle) — Octavia (LBaaS)

**Pré-requis** : Barbican actif (Phase 1).

Octavia gère des "amphoras" (VMs HAProxy) sur un réseau de management dédié.
Kolla peut tout provisionner automatiquement avec :
```yaml
enable_octavia: "yes"
octavia_auto_configure: "yes"
octavia_amp_flavor:
  name: "amphora"
  is_public: false
  vcpus: 1
  ram: 1024
  disk: 5
octavia_amp_network:
  name: lb-mgmt-net
  shared: false
  provider_network_type: vxlan
  external: false
  subnet:
    name: lb-mgmt-subnet
    cidr: "10.1.0.0/24"
    allocation_pool_start: "10.1.0.100"
    allocation_pool_end: "10.1.0.200"
    no_gateway_ip: yes
    enable_dhcp: yes
```

**Déploiement** :
```bash
bash scripts/50-add-octavia.sh
```

**Test** :
```bash
openstack loadbalancer provider list
```

> Octavia exige une image "amphora". `octavia_auto_configure: yes` essaie de
> la télécharger ; sinon construire avec `diskimage-builder` (hors périmètre
> formation).

---

## Phase 6 (optionnelle) — Magnum (Container Orchestration)

**Pré-requis** : Heat (Phase 2), Barbican (Phase 1), idéalement Octavia (Phase 5).

```yaml
enable_magnum: "yes"
enable_horizon_magnum: "yes"
```

```bash
bash scripts/60-add-magnum.sh
```

---

## Phase 7 (optionnelle) — Skyline (dashboard moderne, en parallèle d'Horizon)

```yaml
enable_skyline: "yes"
```

Accès : `http://<VIP>:9999/`

---

## Récap des commandes utiles

```bash
# Re-déployer après ajout d'un service
kolla-ansible -i ./all-in-one deploy

# Reconfigurer un service existant après modif d'un override
kolla-ansible -i ./all-in-one reconfigure --tags <service>

# Voir les conteneurs en cours
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'

# Logs d'un service
sudo docker logs barbican_api --tail 100
```

## Pièges fréquents

- **Swift rings absents** au moment du `deploy` → conteneurs swift en boucle
  d'erreurs. Toujours générer les rings AVANT.
- **Octavia sans Barbican** → échec au prechecks. Activer Barbican d'abord.
- **Heat / Magnum sans `enable_horizon_<svc>`** → fonctionnel en CLI mais
  invisible dans Horizon.
- **Désactiver un service** : passer à `"no"` dans globals.yml ne supprime pas
  les conteneurs. Utiliser `kolla-ansible destroy` ou `docker rm` ciblé.
