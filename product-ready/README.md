# Product-Ready Deployment Bundle

This folder is the standardized deployment bundle for rolling out Cryon to any target machine with the same baseline configuration.

## Goal

- Keep deployment reproducible across environments.
- Use container-first runtime layout.
- Separate infrastructure configuration from live local machine state.

## Structure

- `compose/docker-compose.product-ready.yml`:
  - Standard container topology (Postgres, Redis, Cryon server).
- `env/.env.example`:
  - Baseline environment variables to copy into `.env` per target machine.

## Do We Need to Pull Local Postgres/Redis Into This Folder?

Short answer: **do not copy raw container data directories** from a live local machine.

Preferred approach:

1. Keep baseline runtime configuration in this folder (`compose` + `.env`).
2. Export state from local containers as portable artifacts:
   - Postgres: logical dump (`.dump` from `pg_dump`).
   - Redis: snapshot (`dump.rdb`).
3. Restore those artifacts on the target machine only when you intentionally need seeded data.

Why:

- Raw volume copies are host-specific and fragile.
- Dumps/snapshots are safer, reproducible, and easier to version or archive.

## Quick Start

1. Copy `env/.env.example` to `env/.env` and fill real values.
2. (Optional) Export local state:
   - Run `scripts/export-local-postgres-redis.ps1`.
3. Deploy:
   - `docker compose --env-file env/.env -f compose/docker-compose.product-ready.yml up -d`

## Production Tag Policy

For production-like/go-live deployments, use pinned image tags only:

- `sha-<commit>`
- `vX.Y.Z`

Avoid `latest` for go-live workflows.

## GitHub Distribution Model

For VPS pull-and-run workflow:

- Keep scripts/config in this repository (`product-ready/*`).
- Keep real secrets only on VPS in `env/.env` (never commit).
- Commit runtime binary artifacts in `artifacts/` so VPS can pull-and-run directly; keep sensitive data seeds (`state-seed/`) out of git.

Run on Ubuntu VPS:

```bash
git clone https://github.com/01001100-01001001/CryonConnect
cd CryonConnect/product-ready
chmod +x setup.sh deploy-all.sh
./setup.sh
```


## Included Runtime Binary

This repository includes server runtime artifacts in `product-ready/artifacts/`:

- `cryon-node-linux-amd64`
- `version.txt`
- `binary-manifest.txt`

`deploy-all.sh` can automatically build a local container image from these artifacts when `CRYON_SERVER_IMAGE` is placeholder or remote pull is unavailable.


## Linux-Only Deploy

This repository keeps deployment path focused on Ubuntu/Linux shell scripts:

- `setup.sh`
- `deploy-all.sh`

PowerShell helper scripts are intentionally excluded from this repository.
