#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-${ROOT_DIR}/applebuild/mscore.app}"
shift $(( $# > 0 ? 1 : 0 ))

exec "${ROOT_DIR}/scripts/verify_macos_app.sh" \
  --app "$APP_PATH" \
  --arch arm64 \
  "$@"
