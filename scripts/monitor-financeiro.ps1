$ErrorActionPreference = "Continue"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ApiLauncher = Join-Path $PSScriptRoot "start-local-api.ps1"
$TunnelLauncher = Join-Path $PSScriptRoot "start-cloudflare-quick-tunnel.ps1"
$StatusFile = Join-Path ([Environment]::GetFolderPath("Desktop")) "STATUS_FINANCEIRO.txt"
$LinkFile = Join-Path ([Environment]::GetFolderPath("Desktop")) "LINK_FINANCEIRO.txt"
$LocalUrl = "http://127.0.0.1:3032/"
$IntervalSeconds = 60
$tunnelFailures = 0

function Test-FinanceiroLocal {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $LocalUrl -TimeoutSec 10
    return $response.StatusCode -eq 200 -and $response.Content -match "FinancePro"
  } catch {
    return $false
  }
}

function Get-FinanceiroTunnel {
  return Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -like "*cloudflared*" -and
      $_.CommandLine -match "127\.0\.0\.1:3032"
    } |
    Select-Object -First 1
}

function Get-TunnelUrl {
  if (-not (Test-Path $LinkFile)) {
    return $null
  }

  $content = Get-Content $LinkFile -Raw -ErrorAction SilentlyContinue
  return [regex]::Match($content, "https://[a-z0-9-]+\.trycloudflare\.com").Value
}

function Test-FinanceiroPublic {
  $url = Get-TunnelUrl
  if (-not $url) {
    return $false
  }

  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 15
    return $response.StatusCode -eq 200 -and $response.Content -match "FinancePro"
  } catch {
    return $false
  }
}

function Start-HiddenPowerShell([string]$ScriptPath) {
  Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-WindowStyle", "Hidden", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) `
    -WindowStyle Hidden
}

while ($true) {
  $localOk = Test-FinanceiroLocal
  $apiAction = "Ativo"
  $tunnelAction = "Ativo"

  if (-not $localOk) {
    $listener = Get-NetTCPConnection -LocalPort 3032 -State Listen -ErrorAction SilentlyContinue |
      Select-Object -First 1

    if ($listener) {
      $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
      if ($process.Name -eq "node.exe" -and $process.CommandLine -match "server\.js") {
        Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
      }
    }

    Start-HiddenPowerShell $ApiLauncher
    $apiAction = "Reiniciado"
    Start-Sleep -Seconds 8
    $localOk = Test-FinanceiroLocal
  }

  $tunnel = Get-FinanceiroTunnel
  if ($localOk -and -not $tunnel) {
    Start-HiddenPowerShell $TunnelLauncher
    $tunnelAction = "Reiniciado"
    Start-Sleep -Seconds 35
    $tunnel = Get-FinanceiroTunnel
  }

  $publicOk = $localOk -and $tunnel -and (Test-FinanceiroPublic)
  if ($publicOk) {
    $tunnelFailures = 0
  } elseif ($localOk -and $tunnel) {
    $tunnelFailures++
    $tunnelAction = "Falha publica $tunnelFailures/2"

    if ($tunnelFailures -ge 2) {
      Stop-Process -Id $tunnel.ProcessId -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 2
      Start-HiddenPowerShell $TunnelLauncher
      $tunnelAction = "Link expirado; reiniciado"
      Start-Sleep -Seconds 35
      $tunnel = Get-FinanceiroTunnel
      $publicOk = $tunnel -and (Test-FinanceiroPublic)
      $tunnelFailures = 0
    }
  }

  @(
    "Financeiro Pro - monitor automatico",
    "Ultima verificacao: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
    "Sistema local: $(if ($localOk) { 'ATIVO' } else { 'INDISPONIVEL' }) ($apiAction)",
    "Acesso externo: $(if ($publicOk) { 'ATIVO' } else { 'INDISPONIVEL' }) ($tunnelAction)",
    "Endereco local: http://192.168.24.3:3032",
    "O endereco externo atual fica no arquivo LINK_FINANCEIRO.txt"
  ) | Set-Content -Path $StatusFile -Encoding UTF8

  Start-Sleep -Seconds $IntervalSeconds
}
