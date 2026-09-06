$ErrorActionPreference = "Continue"

$Desktop = [Environment]::GetFolderPath("Desktop")
$Startup = [Environment]::GetFolderPath("Startup")

if (-not $Desktop) {
  $Desktop = Join-Path $env:USERPROFILE "Desktop"
}

if (-not $Startup) {
  $Startup = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
}

& (Join-Path $PSScriptRoot "stop-local-api.ps1")

Remove-Item (Join-Path $Desktop "Financeiro Pro.cmd") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Desktop "Iniciar Servidor Financeiro Pro.cmd") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Desktop "Parar Servidor Financeiro Pro.cmd") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Startup "Iniciar Financeiro Pro Local.cmd") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Startup "Monitor Financeiro Pro.cmd") -Force -ErrorAction SilentlyContinue

Write-Host "Atalhos removidos. A pasta do sistema e os dados nao foram apagados."
