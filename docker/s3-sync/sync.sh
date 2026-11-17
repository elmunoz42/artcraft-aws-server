#!/usr/bin/env bash
# Sync folders to S3 on an interval:
#   /backups  ->  s3://$S3_BUCKET/$S3_PREFIX/           completed backups
#   /outputs  ->  s3://$S3_BUCKET/$S3_OUTPUTS_PREFIX/   files exported by the Craft apps (MCP add-on)
# A folder that is not mounted or is missing is skipped.
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
OUTPUTS_SRC="${SYNC_OUTPUTS_SOURCE:-/outputs}"
STATUS_DIR="${STATUS_DIR:-/status}"
INTERVAL="${SYNC_INTERVAL_SECONDS:-300}"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) s3-sync: $*"; }

# Empty static credentials must not mask the instance role.
[ -n "${AWS_ACCESS_KEY_ID:-}" ] || unset AWS_ACCESS_KEY_ID
[ -n "${AWS_SECRET_ACCESS_KEY:-}" ] || unset AWS_SECRET_ACCESS_KEY
if [ -n "${AWS_REGION:-}" ]; then export AWS_DEFAULT_REGION="${AWS_REGION}"; else unset AWS_REGION; fi

enabled() { [ "${S3_SYNC_ENABLED:-false}" = "true" ]; }

destination() {
  local prefix="$1"
  prefix="${prefix#/}"; prefix="${prefix%/}"
  if [ -n "${prefix}" ]; then echo "s3://${S3_BUCKET}/${prefix}/"; else echo "s3://${S3_BUCKET}/"; fi
}

# One folder. Backups in progress are written to ".<timestamp>.partial" and renamed when
# complete; hidden folders such as caches are never uploaded.
sync_dir() {
  local src="$1" dest args
  dest="$(destination "$2")"
  args=(s3 sync "${src}/" "${dest}" --exclude ".*" --exclude "*/.*" --no-progress --only-show-errors)
  [ "${SYNC_DELETE:-false}" = "true" ] && args+=(--delete)
  log "sync ${src}/ -> ${dest} (delete=${SYNC_DELETE:-false})"
  aws "${args[@]}"
}

sync_once() {
  local started rc=0 did=0
  [ -n "${S3_BUCKET:-}" ] || { log "S3_BUCKET is empty"; return 2; }
  started="$(date +%s)"
  if [ -d "${SRC}" ]; then did=1; sync_dir "${SRC}" "${S3_PREFIX:-backups}" || rc=$?; fi
  if [ -d "${OUTPUTS_SRC}" ]; then did=1; sync_dir "${OUTPUTS_SRC}" "${S3_OUTPUTS_PREFIX:-outputs}" || rc=$?; fi
  [ "${did}" -eq 1 ] || { log "nothing to sync: neither ${SRC} nor ${OUTPUTS_SRC} exists"; return 2; }
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
