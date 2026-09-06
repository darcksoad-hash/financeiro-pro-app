$ErrorActionPreference = "Continue"

$listeners = Get-NetTCPConnection -LocalPort 3032 -State Listen -ErrorAction SilentlyContinue

foreach ($listener in $listeners) {
  $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
  if ($process.Name -eq "node.exe" -and $process.CommandLine -match "server\.js") {
    Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "Financeiro Pro local parado."
