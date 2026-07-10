#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-applebuild/mscore.app}"
APP_BIN="${APP_PATH}/Contents/MacOS/mscore"

if [[ ! -f "${APP_BIN}" ]]; then
  echo "Missing app binary: ${APP_BIN}" >&2
  exit 1
fi

ARCHS="$(lipo -archs "${APP_BIN}")"
echo "Binary architectures: ${ARCHS}"

if [[ "${ARCHS}" != "arm64" ]]; then
  echo "Expected arm64 binary." >&2
  exit 1
fi

file "${APP_BIN}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
MACHO_COUNT=0
while IFS= read -r -d '' f; do
  if file "${f}" | grep -q "Mach-O"; then
    codesign --verify --strict --verbose=2 "${f}"
    MACHO_COUNT=$((MACHO_COUNT + 1))
  fi
done < <(find "${APP_PATH}/Contents" -type f -print0)
echo "Verified Mach-O files: ${MACHO_COUNT}"
echo "Verification passed."
