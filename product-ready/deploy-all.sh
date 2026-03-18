#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  echo "[product-ready] $*"
}

fail() {
  echo "[product-ready][ERROR] $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}"
cd "${ROOT_DIR}"

[[ -f "compose/docker-compose.product-ready.yml" ]] || fail "Missing compose/docker-compose.product-ready.yml"
[[ -f "env/.env.example" ]] || fail "Missing env/.env.example"

sudo_run() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return
  fi

  log "Installing Docker Engine + Compose plugin..."
  sudo_run apt-get update -y
  sudo_run apt-get install -y ca-certificates curl gnupg lsb-release
  sudo_run install -m 0755 -d /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo_run gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo_run chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
  ARCH="$(dpkg --print-architecture)"
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" | sudo_run tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo_run apt-get update -y
  sudo_run apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo_run systemctl enable --now docker
}

ensure_docker

DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
  if [[ "${EUID}" -ne 0 ]]; then
    log "Docker requires sudo for current user; using sudo docker commands."
    DOCKER="sudo docker"
  else
    fail "Docker daemon not available"
  fi
fi

ENV_FILE="env/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  cp "env/.env.example" "${ENV_FILE}"
  log "Created ${ENV_FILE} from template."
fi

build_local_image_from_binary() {
  local local_image="cryon-chat-server:product-ready-local"
  [[ -f "artifacts/cryon-node-linux-amd64" ]] || return 1
  [[ -f "artifacts/version.txt" ]] || return 1

  log "Building local image from artifacts/cryon-node-linux-amd64 ..."
  ${DOCKER} build -t "${local_image}" -f - . <<'EOF'
FROM gcr.io/distroless/base-debian12:nonroot
WORKDIR /app
COPY --chmod=0755 artifacts/cryon-node-linux-amd64 /app/cryon-node
COPY --chmod=0644 artifacts/version.txt /app/version.txt
ENV CRYON_VERSION_FILE=/app/version.txt
EXPOSE 4543/tcp
EXPOSE 8585/tcp
ENTRYPOINT ["/app/cryon-node"]
EOF

  if grep -q '^CRYON_SERVER_IMAGE=' "${ENV_FILE}"; then
    sed -i "s#^CRYON_SERVER_IMAGE=.*#CRYON_SERVER_IMAGE=${local_image}#" "${ENV_FILE}"
  else
    echo "CRYON_SERVER_IMAGE=${local_image}" >> "${ENV_FILE}"
  fi
  log "Set CRYON_SERVER_IMAGE=${local_image} in ${ENV_FILE}"
  return 0
}

resolve_image() {
  local image
  image="$(grep '^CRYON_SERVER_IMAGE=' "${ENV_FILE}" | tail -n1 | cut -d'=' -f2- || true)"
  if [[ -z "${image}" ]]; then
    fail "CRYON_SERVER_IMAGE is empty in ${ENV_FILE}"
  fi

  if [[ "${image}" == *"sha-REPLACE_ME"* ]]; then
    log "CRYON_SERVER_IMAGE still placeholder."
    build_local_image_from_binary || fail "Set CRYON_SERVER_IMAGE in env/.env or provide artifacts/cryon-node-linux-amd64"
    return
  fi

  if [[ "${image}" == "cryon-chat-server:product-ready-local" ]]; then
    log "Refreshing local product-ready image from bundled binary artifacts..."
    build_local_image_from_binary || fail "Missing artifacts/cryon-node-linux-amd64 or artifacts/version.txt"
    return
  fi

  if ! ${DOCKER} image inspect "${image}" >/dev/null 2>&1; then
    log "Image ${image} not found locally. Trying to pull..."
    if ! ${DOCKER} pull "${image}"; then
      log "Pull failed for ${image}. Attempting local artifact image fallback..."
      build_local_image_from_binary || fail "Cannot pull ${image} and no local binary artifacts found"
    fi
  fi
}

wait_for_postgres() {
  local pg_container="${1}"
  local pg_user
  pg_user="$(${DOCKER} exec "${pg_container}" sh -lc 'printf %s "${POSTGRES_USER:-postgres}"')"
  for _ in $(seq 1 60); do
    if ${DOCKER} exec "${pg_container}" sh -lc "pg_isready -U '${pg_user}'" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

restore_seed_if_present() {
  local latest_seed
  latest_seed="$(find state-seed -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n1 || true)"
  if [[ -z "${latest_seed}" ]]; then
    log "No state-seed directory found. Skipping restore."
    return
  fi

  if [[ "${AUTO_RESTORE_SEED:-1}" != "1" ]]; then
    log "AUTO_RESTORE_SEED=${AUTO_RESTORE_SEED:-0}; skipping seed restore."
    return
  fi

  log "Restoring seed from ${latest_seed} ..."

  local pg_container="${POSTGRES_CONTAINER:-cryon-postgres}"
  local redis_container="${REDIS_CONTAINER:-cryon-redis}"
  local pg_dump
  pg_dump="$(ls -1 "${latest_seed}"/postgres-*.dump 2>/dev/null | head -n1 || true)"
  local redis_dump="${latest_seed}/redis-dump.rdb"

  if [[ -n "${pg_dump}" ]]; then
    wait_for_postgres "${pg_container}" || fail "Postgres not ready in ${pg_container}"
    local pg_user pg_db
    pg_user="$(${DOCKER} exec "${pg_container}" sh -lc 'printf %s "${POSTGRES_USER:-postgres}"')"
    pg_db="$(${DOCKER} exec "${pg_container}" sh -lc 'printf %s "${POSTGRES_DB:-postgres}"')"

    ${DOCKER} cp "${pg_dump}" "${pg_container}:/tmp/product-ready-restore.dump"
    ${DOCKER} exec "${pg_container}" sh -lc "pg_restore -U '${pg_user}' -d '${pg_db}' --clean --if-exists --no-owner --no-privileges /tmp/product-ready-restore.dump"
    ${DOCKER} exec "${pg_container}" sh -lc "rm -f /tmp/product-ready-restore.dump"
    log "Postgres restore done."
  else
    log "No postgres dump found in ${latest_seed}; skip Postgres restore."
  fi

  if [[ -f "${redis_dump}" ]]; then
    ${DOCKER} compose --env-file "${ENV_FILE}" -f compose/docker-compose.product-ready.yml stop redis >/dev/null
    ${DOCKER} cp "${redis_dump}" "${redis_container}:/data/dump.rdb"
    ${DOCKER} compose --env-file "${ENV_FILE}" -f compose/docker-compose.product-ready.yml start redis >/dev/null
    log "Redis restore done."
  else
    log "No redis-dump.rdb found in ${latest_seed}; skip Redis restore."
  fi
}

resolve_image

log "Starting stack..."
${DOCKER} compose --env-file "${ENV_FILE}" -f compose/docker-compose.product-ready.yml up -d

restore_seed_if_present

log "Deployment completed."
${DOCKER} compose --env-file "${ENV_FILE}" -f compose/docker-compose.product-ready.yml ps
