#!/usr/bin/env bash
# Prepare a Linux host for artcraft-cloud and optionally build and start the stack.
# Safe to re-run: every step checks before it changes anything.
#
#   sudo scripts/bootstrap.sh [options]
#
#   --install-docker     install Docker Engine + compose plugin from Docker's apt repo if missing
#   --docker-data-root   move Docker's data-root to ${DATA_DIR}/docker (dedicated hosts only:
#                        puts images, build cache and volumes on the data volume)
#   --swap-gb N          make sure a swap file of N GB exists at ${DATA_DIR}/swapfile
#   --build              build the images (compiles ArtCraft from source; can take an hour or more)
#   --start              start the stack and wait for it to become healthy
#   --force              build even when the host is below the recommended size
#
# Without --build/--start it only prepares the host: packages, kernel setting, upstream
# checkout at the pinned commit, generated secrets, .env, backup timer.
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

install_docker=false; data_root=false; swap_gb=0; build=false; start=false; force=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-docker) install_docker=true ;;
    --docker-data-root) data_root=true ;;
    --swap-gb) [ "$#" -ge 2 ] || die "--swap-gb needs a number"; swap_gb="$2"; shift ;;
    --build) build=true ;;
    --start) start=true ;;
    --force) force=true ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) die "unknown option $1" ;;
  esac
  shift
done
[[ "${swap_gb}" =~ ^[0-9]+$ ]] || die "--swap-gb must be a whole number"
[ "${EUID}" -eq 0 ] || die "run with sudo"
step() { echo; echo "==> $*"; }

step "host packages"
if command -v apt-get >/dev/null; then
  missing=()
  for p in git curl openssl; do command -v "$p" >/dev/null || missing+=("$p"); done
  if [ "${#missing[@]}" -gt 0 ]; then
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates "${missing[@]}"
  fi
else
  for p in git curl openssl; do command -v "$p" >/dev/null || die "$p is required"; done
fi

step "docker"
if ! command -v docker >/dev/null; then
  "${install_docker}" || die "Docker is missing. Install it or pass --install-docker."
  command -v apt-get >/dev/null || die "--install-docker supports apt-based systems only"
  # shellcheck disable=SC1091
  . /etc/os-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
docker compose version >/dev/null || die "the docker compose plugin is required"
systemctl enable --now docker >/dev/null 2>&1 || true

step "data directory ${DATA_DIR}"
mkdir -p "${DATA_DIR}"

if "${data_root}"; then
  step "docker data-root -> ${DATA_DIR}/docker"
  current="$(docker info --format '{{.DockerRootDir}}')"
  if [ "${current}" = "${DATA_DIR}/docker" ]; then
    echo "already set"
  elif [ -e /etc/docker/daemon.json ]; then
    die "/etc/docker/daemon.json already exists; add \"data-root\": \"${DATA_DIR}/docker\" to it yourself"
  else
    [ -z "$(docker ps -aq)" ] || die "containers already exist under ${current}; refusing to move the data-root"
    mkdir -p /etc/docker "${DATA_DIR}/docker"
    printf '{\n  "data-root": "%s/docker"\n}\n' "${DATA_DIR}" > /etc/docker/daemon.json
    systemctl restart docker
    echo "data-root is now $(docker info --format '{{.DockerRootDir}}')"
  fi

  # Recent Docker keeps images and build cache in containerd's own directory, not in the
  # data-root. Move that too, or the source build fills the root disk.
  if docker info --format '{{.DriverStatus}}' | grep -q 'io.containerd.snapshotter'; then
    step "containerd root -> ${DATA_DIR}/containerd"
    cfg=/etc/containerd/config.toml
    if grep -Eq "^root[[:space:]]*=[[:space:]]*\"${DATA_DIR}/containerd\"" "${cfg}" 2>/dev/null; then
      echo "already set"
    elif grep -Eq '^root[[:space:]]*=' "${cfg}" 2>/dev/null; then
      die "${cfg} already sets a root; point it at ${DATA_DIR}/containerd yourself"
    else
      [ -z "$(docker images -q)" ] || die "images already exist in containerd's current root; run 'docker system prune -af' first"
      mkdir -p /etc/containerd "${DATA_DIR}/containerd"
      touch "${cfg}"
      # A top-level key must come before any [table] header, so put it on the first line.
      sed -i "1i root = \"${DATA_DIR}/containerd\"" "${cfg}" 2>/dev/null || true
      [ -s "${cfg}" ] || echo "root = \"${DATA_DIR}/containerd\"" > "${cfg}"
      systemctl restart containerd
      systemctl restart docker
      echo "containerd root is now ${DATA_DIR}/containerd"
    fi
  fi
fi

if [ "${swap_gb}" -gt 0 ]; then
  step "swap (${swap_gb} GB at ${DATA_DIR}/swapfile)"
  swapfile="${DATA_DIR}/swapfile"
  if [ ! -e "${swapfile}" ]; then
    fallocate -l "${swap_gb}G" "${swapfile}"
    chmod 600 "${swapfile}"
    mkswap "${swapfile}" >/dev/null
  fi
  swapon --show=NAME --noheadings | grep -qx "${swapfile}" || swapon "${swapfile}"
  grep -q "^${swapfile} " /etc/fstab || echo "${swapfile} none swap sw,nofail 0 0" >> /etc/fstab
