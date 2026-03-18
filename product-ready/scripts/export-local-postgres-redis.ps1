param(
  [string]$OutputRoot = ".\\product-ready\\state-seed",
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

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $OutputRoot $timestamp
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Write-Host "Export folder: $outDir"

# ---- Postgres export (logical dump) ----
Write-Host "Exporting Postgres from container: $PostgresContainer"
$pgUser = (docker exec $PostgresContainer sh -lc 'printf %s "${POSTGRES_USER:-postgres}"').Trim()
$pgDb = (docker exec $PostgresContainer sh -lc 'printf %s "${POSTGRES_DB:-postgres}"').Trim()
if ([string]::IsNullOrWhiteSpace($pgUser)) { $pgUser = "postgres" }
if ([string]::IsNullOrWhiteSpace($pgDb)) { $pgDb = "postgres" }

$pgDumpPath = Join-Path $outDir "postgres-$pgDb.dump"
$pgTmpDump = "/tmp/product-ready-export.dump"
docker exec $PostgresContainer sh -lc "pg_dump -U '$pgUser' -d '$pgDb' -Fc -f '$pgTmpDump'" | Out-Null
docker cp "${PostgresContainer}:${pgTmpDump}" $pgDumpPath | Out-Null
docker exec $PostgresContainer sh -lc "rm -f '$pgTmpDump'" | Out-Null

# ---- Redis export (RDB snapshot) ----
Write-Host "Exporting Redis from container: $RedisContainer"
docker exec $RedisContainer redis-cli SAVE | Out-Null
$redisDumpPath = Join-Path $outDir "redis-dump.rdb"
docker cp "${RedisContainer}:/data/dump.rdb" $redisDumpPath | Out-Null

# ---- Metadata ----
$metaPath = Join-Path $outDir "export-meta.txt"
@(
  "created_at_utc=$((Get-Date).ToUniversalTime().ToString('o'))"
  "postgres_container=$PostgresContainer"
  "postgres_user=$pgUser"
  "postgres_db=$pgDb"
  "postgres_dump=$(Split-Path $pgDumpPath -Leaf)"
  "redis_container=$RedisContainer"
  "redis_dump=$(Split-Path $redisDumpPath -Leaf)"
) | Set-Content -Encoding UTF8 -Path $metaPath

Write-Host "Done."
Write-Host "Postgres dump: $pgDumpPath"
Write-Host "Redis dump:    $redisDumpPath"
Write-Host "Metadata:      $metaPath"
