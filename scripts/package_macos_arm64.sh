#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${MUSESCORE_PACKAGE_VERSION:-3.6.2}"
PACKAGE_ARGS=()

usage() {
  cat <<EOF
Usage: scripts/package_macos_arm64.sh [options]

Options:
  --skip-sign              Package without code signing.
  --sign-identity NAME     Developer ID Application identity for codesign.
  --version VERSION        Package version. Default: ${VERSION}
  -h, --help               Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-sign|--skip_sign)
      PACKAGE_ARGS+=(--skip_sign)
      ;;
    --sign-identity|--sign_identity)
      PACKAGE_ARGS+=(--sign_identity "$2")
      shift
      ;;
    --version)
      VERSION="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

APP_BIN="${ROOT_DIR}/applebuild/mscore.app/Contents/MacOS/mscore"
if [[ ! -f "${APP_BIN}" ]]; then
  echo "Missing ${APP_BIN}. Run scripts/build_macos_arm64.sh first." >&2
  exit 1
fi

if [[ "$(lipo -archs "${APP_BIN}")" != "arm64" ]]; then
  echo "Expected arm64 app binary, got: $(lipo -archs "${APP_BIN}")" >&2
  exit 1
fi

if command -v brew >/dev/null 2>&1 && brew --prefix qt@5 >/dev/null 2>&1; then
  QT_PREFIX="${QT_PREFIX:-$(brew --prefix qt@5)}"
  export QT_PREFIX
  export PATH="${QT_PREFIX}/bin:${PATH}"
fi

if [[ ! -x "${QT_PREFIX:-}/bin/macdeployqt" ]]; then
  echo "Qt 5 macdeployqt was not found; set QT_PREFIX to the Qt 5 installation" >&2
  exit 1
fi

export MACDEPLOYQT="${QT_PREFIX}/bin/macdeployqt"

(
  cd "${ROOT_DIR}"
  build/package_mac --version "${VERSION}" "${PACKAGE_ARGS[@]}"
)

DMG="${ROOT_DIR}/applebuild/MuseScore-${VERSION}.dmg"
if [[ -f "${DMG}" ]]; then
  echo "Created ${DMG}"
fi