fi

step "kernel setting for Elasticsearch"
if [ "$(sysctl -n vm.max_map_count)" -lt 262144 ]; then
  echo 'vm.max_map_count=262144' > /etc/sysctl.d/99-artcraft.conf
  sysctl -q -p /etc/sysctl.d/99-artcraft.conf
fi

step "upstream template at the pinned commit"
repo="$(lock_value PERSONAL_SERVER_REPO)"; sha="$(lock_value PERSONAL_SERVER_SHA)"
[[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || die "PERSONAL_SERVER_SHA in UPSTREAM.lock is not a full commit SHA"
if [ ! -d "${UPSTREAM_DIR}/.git" ]; then
  git clone "${repo}" "${UPSTREAM_DIR}"
fi
git config --global --add safe.directory "${UPSTREAM_DIR}" 2>/dev/null || true
if [ "$(git -C "${UPSTREAM_DIR}" rev-parse HEAD)" != "${sha}" ]; then
  git -C "${UPSTREAM_DIR}" fetch origin
  git -C "${UPSTREAM_DIR}" checkout --detach "${sha}"
fi
[ "$(git -C "${UPSTREAM_DIR}" rev-parse HEAD)" = "${sha}" ] || die "upstream checkout is not at ${sha}"
mkdir -p "${UPSTREAM_DIR}/backups"
chmod 700 "${UPSTREAM_DIR}/backups"

step "secrets"
# Generated on this host, never printed, never overwritten. The script exits 1 when .env
# already existed, which is fine.
if [ ! -e "${UPSTREAM_DIR}/.env" ] || [ ! -e "${UPSTREAM_DIR}/config/providers.env" ]; then
  "${UPSTREAM_DIR}/scripts/generate-secrets.sh" || true
fi
[ -s "${UPSTREAM_DIR}/.env" ] || die "${UPSTREAM_DIR}/.env was not created"

step "settings"
if [ ! -e "${ENV_FILE}" ]; then
  (umask 077; cp "${REPO_DIR}/.env.example" "${ENV_FILE}")
  echo "created ${ENV_FILE} from .env.example"
fi
domain="$(env_get DOMAIN_NAME)"
if [ -n "${domain}" ]; then
  # Media links and the web build carry the browser-facing origin (see docs/security.md).
  want="WEBAPP_ORIGIN=https://${domain}"
  if ! grep -qx "${want}" "${UPSTREAM_DIR}/.env"; then
    sed -i -E "s|^WEBAPP_ORIGIN=.*|${want}|" "${UPSTREAM_DIR}/.env"
    echo "set ${want} (the webapp image must be rebuilt for this to take effect)"
  fi
fi

step "backup timer"
schedule="$(env_get BACKUP_SCHEDULE daily)"
if [ "${schedule}" = "off" ] || ! command -v systemctl >/dev/null; then
  echo "no timer installed"
else
  cat > /etc/systemd/system/artcraft-backup.service <<UNIT
[Unit]
Description=ArtCraft backup (MySQL dump + media mirror)
After=docker.service
Requires=docker.service
# Nothing to back up until the stack has been built and started once.
ConditionPathExists=${UPSTREAM_DIR}/.env

[Service]
Type=oneshot
ExecStart=${REPO_DIR}/scripts/backup.sh
UNIT
  cat > /etc/systemd/system/artcraft-backup.timer <<UNIT
[Unit]
Description=Run the ArtCraft backup (${schedule})

[Timer]
OnCalendar=${schedule}
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
UNIT
  systemctl daemon-reload
  systemctl enable --now artcraft-backup.timer >/dev/null
  echo "artcraft-backup.timer: ${schedule}"
fi

step "compose configuration"
acc_compose config --quiet
echo "valid (s3 sync: $(s3_enabled && echo on || echo off), public https: $(caddy_enabled && echo on || echo off))"

if "${build}"; then
  step "size check"
  mem_gb=$(( ( $(awk '/MemTotal/ {print $2}' /proc/meminfo) + $(awk '/SwapTotal/ {print $2}' /proc/meminfo) ) / 1024 / 1024 ))
  disk_gb=$(( $(df -Pk "$(docker info --format '{{.DockerRootDir}}')" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
  echo "RAM+swap: ${mem_gb} GB, free disk for Docker: ${disk_gb} GB, CPUs: $(nproc)"
  if [ "${mem_gb}" -lt 15 ] || [ "${disk_gb}" -lt 40 ]; then
    msg="upstream asks for 8 GB RAM + 8 GB swap and 40 GB free disk to build"
    "${force}" || die "${msg}. Add swap/disk, use a bigger machine for the build, or pass --force."
    echo "WARNING: ${msg}; continuing because of --force"
  fi
  step "build (this compiles Rust, Go and the web app; expect an hour or more)"
  acc_compose build
fi

if "${start}"; then
  step "start"
  acc_compose up -d --wait --wait-timeout 900
  acc_compose ps
fi

echo
echo "done. Next: scripts/compose.sh ps   |   docs: README.md"
