param(
  [Parameter(Mandatory = $true)]
  [string]$SeedDir,
  [string]$PostgresContainer = "cryon-postgres",
  [string]$DumpFileName
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
if ([string]::IsNullOrWhiteSpace($DumpFileName)) {
  $candidate = Get-ChildItem -Path $resolvedSeedDir -Filter "postgres-*.dump" | Select-Object -First 1
  if ($null -eq $candidate) {
    throw "No postgres dump file found in $resolvedSeedDir"
  }
  $dumpPath = $candidate.FullName
} else {
  $dumpPath = Join-Path $resolvedSeedDir $DumpFileName
  if (-not (Test-Path $dumpPath)) {
    throw "Dump file not found: $dumpPath"
  }
}

Write-Host "Using postgres dump: $dumpPath"

$pgUser = (docker exec $PostgresContainer sh -lc 'printf %s "${POSTGRES_USER:-postgres}"').Trim()
$pgDb = (docker exec $PostgresContainer sh -lc 'printf %s "${POSTGRES_DB:-postgres}"').Trim()
if ([string]::IsNullOrWhiteSpace($pgUser)) { $pgUser = "postgres" }
if ([string]::IsNullOrWhiteSpace($pgDb)) { $pgDb = "postgres" }

$tmpDumpPath = "/tmp/product-ready-restore.dump"
docker cp $dumpPath "${PostgresContainer}:${tmpDumpPath}" | Out-Null

Write-Host "Restoring into database '$pgDb' as user '$pgUser'..."
docker exec $PostgresContainer sh -lc "pg_restore -U '$pgUser' -d '$pgDb' --clean --if-exists --no-owner --no-privileges '$tmpDumpPath'" | Out-Null
docker exec $PostgresContainer sh -lc "rm -f '$tmpDumpPath'" | Out-Null

Write-Host "Postgres restore completed."
