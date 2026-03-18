param(
  [Parameter(Mandatory = $true)]
  [string]$SeedDir,
  [string]$RedisContainer = "cryon-redis",
  [string]$RdbFileName = "redis-dump.rdb"
)

$ErrorActionPreference = "Stop"

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

Require-Command docker

if (-not (Test-Path $SeedDir)) {
  throw "Seed directory not found: $SeedDir"
}

$resolvedSeedDir = (Resolve-Path $SeedDir).Path
$rdbPath = Join-Path $resolvedSeedDir $RdbFileName
if (-not (Test-Path $rdbPath)) {
  throw "Redis dump not found: $rdbPath"
}

Write-Host "Using redis dump: $rdbPath"

$running = (docker inspect -f "{{.State.Running}}" $RedisContainer).Trim()
if ($running -eq "true") {
  Write-Host "Stopping redis container: $RedisContainer"
  docker stop $RedisContainer | Out-Null
}

docker cp $rdbPath "${RedisContainer}:/data/dump.rdb" | Out-Null

Write-Host "Starting redis container: $RedisContainer"
docker start $RedisContainer | Out-Null
Start-Sleep -Seconds 2

docker exec $RedisContainer redis-cli ping | Out-Null
Write-Host "Redis restore completed."
