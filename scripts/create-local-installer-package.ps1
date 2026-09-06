$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Desktop = [Environment]::GetFolderPath("Desktop")
if (-not $Desktop) {
  $Desktop = Join-Path $env:USERPROFILE "Desktop"
}

$PackageRoot = Join-Path $env:TEMP "financeiro-pro-local-installer"
$ZipPath = Join-Path $Desktop "Financeiro-Pro-Instalador-Local.zip"

Remove-Item $PackageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null

$excludeDirs = @("\.git($|\\)", "\\node_modules($|\\)", "\\logs($|\\)", "\\.vercel($|\\)")
$excludeFiles = @("\\.env$", "\\.env\..*local$", "\\data\.local\.json$")

Get-ChildItem -Path $ProjectRoot -Recurse -Force | ForEach-Object {
  $relative = $_.FullName.Substring($ProjectRoot.Length).TrimStart("\")
  $normalized = "\" + $relative

  foreach ($pattern in $excludeDirs) {
    if ($normalized -match $pattern) { return }
  }

  foreach ($pattern in $excludeFiles) {
    if ($normalized -match $pattern) { return }
  }

  $target = Join-Path $PackageRoot $relative
  if ($_.PSIsContainer) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
  } else {
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item $_.FullName $target -Force
  }
}

Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $PackageRoot "*") -DestinationPath $ZipPath -Force

Write-Host "Pacote criado em: $ZipPath"
Write-Host "Por seguranca, arquivos .env e senhas nao foram incluidos."
