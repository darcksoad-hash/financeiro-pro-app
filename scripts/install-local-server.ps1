$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $ProjectRoot ".env.vercel.local"
$Desktop = [Environment]::GetFolderPath("Desktop")
$Startup = [Environment]::GetFolderPath("Startup")

if (-not $Desktop) {
  $Desktop = Join-Path $env:USERPROFILE "Desktop"
}

if (-not $Startup) {
  $Startup = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
}

function Write-CmdFile([string]$Path, [string]$ScriptPath) {
  Set-Content -Path $Path -Encoding ASCII -Value @(
    "@echo off",
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$ScriptPath"""
  )
}

function Assert-Command([string]$CommandName, [string]$FriendlyName) {
  if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
    throw "$FriendlyName nao encontrado. Instale o Node.js LTS antes de continuar."
  }
}

Write-Host "Instalando Financeiro Pro local..."
Write-Host "Pasta: $ProjectRoot"

Assert-Command "node.exe" "Node.js"
Assert-Command "npm.cmd" "npm"

if (-not (Test-Path $EnvFile)) {
  $ExampleFile = Join-Path $ProjectRoot ".env.example"
  if (Test-Path $ExampleFile) {
    Copy-Item $ExampleFile $EnvFile -Force
  }
  throw "Arquivo .env.vercel.local nao encontrado. Preencha DATABASE_URL, JWT_SECRET, ADMIN_USER e ADMIN_PASSWORD nesse arquivo e rode o instalador novamente."
}

Set-Location $ProjectRoot
if (-not (Test-Path (Join-Path $ProjectRoot "node_modules"))) {
  npm.cmd install
}

New-Item -ItemType Directory -Path $Desktop -Force | Out-Null
New-Item -ItemType Directory -Path $Startup -Force | Out-Null

$openScript = Join-Path $PSScriptRoot "open-local-app.ps1"
$startScript = Join-Path $PSScriptRoot "start-local-api.ps1"
$stopScript = Join-Path $PSScriptRoot "stop-local-api.ps1"
$monitorScript = Join-Path $PSScriptRoot "monitor-financeiro.ps1"

Write-CmdFile (Join-Path $Desktop "Financeiro Pro.cmd") $openScript
Write-CmdFile (Join-Path $Desktop "Iniciar Servidor Financeiro Pro.cmd") $startScript
Write-CmdFile (Join-Path $Desktop "Parar Servidor Financeiro Pro.cmd") $stopScript
Write-CmdFile (Join-Path $Startup "Iniciar Financeiro Pro Local.cmd") $startScript

if (Test-Path $monitorScript) {
  Write-CmdFile (Join-Path $Startup "Monitor Financeiro Pro.cmd") $monitorScript
}

Start-Process -FilePath "powershell.exe" `
  -ArgumentList @("-WindowStyle", "Hidden", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $startScript) `
  -WindowStyle Hidden

Start-Sleep -Seconds 6

try {
  $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:3032/" -TimeoutSec 10
  if ($response.StatusCode -ne 200) {
    throw "Resposta inesperada: $($response.StatusCode)"
  }
  Write-Host "Instalacao concluida."
  Write-Host "Abra pelo atalho Financeiro Pro na Area de Trabalho ou use http://127.0.0.1:3032/"
} catch {
  throw "Servidor instalado, mas nao respondeu em http://127.0.0.1:3032/. Detalhe: $($_.Exception.Message)"
}
