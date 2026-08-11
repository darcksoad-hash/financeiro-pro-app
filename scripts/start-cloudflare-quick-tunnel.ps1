$ErrorActionPreference = "Stop"

$Cloudflared = "C:\Users\darck\Tools\cloudflared\cloudflared.exe"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $ProjectRoot "logs"
$OutLog = Join-Path $LogDir "financeiro-cloudflare.out.log"
$ErrLog = Join-Path $LogDir "financeiro-cloudflare.err.log"
$LinkFile = Join-Path ([Environment]::GetFolderPath("Desktop")) "LINK_FINANCEIRO.txt"

if (-not (Test-Path $Cloudflared)) {
  throw "cloudflared.exe nao encontrado em $Cloudflared"
}

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

Get-CimInstance Win32_Process |
  Where-Object { $_.Name -like "*cloudflared*" -and $_.CommandLine -match "127\.0\.0\.1:3032" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Remove-Item $OutLog, $ErrLog -ErrorAction SilentlyContinue

Start-Process -FilePath $Cloudflared `
  -ArgumentList @("tunnel", "--url", "http://127.0.0.1:3032", "--protocol", "http2", "--no-autoupdate") `
  -WindowStyle Hidden `
  -RedirectStandardOutput $OutLog `
  -RedirectStandardError $ErrLog

$url = $null
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path $ErrLog) {
    $url = Select-String -Path $ErrLog -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" -AllMatches |
      ForEach-Object { $_.Matches.Value } |
      Select-Object -Last 1
  }
  if ($url) { break }
}

if ($url) {
  Set-Content -Path $LinkFile -Value @(
    "Financeiro Pro online:",
    $url,
    "",
    "Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
  ) -Encoding UTF8
}
