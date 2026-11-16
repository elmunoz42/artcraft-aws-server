#!/usr/bin/env bash
# Pull a backup from the S3 bucket back to disk, and optionally restore it.
#
#   scripts/restore-from-s3.sh --list               list backups in the bucket
#   scripts/restore-from-s3.sh                      download the newest backup
#   scripts/restore-from-s3.sh 20261116T031500Z     download a specific backup
#   scripts/restore-from-s3.sh --apply [TIMESTAMP]  download, then OVERWRITE the database and media
#
# For recovery or for moving to a new instance: run scripts/bootstrap.sh --build --start on
# the new host first so the stack exists, then run this with --apply.
# Uses the same image and credentials as the sync sidecar, so no AWS CLI is needed on the host.
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

apply=false; list=false; ts=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) apply=true ;;
    --list) list=true ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) ts="$1" ;;
  esac
  shift
done

bucket="$(env_get S3_BUCKET)"
[ -n "${bucket}" ] || die "S3_BUCKET is not set in ${ENV_FILE}"
prefix="$(env_get S3_PREFIX backups)"; prefix="${prefix#/}"; prefix="${prefix%/}"
base="s3://${bucket}/${prefix:+${prefix}/}"
region="$(env_get AWS_REGION)"
image="artcraft-cloud/s3-sync:local"
docker image inspect "${image}" >/dev/null 2>&1 \
  || docker build -q -t "${image}" --build-arg "AWS_CLI_IMAGE=$(lock_value AWS_CLI_IMAGE)" "${REPO_DIR}/docker/s3-sync" >/dev/null

backups_dir="${UPSTREAM_DIR}/backups"
mkdir -p "${backups_dir}"

aws_run() {
  local envargs=()
  [ -n "${region}" ] && envargs+=(-e "AWS_DEFAULT_REGION=${region}")
  [ -n "$(env_get AWS_ACCESS_KEY_ID)" ] && envargs+=(-e "AWS_ACCESS_KEY_ID=$(env_get AWS_ACCESS_KEY_ID)" -e "AWS_SECRET_ACCESS_KEY=$(env_get AWS_SECRET_ACCESS_KEY)")
  docker run --rm --entrypoint aws "${envargs[@]}" -v "${backups_dir}:/backups" "${image}" "$@"
}

available() { aws_run s3 ls "${base}" | awk '$1 == "PRE" {sub("/$", "", $2); print $2}' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort || true; }

if "${list}"; then available; exit 0; fi

if [ -z "${ts}" ]; then
  ts="$(available | tail -n1)"
  [ -n "${ts}" ] || die "no backups found under ${base}"
  echo "newest backup in the bucket: ${ts}"
fi
[[ "${ts}" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "not a backup timestamp: ${ts}"

echo "downloading ${base}${ts}/ -> ${backups_dir}/${ts}/"
aws_run s3 sync "${base}${ts}/" "/backups/${ts}/" --no-progress --only-show-errors
[ -f "${backups_dir}/${ts}/SHA256SUMS" ] || die "download is incomplete: ${backups_dir}/${ts}/SHA256SUMS is missing"
# S3 does not store empty directories, but the upstream restore requires one per bucket.
for b in artcraft-private artcraft-public artcraft-public-gc; do mkdir -p "${backups_dir}/${ts}/minio/${b}"; done
echo "downloaded to ${backups_dir}/${ts}"

if "${apply}"; then
  [ -x "${UPSTREAM_DIR}/scripts/restore.sh" ] || die "${UPSTREAM_DIR}/scripts/restore.sh not found; run scripts/bootstrap.sh first"
  # The upstream script verifies checksums, asks for confirmation, then overwrites the
  # database and media buckets. Set RESTORE_CONFIRM=restore to skip the prompt.
  exec "${UPSTREAM_DIR}/scripts/restore.sh" "${backups_dir}/${ts}"
fi
echo "not restored. To restore: $0 --apply ${ts}"
