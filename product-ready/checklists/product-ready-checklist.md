# Product-Ready Checklist

## 1) Bundle Preparation (Local)

- Copy `product-ready/env/.env.example` to `product-ready/env/.env`.
- Fill strong secrets and production values.
- Set `CRYON_SERVER_IMAGE` to a pinned tag (`sha-...` or `vX.Y.Z`).
- (Optional) Export local seed data with:
  - `powershell -File product-ready/scripts/export-local-postgres-redis.ps1`

## 2) Target Host Preparation

- Ensure Docker Engine + Docker Compose are installed.
- Ensure required ports are open:
  - `4543/tcp` (NQ ingress)
  - `8585/tcp` (observability panel, if enabled)
- Confirm no old Cryon stack is running.

## 3) Deploy

- On target machine, place the `product-ready` folder.
- Start stack:
  - `docker compose --env-file env/.env -f compose/docker-compose.product-ready.yml up -d`
- Validate:
  - `docker compose -f compose/docker-compose.product-ready.yml ps`
  - `docker logs cryon-chat-server --tail 200`

## 4) Optional Restore (Seed Data)

- Postgres restore:
  - `pg_restore` into target DB from exported `.dump`.
- Redis restore:
  - stop Redis, place `dump.rdb` into data dir, restart Redis.
- Re-run health checks after restore.

## 5) Go-Live Guardrails

- Never deploy go-live with `latest` tag.
- Keep one `.env` per environment (dev/stage/prod), do not mix.
- Keep deployment artifacts and seed dumps archived per release.
