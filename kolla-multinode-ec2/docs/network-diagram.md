# Détails réseau

## Mappage interfaces / rôles Kolla

| Variable Kolla | Interface | Rôle |
|---|---|---|
| `network_interface` | ens5 (ENI #1) | mgmt, API, mariadb, rabbitmq |
| `api_interface` | ens5 | endpoints publiés (via VIP) |
| `storage_interface` | ens5 | trafic Cinder iSCSI / Swift |
| `tunnel_interface` | ens5 | VXLAN tenant networks |
| `cluster_interface` | ens5 | (idem) |
| `neutron_external_interface` | ens6 (ENI #2) | bridge L2 vers réseau externe |

Tout est concentré sur ens5 sauf le bridge externe : c'est le mode "collapsed",
acceptable en lab. En production on dédie ≥3 interfaces (mgmt / storage / tunnel).

## VIP `10.0.1.10`

- Configurée comme IP secondaire AWS sur l'ENI #1 de node1 (script `aws/06-`)
- Configurée comme adresse IP supplémentaire sur ens5 de node1 via netplan
  (playbook `prep-hosts.yml`, var `vip_holder=true`)
- HAProxy bind sur `10.0.1.10:<port>` sur les 3 nodes ; seul node1 reçoit
  effectivement le trafic (l'IP n'existe sur l'ENI que là).
- Failover : manuel (réassigner l'IP secondaire à un autre ENI).

## Trafic OpenStack

- API (Keystone, Nova, Neutron, …) : clients → VIP → HAProxy → backend sur le node.
- Tenant networks (VXLAN) : encapsulation sur ens5 (port UDP 4789). MTU 1450
  pour rester sous le MTU EC2 1500 (50 octets d'overhead VXLAN+VLAN).
- Volumes Cinder : iSCSI sur ens5 entre cinder-volume et nova-compute.
- Swift : trafic proxy ↔ object servers sur ens5, ports 6200/6201/6202.

## Pourquoi désactiver source/dest check sur ENI #2

Quand Neutron router fait du SNAT/DNAT pour les floating IPs, les paquets
sortants ont une IP source qui n'est pas l'IP "officielle" de l'ENI. AWS, par
défaut, drope ces paquets ("EC2 instance receiving/sending traffic that's not
its own"). Désactiver la vérification autorise l'ENI à se comporter comme un
bridge L2.
