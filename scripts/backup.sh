#!/usr/bin/env bash
# Take a consistent backup with the upstream template's backup script: it pauses the API,
# dumps MySQL, mirrors the media buckets, writes checksums, then resumes the API.
# Output: ${UPSTREAM_DIR}/backups/<UTC timestamp>/. The S3 sidecar uploads it on its next run.
# Retention: set BACKUP_RETENTION_DAYS in ${UPSTREAM_DIR}/.env (off by default).
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
[ -x "${UPSTREAM_DIR}/scripts/backup.sh" ] || die "${UPSTREAM_DIR}/scripts/backup.sh not found; run scripts/bootstrap.sh first"
# Before the stack has been started once there is nothing to back up, and the upstream script
# would try to start (and therefore build) the database and storage services.
if [ -z "$(acc_compose ps -a -q mysql 2>/dev/null)" ]; then
  echo "stack has not been started yet; nothing to back up"
  exit 0
fi
exec "${UPSTREAM_DIR}/scripts/backup.sh" "$@"
