#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build.release}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${ROOT_DIR}/applebuild}"
ARCH="${OSX_ARCHITECTURES:-arm64}"
QT_MAJOR_VERSION="${QT_MAJOR_VERSION:-${MSCORE_QT_MAJOR_VERSION:-6}}"
QT_PREFIX="${QT_PREFIX:-}"
DEPLOYMENT_TARGET="${OSX_DEPLOYMENT_TARGET:-11.0}"
GENERATOR="${OSX_GENERATOR:-Unix Makefiles}"
VERSION="${MUSESCORE_PACKAGE_VERSION:-3.6.2}"
DOWNLOAD_SOUNDFONT="${DOWNLOAD_SOUNDFONT:-OFF}"
BUILD_WEBENGINE="${BUILD_WEBENGINE:-ON}"
BUILD_PCH="${BUILD_PCH:-ON}"
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
PACKAGE=1
CLEAN=0
CLEAN_ONLY=0
PACKAGE_ARGS=()
CMAKE_OSX_SYSROOT_ARGS=()
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
  --qt-major VERSION       Qt major version, 5 or 6. Default: ${QT_MAJOR_VERSION}
  -h, --help               Show this help.
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
    --qt-major)
      QT_MAJOR_VERSION="$2"
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

case "$QT_MAJOR_VERSION" in
  5|6) ;;
  *) echo "Qt major version must be 5 or 6; got: ${QT_MAJOR_VERSION}" >&2; exit 1 ;;
esac

if [[ "${CLEAN}" == "1" ]]; then
  rm -rf "${BUILD_DIR}" "${INSTALL_PREFIX}"

  if [[ "${CLEAN_ONLY}" == "1" ]]; then
    echo "MuseScore clean completed:"
    echo "  Build directory: ${BUILD_DIR}"
    echo "  Install prefix: ${INSTALL_PREFIX}"
    exit 0
  fi
fi

if [[ -z "$QT_PREFIX" ]] && command -v brew >/dev/null 2>&1; then
  if [[ "$QT_MAJOR_VERSION" == "6" ]]; then
    QT_FORMULA="qt"
  else
    QT_FORMULA="qt@5"
  fi
  if brew --prefix "$QT_FORMULA" >/dev/null 2>&1; then
    QT_PREFIX="$(brew --prefix "$QT_FORMULA")"
    export PATH="${QT_PREFIX}/bin:${PATH}"
    export CMAKE_PREFIX_PATH="${QT_PREFIX}:${CMAKE_PREFIX_PATH:-}"
  fi
fi

if [[ "$QT_MAJOR_VERSION" == "6" ]]; then
  QMAKE_BIN="$(command -v qmake6 2>/dev/null || command -v qmake 2>/dev/null || true)"
else
  QMAKE_BIN="$(command -v qmake 2>/dev/null || command -v qmake-qt5 2>/dev/null || true)"
fi
[[ -n "$QMAKE_BIN" ]] || { echo "Qt ${QT_MAJOR_VERSION} qmake is not in PATH; set QT_PREFIX" >&2; exit 1; }
QMAKE_VERSION="$("$QMAKE_BIN" -query QT_VERSION)"
[[ "$QMAKE_VERSION" == "$QT_MAJOR_VERSION".* ]] || { echo "$QMAKE_BIN reports Qt $QMAKE_VERSION, but Qt $QT_MAJOR_VERSION was requested" >&2; exit 1; }
QT_PREFIX="${QT_PREFIX:-$("$QMAKE_BIN" -query QT_INSTALL_PREFIX)}"

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
  -DMSCORE_QT_MAJOR_VERSION="${QT_MAJOR_VERSION}" \
  -DDOWNLOAD_SOUNDFONT="${DOWNLOAD_SOUNDFONT}" \
  -DBUILD_WEBENGINE="${BUILD_WEBENGINE}" \
  -DBUILD_PCH="${BUILD_PCH}" \
  -DBUILD_AUTOUPDATE=OFF \
  -DTELEMETRY_TRACK_ID="" \
  -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
  "${CMAKE_OSX_SYSROOT_ARGS[@]}"

cmake --build "${BUILD_DIR}" --target lrelease -- -j"${JOBS}"
cmake --build "${BUILD_DIR}" --target install -- -j"${JOBS}"

APP_PATH="${INSTALL_PREFIX}/mscore.app"
"${ROOT_DIR}/scripts/deploy_macos_app.sh" \
  --app "$APP_PATH" \
  --qt-prefix "$QT_PREFIX" \
  --qt-major "$QT_MAJOR_VERSION"

VERIFY_ARGS=(
  --app "$APP_PATH"
  --arch "$ARCH"
  --qt-major "$QT_MAJOR_VERSION"
)
"${ROOT_DIR}/scripts/verify_macos_app.sh" "${VERIFY_ARGS[@]}"

if [[ "${PACKAGE}" == "1" ]]; then
  "${ROOT_DIR}/scripts/package_macos_arm64.sh" --version "${VERSION}" "${PACKAGE_ARGS[@]}"
fi
