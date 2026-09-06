$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Launcher = Join-Path $PSScriptRoot "start-local-api.ps1"
$Url = "http://127.0.0.1:3032/"

function Test-FinanceiroLocal {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5
    return $response.StatusCode -eq 200
  } catch {
    return $false
  }
}

if (-not (Test-FinanceiroLocal)) {
  Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-WindowStyle", "Hidden", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Launcher) `
    -WindowStyle Hidden

  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    if (Test-FinanceiroLocal) { break }
  }
}

Start-Process $Url
