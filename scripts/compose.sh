#!/usr/bin/env bash
# docker compose for this stack, with the S3 and Caddy add-ons applied according to .env.
#   scripts/compose.sh ps
#   scripts/compose.sh logs -f storyteller-web
#   scripts/compose.sh up -d
set -Eeuo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
acc_compose "$@"
