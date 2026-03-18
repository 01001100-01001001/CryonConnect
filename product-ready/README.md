# Product-Ready Ubuntu Deploy Guide

This folder contains the Linux deployment bundle for Cryon server stack:

- `cryon-chat-server`
- `postgres`
- `redis`

The deployment entrypoint is `deploy-all.sh`.

## Tested Environment

Verified on:

- Ubuntu Server 22.04 LTS (Jammy)
- Docker Engine + Docker Compose plugin installed by `deploy-all.sh`

## Files Used By Deploy

Required:

- `compose/docker-compose.product-ready.yml`
- `env/.env.example` (template)
- `deploy-all.sh`
- `artifacts/cryon-node-linux-amd64`
- `artifacts/libnqp_node.so`
- `artifacts/version.txt`

Optional:

- `state-seed/<timestamp>/postgres-*.dump`
- `state-seed/<timestamp>/redis-dump.rdb`

## Deploy On Ubuntu

```bash
git clone https://github.com/01001100-01001001/CryonConnect
cd CryonConnect/product-ready
chmod +x deploy-all.sh
./deploy-all.sh
```

`deploy-all.sh` will:

- install Docker/Compose if missing
- create `env/.env` from `env/.env.example` (first run)
- build local runtime image from `artifacts/*` when needed
- start the stack with `docker compose`
- restore latest seed automatically if `state-seed` exists

## Where To Change Password / IP / Ports

After first run, edit:

- `product-ready/env/.env`

Main values:

- `POSTGRES_PASSWORD` -> change database password
- `POSTGRES_USER` / `POSTGRES_DB` -> adjust DB account/database if needed
- `CRYON_NQ_INGRESS_PORT` -> public port (default `443`) used for UDP primary (`container:4543/udp`) and TCP fallback (`container:4544/tcp`)
- `CRYON_OBS_PORT` -> host port mapped to observability panel (`8585` in container)
- `CRYON_SERVER_IMAGE` -> pinned remote image (`sha-*` or `vX.Y.Z`) or keep local build flow
- `CRYON_ALLOW_RAW_ONLY_FALLBACK` -> set `false` to enforce native NQFFI startup

If you need to change bind address inside container, edit:

- `CRYON_NQ_INGRESS_ADDR`
- `CRYON_RAW_INGRESS_ADDR`
- `CRYON_OBS_ADDR`

in `env/.env`.

Then apply changes:

```bash
cd CryonConnect/product-ready
./deploy-all.sh
```

## Verify After Install

```bash
docker compose --env-file env/.env -f compose/docker-compose.product-ready.yml ps
docker logs --tail 120 cryon-chat-server
```

Expected server log lines:

- `Transport mode: nq_only_ffi`
- `=== Cryon Chat Server Started ===`

## Notes

- Default transport profile is UDP primary on port `443` with TCP fallback on the same public port.
- For go-live, prefer pinned image tags (`sha-*` or `vX.Y.Z`), not `latest`.
- Keep secrets only in `env/.env` on the server, do not commit secrets.