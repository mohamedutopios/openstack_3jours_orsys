# Génère une paire de clés SSH partagée entre vm1 et vm2
# À exécuter une seule fois avant `vagrant up`
#
# Usage : .\generate-ssh.ps1
#
# Prérequis : OpenSSH client installé (présent par défaut sur Windows 10/11)

$ErrorActionPreference = "Stop"

$sshDir = Join-Path $PSScriptRoot "ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir | Out-Null
    Write-Host "Dossier créé : $sshDir"
}

$keyPath = Join-Path $sshDir "id_rsa"

if (Test-Path $keyPath) {
    Write-Host "Les clés existent déjà dans $sshDir. Suppression et régénération..."
    Remove-Item "$keyPath*" -Force
}

ssh-keygen -t rsa -b 4096 -f $keyPath -N '""' -C "kolla-lab"

Write-Host ""
Write-Host "=============================================="
Write-Host " Clés SSH générées dans : $sshDir"
Write-Host " Tu peux maintenant lancer : vagrant up"
Write-Host "=============================================="
