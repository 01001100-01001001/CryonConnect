param(
  [string]$EnvFile = ".\\product-ready\\env\\.env",
  [string]$ComposeFile = ".\\product-ready\\compose\\docker-compose.product-ready.yml",
  [switch]$WithSeedRestore,
  [string]$SeedDir,
  [string]$PostgresContainer = "cryon-postgres",
  [string]$RedisContainer = "cryon-redis"
)

$ErrorActionPreference = "Stop"

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

Require-Command docker

if (-not (Test-Path $EnvFile)) {
  throw "Missing env file: $EnvFile"
}
if (-not (Test-Path $ComposeFile)) {
  throw "Missing compose file: $ComposeFile"
}

Write-Host "Starting product-ready stack..."
docker compose --env-file $EnvFile -f $ComposeFile up -d

if ($WithSeedRestore) {
  if ([string]::IsNullOrWhiteSpace($SeedDir)) {
    throw "WithSeedRestore is set but SeedDir is empty"
  }

  Write-Host "Running seed restore from: $SeedDir"
  powershell -ExecutionPolicy Bypass -File ".\\product-ready\\scripts\\restore-postgres.ps1" `
    -SeedDir $SeedDir -PostgresContainer $PostgresContainer
  powershell -ExecutionPolicy Bypass -File ".\\product-ready\\scripts\\restore-redis.ps1" `
    -SeedDir $SeedDir -RedisContainer $RedisContainer
}

Write-Host "Done."
Write-Host "Check status with:"
Write-Host "docker compose --env-file $EnvFile -f $ComposeFile ps"
