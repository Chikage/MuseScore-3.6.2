#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${MUSESCORE_PACKAGE_VERSION:-3.6.2}"
JOBS=""
CLEAN=0
SIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:-}"

usage() {
  cat <<EOF
Usage: ./build_signed_dmg.sh [options]

Build MuseScore for macOS ARM64, sign the app bundle during packaging, then sign
and verify the final DMG.

Options:
  --sign-identity NAME     Codesign identity. Default: auto-detect.
  --version VERSION        Package version. Default: ${VERSION}
  --jobs N                 Parallel build jobs.
  --clean                  Remove build.release and applebuild before building.
  -h, --help               Show this help.

Environment:
  MACOS_CODESIGN_IDENTITY  Same as --sign-identity.
  MUSESCORE_PACKAGE_VERSION Same as --version.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign-identity|--sign_identity)
      SIGN_IDENTITY="$2"
      shift
      ;;
    --version)
      VERSION="$2"
      shift
      ;;
    --jobs)
      JOBS="$2"
      shift
      ;;
    --clean)
      CLEAN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must be run on macOS." >&2
  exit 1
fi

find_identity() {
  local pattern="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n "/${pattern}/s/^[^\"]*\"\(.*\)\"$/\1/p" \
    | head -n 1
}

if [[ -z "${SIGN_IDENTITY}" ]]; then
  SIGN_IDENTITY="$(find_identity 'Developer ID Application:')"
fi
if [[ -z "${SIGN_IDENTITY}" ]]; then
  SIGN_IDENTITY="$(find_identity 'Apple Distribution:')"
fi
if [[ -z "${SIGN_IDENTITY}" ]]; then
  SIGN_IDENTITY="$(find_identity 'Apple Development:')"
fi

if [[ -z "${SIGN_IDENTITY}" ]]; then
  echo "No valid codesigning identity found." >&2
  echo "Install a signing certificate or pass --sign-identity \"...\"." >&2
  exit 1
fi

if [[ "${SIGN_IDENTITY}" != Developer\ ID\ Application:* ]]; then
  echo "Warning: using '${SIGN_IDENTITY}'." >&2
  echo "For public distribution, use a Developer ID Application certificate." >&2
fi

BUILD_ARGS=(--version "${VERSION}" --sign-identity "${SIGN_IDENTITY}")
if [[ "${CLEAN}" == "1" ]]; then
  BUILD_ARGS=(--clean "${BUILD_ARGS[@]}")
fi
if [[ -n "${JOBS}" ]]; then
  BUILD_ARGS+=(--jobs "${JOBS}")
fi

export OSX_ARCHITECTURES="arm64"
export OSX_DEPLOYMENT_TARGET="${OSX_DEPLOYMENT_TARGET:-11.0}"
export MUSESCORE_PACKAGE_VERSION="${VERSION}"

"${ROOT_DIR}/scripts/build_macos_arm64.sh" "${BUILD_ARGS[@]}"

DMG="${ROOT_DIR}/applebuild/MuseScore-${VERSION}.dmg"
if [[ ! -f "${DMG}" ]]; then
  echo "Expected DMG was not created: ${DMG}" >&2
  exit 1
fi

echo "Signing DMG: ${DMG}"
codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG}"

echo "Verifying DMG signature"
codesign --verify --verbose=2 "${DMG}"
spctl --assess --type open --verbose "${DMG}" || {
  echo "spctl assessment did not accept the DMG. Codesign verification passed, but notarization may still be required for distribution." >&2
}

echo "Signed DMG created:"
echo "  ${DMG}"
