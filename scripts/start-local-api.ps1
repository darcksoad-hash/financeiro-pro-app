$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LocalEnvFile = Join-Path $ProjectRoot ".env.local"
$CloudEnvFile = Join-Path $ProjectRoot ".env.vercel.local"
$EnvFile = if (Test-Path $LocalEnvFile) { $LocalEnvFile } else { $CloudEnvFile }

if (-not (Test-Path $EnvFile)) {
  throw "Arquivo de configuracao local nao encontrado. Rode scripts\install-local-server.ps1 antes de iniciar."
}

Remove-Item Env:\DATABASE_URL -ErrorAction SilentlyContinue

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
$env:DOTENV_CONFIG_PATH = $EnvFile
if ($EnvFile -eq $LocalEnvFile) {
  $env:DATABASE_URL = ""
}
Remove-Item Env:\VERCEL -ErrorAction SilentlyContinue

Set-Location $ProjectRoot
$LogDir = Join-Path $ProjectRoot "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$ErrorActionPreference = "Continue"
node server.js *>> (Join-Path $LogDir "financeiro-local-api.log")
