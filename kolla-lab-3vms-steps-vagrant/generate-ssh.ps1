$ErrorActionPreference = "Stop"
$sshDir = Join-Path $PSScriptRoot "ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir | Out-Null
}
$keyPath = Join-Path $sshDir "id_rsa"
if (Test-Path $keyPath) {
    Write-Host "Les clés existent déjà. Régénération..."
    Remove-Item "$keyPath*" -Force
}
ssh-keygen -t rsa -b 4096 -f $keyPath -N '""' -C "kolla-lab"
Write-Host ""
Write-Host "=============================================="
Write-Host " Clés SSH générées dans : $sshDir"
Write-Host " Tu peux maintenant lancer : vagrant up"
Write-Host "=============================================="
