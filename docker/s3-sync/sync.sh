#!/usr/bin/env bash
# Sync /backups to s3://$S3_BUCKET/$S3_PREFIX on an interval.
#
#   sync.sh run          loop forever (container default)
#   sync.sh once         one sync, exit with its status
#   sync.sh healthcheck  exit 0 if the last successful sync is recent enough
#   sync.sh status       print the last successful sync time
#
# Status files in /status:
#   last_success        epoch seconds of the last successful sync
#   last_success_iso    the same moment in UTC ISO 8601
#   last_error          message from the most recent failed run (removed on success)
set -uo pipefail

SRC="${SYNC_SOURCE:-/backups}"
STATUS_DIR="${STATUS_DIR:-/status}"
INTERVAL="${SYNC_INTERVAL_SECONDS:-300}"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) s3-sync: $*"; }

# Empty static credentials must not mask the instance role.
[ -n "${AWS_ACCESS_KEY_ID:-}" ] || unset AWS_ACCESS_KEY_ID
[ -n "${AWS_SECRET_ACCESS_KEY:-}" ] || unset AWS_SECRET_ACCESS_KEY
if [ -n "${AWS_REGION:-}" ]; then export AWS_DEFAULT_REGION="${AWS_REGION}"; else unset AWS_REGION; fi

enabled() { [ "${S3_SYNC_ENABLED:-false}" = "true" ]; }

destination() {
  local prefix="${S3_PREFIX:-}"
  prefix="${prefix#/}"; prefix="${prefix%/}"
  if [ -n "${prefix}" ]; then echo "s3://${S3_BUCKET}/${prefix}/"; else echo "s3://${S3_BUCKET}/"; fi
}

sync_once() {
  local dest args started rc
  [ -n "${S3_BUCKET:-}" ] || { log "S3_BUCKET is empty"; return 2; }
  [ -d "${SRC}" ] || { log "source ${SRC} is missing"; return 2; }
  dest="$(destination)"
  # Backups in progress are written to ".<timestamp>.partial" and renamed when complete.
  args=(s3 sync "${SRC}/" "${dest}" --exclude ".*.partial/*" --no-progress --only-show-errors)
  [ "${SYNC_DELETE:-false}" = "true" ] && args+=(--delete)
  started="$(date +%s)"
  log "sync start ${SRC}/ -> ${dest} (delete=${SYNC_DELETE:-false})"
  aws "${args[@]}"
  rc=$?
  if [ "${rc}" -eq 0 ]; then
    date +%s > "${STATUS_DIR}/last_success"
    date -u +%Y-%m-%dT%H:%M:%SZ > "${STATUS_DIR}/last_success_iso"
    rm -f "${STATUS_DIR}/last_error"
    log "sync ok in $(( $(date +%s) - started ))s"
  else
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) aws s3 sync exited ${rc}" > "${STATUS_DIR}/last_error"
    log "sync FAILED (aws exit ${rc})"
  fi
  return "${rc}"
}

healthcheck() {
  local last age max
  enabled || exit 0
  [ -f "${STATUS_DIR}/last_success" ] || { echo "no successful sync yet"; exit 1; }
  last="$(cat "${STATUS_DIR}/last_success")"
  age=$(( $(date +%s) - last ))
  max=$(( INTERVAL * 3 + 120 ))
  if [ "${age}" -le "${max}" ]; then
    echo "last successful sync ${age}s ago"; exit 0
  fi
  echo "last successful sync ${age}s ago (limit ${max}s)"; exit 1
}

mkdir -p "${STATUS_DIR}"
case "${1:-run}" in
  once) sync_once; exit $? ;;
  healthcheck) healthcheck ;;
  status)
    if [ -f "${STATUS_DIR}/last_success_iso" ]; then cat "${STATUS_DIR}/last_success_iso"; else echo "never"; fi
    [ -f "${STATUS_DIR}/last_error" ] && cat "${STATUS_DIR}/last_error"
    exit 0 ;;
  run)
    if ! enabled; then
      log "S3_SYNC_ENABLED is not true; idling"
      while true; do sleep 3600; done
    fi
    [[ "${INTERVAL}" =~ ^[1-9][0-9]*$ ]] || { log "SYNC_INTERVAL_SECONDS must be a positive integer"; exit 2; }
    trap 'log "stopping"; exit 0' TERM INT
    while true; do
      sync_once || true
      sleep "${INTERVAL}" &
      wait $!
    done ;;
  *) echo "usage: sync.sh {run|once|healthcheck|status}" >&2; exit 2 ;;
esac
