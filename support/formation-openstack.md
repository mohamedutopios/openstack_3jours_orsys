# Conception d'un Cloud OpenStack

## 1. Conception d'un Cloud OpenStack

- Apports et spécificités d'un Cloud. Type de Clouds : SaaS, PaaS, IaaS, publics, privés.
- Le projet OpenStack. Organisation et structure.
- Architecture de la plateforme. Vue d'ensemble des différentes briques.
- Méthodes d'installation.

**Travaux pratiques**
Comparaison et sélection d'une méthode d'installation et installation.

---

## 2. Gestion des machines virtuelles

- Présentation de la brique Nova. Mise en œuvre et configuration.
- Gestion des images et des instances. Gestion du réseau virtuel.
- Gestion d'hyperviseurs multiples (Hyper-V, ESXi, KVM).

**Travaux pratiques**
Création d'une machine virtuelle depuis Nova.

---

## 3. Gestion du stockage

- Vue d'ensemble de Swift.
- Mise en œuvre et configuration.
- Gestion des pools de stockage.
- Mise en œuvre du stockage en mode bloc avec Cinder.
- Backend supportés par Cinder.

**Travaux pratiques**
Gestion du stockage avec Cinder.

---

## 4. Gestion des images

- Qu'est-ce qu'une image ?
- La brique de gestion des images Glance.
- Création de la base de données. Mise en œuvre et configuration.
- Gestion du stockage des images. La gestion des images EC2 (AMI).

**Travaux pratiques**
Créer et configurer des images.

---

## 5. Gestion du réseau

- Vue d'ensemble de la brique Neutron (anciennement Quantum).
- Switchs virtuels avec Open vSwitch.
- Topologies de réseau Cloud.
- Daemon de routage (L3).
- Mise en œuvre et configuration.

**Travaux pratiques**
Créer et configurer un réseau virtuel.

---

## 6. Authentification et autorisations

- Présentation de la brique Keystone.
- Création des utilisateurs, projets et rôles.
- Mise en œuvre et configuration.
- Configuration des utilisateurs, projets et rôles.

**Travaux pratiques**
Gestion des utilisateurs et des services.

---

## 7. Administration du Cloud

- Vue d'ensemble du client Web Horizon.
- Automatisation avec l'API REST.
- Présentation des API Amazon EC2 et S3.
- Automatisation du Cloud avec un outil d'automatisation et d'orchestration comme Cloud-init.

**Travaux pratiques**
Administration d'OpenStack depuis Horizon. Utilisation de Cloud-init ou d'un autre outil d'automatisation et d'orchestration.
