$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $ProjectRoot ".env.vercel.local"

if (-not (Test-Path $EnvFile)) {
  throw "Arquivo .env.vercel.local nao encontrado. Puxe as variaveis do Vercel antes de iniciar."
}

Get-Content $EnvFile | ForEach-Object {
  $line = $_.Trim()
  if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
    return
  }
  $name, $value = $line.Split("=", 2)
  $value = $value.Trim()
  if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
    $value = $value.Substring(1, $value.Length - 2)
  }
  [Environment]::SetEnvironmentVariable($name.Trim(), $value, "Process")
}

$env:PORT = "3032"
$env:NODE_ENV = "production"
Remove-Item Env:\VERCEL -ErrorAction SilentlyContinue

Set-Location $ProjectRoot
node server.js
