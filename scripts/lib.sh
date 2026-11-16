#!/usr/bin/env bash
# Shared helpers for artcraft-cloud scripts. Source it; do not run it.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_DIR
ENV_FILE="${REPO_DIR}/.env"

# KEY from the environment if set, else from .env, else the given default.
# Surrounding single or double quotes in .env are stripped.
env_get() {
  local key="$1" default="${2:-}" val
  if [ -n "${!key+x}" ]; then printf '%s' "${!key}"; return 0; fi
  if [ -f "${ENV_FILE}" ]; then
    val="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n1 | cut -d= -f2- || true)"
    val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    if [ -n "${val}" ]; then printf '%s' "${val}"; return 0; fi
  fi
  printf '%s' "${default}"
}

lock_value() { grep -E "^$1=" "${REPO_DIR}/UPSTREAM.lock" | head -n1 | cut -d= -f2-; }

DATA_DIR="$(env_get DATA_DIR /data/artcraft)"
UPSTREAM_DIR="$(env_get UPSTREAM_DIR "${DATA_DIR}/upstream")"
export DATA_DIR UPSTREAM_DIR

s3_enabled() { [ "$(env_get S3_SYNC_ENABLED false)" = "true" ]; }
caddy_enabled() { [ -n "$(env_get DOMAIN_NAME)" ]; }

# docker compose with the base file plus whichever add-ons .env switches on.
acc_compose() {
  local files=(-f "${REPO_DIR}/docker/docker-compose.yml")
  s3_enabled && files+=(-f "${REPO_DIR}/docker/docker-compose.s3.yml")
  caddy_enabled && files+=(-f "${REPO_DIR}/docker/docker-compose.caddy.yml")
  local envargs=()
  [ -f "${ENV_FILE}" ] && envargs=(--env-file "${ENV_FILE}")
  docker compose --project-directory "${REPO_DIR}/docker" "${envargs[@]}" "${files[@]}" "$@"
}

die() { echo "error: $*" >&2; exit 1; }
