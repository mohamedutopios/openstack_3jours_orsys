#!/usr/bin/env bash
# Préparation système Ubuntu 22.04 pour Kolla-Ansible
set -euo pipefail

sudo apt update
sudo apt upgrade -y
sudo apt install -y \
    git \
    python3-dev \
    python3-venv \
    python3-pip \
    libffi-dev \
    libssl-dev \
    gcc \
    chrony

sudo timedatectl set-timezone Europe/Paris
sudo systemctl enable --now chrony

# UFW désactivé (Kolla gère ses règles via Docker/iptables)
sudo systemctl disable --now ufw 2>/dev/null || true

echo "[OK] Hôte préparé. Vérifiez l'heure :"
timedatectl status | grep -E 'Time zone|System clock synchronized'

echo "[OK] Vérifiez vos interfaces :"
ip -br a
