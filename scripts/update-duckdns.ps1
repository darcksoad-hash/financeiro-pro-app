param(
  [switch]$Loop,
  [int]$IntervalMinutes = 30
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $ProjectRoot ".env.duckdns.local"
$StatusFile = Join-Path ([Environment]::GetFolderPath("Desktop")) "STATUS_DUCKDNS_FINANCEIRO.txt"

if (-not (Test-Path $EnvFile)) {
  throw "Arquivo .env.duckdns.local nao encontrado."
}

$settings = @{}
Get-Content $EnvFile | ForEach-Object {
  $line = $_.Trim()
  if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
    return
  }
  $name, $value = $line.Split("=", 2)
  $settings[$name.Trim()] = $value.Trim().Trim('"').Trim("'")
}

$domain = $settings["DUCKDNS_DOMAIN"]
$token = $settings["DUCKDNS_TOKEN"]

if (-not $domain -or -not $token) {
  throw "Informe DUCKDNS_DOMAIN e DUCKDNS_TOKEN em .env.duckdns.local."
}

do {
  $updateUrl = "https://www.duckdns.org/update?domains=$domain&token=$token&ip="
  $response = Invoke-WebRequest -Uri $updateUrl -UseBasicParsing
  $content = [System.Text.Encoding]::UTF8.GetString($response.Content).Trim()
  $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json").ip

  Set-Content -Path $StatusFile -Value @(
    "DuckDNS Financeiro",
    "Dominio: https://$domain.duckdns.org",
    "IP publico: $publicIp",
    "Atualizacao: $content",
    "Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
  ) -Encoding UTF8

  Write-Output $content
  if ($Loop) {
    Start-Sleep -Seconds ([Math]::Max(1, $IntervalMinutes) * 60)
  }
} while ($Loop)
