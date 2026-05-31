# Provisionnement AWS via la console (équivalent des scripts `aws/`)

## 1. VPC

- VPC → Create VPC
  - Name : `kolla-vpc`
  - IPv4 CIDR : `10.0.0.0/16`
- VPC → Internet Gateways → Create + Attach to VPC
- VPC → Subnets → Create subnet (× 2)
  - `kolla-subnet-mgmt` : 10.0.1.0/24, AZ a, **Auto-assign public IP : Enable**
  - `kolla-subnet-ext`  : 10.0.99.0/24, AZ a (idem)
- VPC → Route Tables → Create RT `kolla-rt-public`
  - Route : `0.0.0.0/0 → IGW`
  - Subnet associations : les **deux** subnets

## 2. Security Groups

- **kolla-sg-intra** (VPC `kolla-vpc`)
  - Inbound : `All traffic` source = ce SG (self-reference)
- **kolla-sg-admin**
  - Inbound : `TCP 22, 80, 443, 9999, 6080` source = `<votre IP>/32`

## 3. Key Pair

EC2 → Key Pairs → Create `formation-openstack` (RSA, .pem) → télécharger.

## 4. Instances

EC2 → Launch instances (× 3, ou 1 puis "launch more like this") :
- Name : `node1`, `node2`, `node3`
- AMI : Ubuntu Server 22.04 LTS (HVM) (Canonical)
- Type : `m5.2xlarge`
- Key pair : `formation-openstack`
- Network :
  - VPC `kolla-vpc`, Subnet `kolla-subnet-mgmt`
  - **Primary IP private** : 10.0.1.11 / .12 / .13 (manuel par instance)
  - Auto-assign public IP : Enable
  - Firewall : sélectionner `kolla-sg-intra` **et** `kolla-sg-admin`
- Storage :
  - Volume 1 (root) : 50 GiB gp3
  - + Add volume : 50 GiB gp3 (Cinder)
  - + Add volume : 20 GiB gp3 (Swift d0)
  - + Add volume : 20 GiB gp3 (Swift d1)
  - + Add volume : 20 GiB gp3 (Swift d2)
- Advanced → User data : coller le contenu de `aws/userdata-cloudinit.yaml`

## 5. ENI externe (× 3)

EC2 → Network Interfaces → Create network interface :
- Description : `kolla-ext-node1`
- Subnet : `kolla-subnet-ext`
- Security group : `kolla-sg-intra`
- Créer, puis **Actions → Change source/dest. check → Disable** ⚠️
- Actions → Attach : à node1, device-index 1
- Répéter pour node2, node3.

## 6. VIP (IP secondaire sur node1)

EC2 → Network Interfaces → sélectionner l'ENI primaire de node1 (celle dans
`kolla-subnet-mgmt`) → Actions → Manage IP addresses → Assign new IP `10.0.1.10`.

## 7. Connexion

```bash
chmod 600 ~/Downloads/formation-openstack.pem
ssh -i ~/Downloads/formation-openstack.pem ubuntu@<EIP-node1>
```
