#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build.release}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${ROOT_DIR}/applebuild}"
ARCH="${OSX_ARCHITECTURES:-arm64}"
DEPLOYMENT_TARGET="${OSX_DEPLOYMENT_TARGET:-11.0}"
GENERATOR="${OSX_GENERATOR:-Unix Makefiles}"
VERSION="${MUSESCORE_PACKAGE_VERSION:-3.6.2}"
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
PACKAGE=1
CLEAN=0
CLEAN_ONLY=0
PACKAGE_ARGS=()
CMAKE_OSX_SYSROOT_ARGS=()
CMAKE_LAUNCHER_ARGS=()
USE_CCACHE="${MUSESCORE_USE_CCACHE:-auto}"
SCRIPT_START_TIME=$SECONDS

usage() {
  cat <<EOF
Usage: scripts/build_macos_arm64.sh [options]

Options:
  --clean                  Remove build.release and applebuild before building.
  --clean-only             Remove build.release and applebuild and exit.
  --skip-package           Build applebuild/mscore.app only, do not create DMG.
  --skip-sign              Package without code signing.
  --sign-identity NAME     Developer ID Application identity for codesign.
  --version VERSION        Package version. Default: ${VERSION}
  --jobs N                 Parallel build jobs. Default: ${JOBS}
  -h, --help               Show this help.

Environment:
  MUSESCORE_USE_CCACHE     auto, ON, or OFF. Default: auto
EOF
}

print_elapsed_time() {
  local elapsed=$((SECONDS - SCRIPT_START_TIME))
  local hours=$((elapsed / 3600))
  local minutes=$(((elapsed % 3600) / 60))
  local seconds=$((elapsed % 60))

  printf '\nTotal elapsed time: %02d:%02d:%02d\n' "$hours" "$minutes" "$seconds"
}

trap print_elapsed_time EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN=1
      ;;
    --clean-only)
      CLEAN=1
      CLEAN_ONLY=1
      ;;
    --skip-package)
      PACKAGE=0
      ;;
    --skip-sign)
      PACKAGE_ARGS+=(--skip_sign)
      ;;
    --sign-identity)
      PACKAGE_ARGS+=(--sign_identity "$2")
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

if [[ "${ARCH}" != "arm64" ]]; then
  echo "This standalone project is configured for macOS arm64; got: ${ARCH}" >&2
  exit 1
fi

if [[ "${CLEAN}" == "1" ]]; then
  rm -rf "${BUILD_DIR}" "${INSTALL_PREFIX}"

  if [[ "${CLEAN_ONLY}" == "1" ]]; then
    echo "MuseScore clean completed:"
    echo "  Build directory: ${BUILD_DIR}"
    echo "  Install prefix: ${INSTALL_PREFIX}"
    exit 0
  fi
fi

if command -v brew >/dev/null 2>&1 && brew --prefix qt@5 >/dev/null 2>&1; then
  QT_PREFIX="$(brew --prefix qt@5)"
  export PATH="${QT_PREFIX}/bin:${PATH}"
  export CMAKE_PREFIX_PATH="${QT_PREFIX}:${CMAKE_PREFIX_PATH:-}"
fi

case "${USE_CCACHE}" in
  auto|AUTO|Auto)
    if command -v ccache >/dev/null 2>&1; then
      CCACHE_BIN="$(command -v ccache)"
    fi
    ;;
  1|ON|on|TRUE|true|YES|yes)
    if ! command -v ccache >/dev/null 2>&1; then
      echo "ccache is not installed; run scripts/setup_ccache_macos.sh" >&2
      exit 1
    fi
    CCACHE_BIN="$(command -v ccache)"
    ;;
  0|OFF|off|FALSE|false|NO|no)
    CCACHE_BIN=""
    ;;
  *)
    echo "MUSESCORE_USE_CCACHE must be auto, ON, or OFF; got: ${USE_CCACHE}" >&2
    exit 1
    ;;
esac

CCACHE_BIN="${CCACHE_BIN:-}"
CMAKE_LAUNCHER_ARGS=(
  -DCMAKE_C_COMPILER_LAUNCHER="${CCACHE_BIN}"
  -DCMAKE_CXX_COMPILER_LAUNCHER="${CCACHE_BIN}"
)

if [[ -n "${CCACHE_BIN}" ]]; then
  echo "Using ccache: ${CCACHE_BIN}"
fi

sign_resource_macho_files() {
  local resources_dir="$1"

  if [[ ! -d "${resources_dir}" ]]; then
    return
  fi

  while IFS= read -r -d '' f; do
    if file "${f}" | grep -q "Mach-O"; then
      codesign --force --sign - "${f}"
    fi
  done < <(find "${resources_dir}" -type f -print0)
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  OSX_SYSROOT="${OSX_SYSROOT:-$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)}"
  if [[ -n "${OSX_SYSROOT}" ]]; then
    export SDKROOT="${OSX_SYSROOT}"
    CMAKE_OSX_SYSROOT_ARGS=(-DCMAKE_OSX_SYSROOT="${OSX_SYSROOT}")
  fi
fi

cmake -S "${ROOT_DIR}" -B "${BUILD_DIR}" -G "${GENERATOR}" \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
  -DCMAKE_BUILD_TYPE=RELEASE \
  -DCMAKE_BUILD_NUMBER="" \
  -DMUSESCORE_BUILD_CONFIG="dev" \
  -DMUSESCORE_REVISION="" \
  -DTELEMETRY_TRACK_ID="" \
  -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
  "${CMAKE_OSX_SYSROOT_ARGS[@]}" \
  "${CMAKE_LAUNCHER_ARGS[@]}"

cmake --build "${BUILD_DIR}" --target lrelease -- -j"${JOBS}"
cmake --build "${BUILD_DIR}" --target install -- -j"${JOBS}"

# Seal the install-tree app with an ad-hoc signature. On Apple Silicon, an
# unsealed bundle can be killed at launch with CODESIGNING Invalid Page even
# when it is only intended for local testing.
codesign --force --deep --sign - "${INSTALL_PREFIX}/mscore.app"
sign_resource_macho_files "${INSTALL_PREFIX}/mscore.app/Contents/Resources"
codesign --force --sign - "${INSTALL_PREFIX}/mscore.app"

"${ROOT_DIR}/scripts/verify_macos_arm64.sh" "${INSTALL_PREFIX}/mscore.app"

if [[ "${PACKAGE}" == "1" ]]; then
  "${ROOT_DIR}/scripts/package_macos_arm64.sh" --version "${VERSION}" "${PACKAGE_ARGS[@]}"
fi

if [[ -n "${CCACHE_BIN}" ]]; then
  echo
  "${CCACHE_BIN}" --show-stats
fi
