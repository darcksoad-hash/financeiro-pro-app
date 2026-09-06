$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Desktop = [Environment]::GetFolderPath("Desktop")
if (-not $Desktop) {
  $Desktop = Join-Path $env:USERPROFILE "Desktop"
}

$PackageScript = Join-Path $PSScriptRoot "create-local-installer-package.ps1"
$PackageZip = Join-Path $Desktop "Financeiro-Pro-Instalador-Local.zip"
$InstallerExe = Join-Path $Desktop "Financeiro-Pro-Setup.exe"
$InstallerCmd = Join-Path $Desktop "Financeiro-Pro-Setup.cmd"
$InstallerPs1 = Join-Path $Desktop "Financeiro-Pro-Setup.ps1"
$StageRoot = Join-Path $env:TEMP "financeiro-pro-single-installer"

Write-Host "Preparando pacote local do Financeiro Pro..."
& $PackageScript

if (-not (Test-Path $PackageZip)) {
  throw "Pacote base nao encontrado: $PackageZip"
}

Remove-Item $StageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null

$zipBytes = [IO.File]::ReadAllBytes($PackageZip)
$zipBase64 = [Convert]::ToBase64String($zipBytes)
$payloadPath = Join-Path $StageRoot "Financeiro-Pro-Setup.ps1"
$runnerPath = Join-Path $StageRoot "Financeiro-Pro-Setup.cmd"
$sedPath = Join-Path $StageRoot "Financeiro-Pro-Setup.sed"

$payload = @"
param(
  [string]`$InstallDir = (Join-Path `$env:LOCALAPPDATA "FinanceiroPro")
)

`$ErrorActionPreference = "Stop"

function Assert-Command([string]`$CommandName, [string]`$FriendlyName) {
  if (-not (Get-Command `$CommandName -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "`$FriendlyName nao encontrado."
    Write-Host "Instale o Node.js LTS e rode este instalador novamente:"
    Write-Host "https://nodejs.org/"
    Start-Process "https://nodejs.org/" -ErrorAction SilentlyContinue
    throw "`$FriendlyName nao encontrado."
  }
}

Write-Host "Instalando Financeiro Pro neste computador..."
Write-Host "Pasta local: `$InstallDir"

Assert-Command "node.exe" "Node.js"
Assert-Command "npm.cmd" "npm"

New-Item -ItemType Directory -Path `$InstallDir -Force | Out-Null

`$tempZip = Join-Path `$env:TEMP ("financeiro-pro-local-" + [Guid]::NewGuid().ToString("N") + ".zip")
`$base64 = @'
$zipBase64
'@

[IO.File]::WriteAllBytes(`$tempZip, [Convert]::FromBase64String(`$base64))

`$extractRoot = Join-Path `$env:TEMP ("financeiro-pro-extract-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path `$extractRoot -Force | Out-Null

try {
  Expand-Archive -Path `$tempZip -DestinationPath `$extractRoot -Force
  Copy-Item -Path (Join-Path `$extractRoot "*") -Destination `$InstallDir -Recurse -Force

  `$installScript = Join-Path `$InstallDir "scripts\install-local-server.ps1"
  if (-not (Test-Path `$installScript)) {
    throw "Arquivo de instalacao nao encontrado dentro do pacote."
  }

  & `$installScript

  Write-Host ""
  Write-Host "Financeiro Pro instalado com sucesso."
  Write-Host "Abra pelo atalho Financeiro Pro na Area de Trabalho."
  Write-Host "Usuario inicial: admin.financeiro"
  Write-Host "Senha inicial: FinanceiroLocal@2026"
} finally {
  Remove-Item `$tempZip -Force -ErrorAction SilentlyContinue
  Remove-Item `$extractRoot -Recurse -Force -ErrorAction SilentlyContinue
}
"@

Set-Content -Path $payloadPath -Encoding ASCII -Value $payload

Set-Content -Path $runnerPath -Encoding ASCII -Value @(
  "@echo off",
  "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""%~dp0Financeiro-Pro-Setup.ps1""",
  "pause"
)

Copy-Item $payloadPath $InstallerPs1 -Force
Copy-Item $runnerPath $InstallerCmd -Force

$iexpress = Join-Path $env:SystemRoot "System32\iexpress.exe"
if (-not (Test-Path $iexpress)) {
  Write-Host "IExpress nao encontrado. Instalador criado em: $InstallerCmd"
  Write-Host "Arquivo auxiliar criado em: $InstallerPs1"
  exit 0
}

$escapedStageRoot = $StageRoot.TrimEnd("\") + "\"
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=Instalacao concluida.
TargetName=$InstallerExe
FriendlyName=Financeiro Pro Setup
AppLaunched=Financeiro-Pro-Setup.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=Financeiro-Pro-Setup.cmd
UserQuietInstCmd=Financeiro-Pro-Setup.cmd
SourceFiles=SourceFiles
[SourceFiles]
SourceFiles0=$escapedStageRoot
[SourceFiles0]
%FILE0%=
%FILE1%=
[Strings]
FILE0="Financeiro-Pro-Setup.cmd"
FILE1="Financeiro-Pro-Setup.ps1"
"@

Set-Content -Path $sedPath -Encoding ASCII -Value $sed
Remove-Item $InstallerExe -Force -ErrorAction SilentlyContinue

Write-Host "Gerando instalador EXE..."
& $iexpress /N /Q $sedPath

for ($i = 0; $i -lt 20 -and -not (Test-Path $InstallerExe); $i++) {
  Start-Sleep -Milliseconds 500
}

if (Test-Path $InstallerExe) {
  Write-Host "Instalador criado em: $InstallerExe"
} else {
  Write-Host "Nao foi possivel gerar o EXE. Use o instalador em: $InstallerCmd"
  Write-Host "Arquivo auxiliar criado em: $InstallerPs1"
}
