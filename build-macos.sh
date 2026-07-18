#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH="${OSX_ARCHITECTURES:-$(uname -m)}"
CONFIGURATION="${MUSESCORE_CONFIGURATION:-release}"
BUILD_CONFIG="${MUSESCORE_BUILD_CONFIG:-dev}"
QT_MAJOR_VERSION="${QT_MAJOR_VERSION:-${MSCORE_QT_MAJOR_VERSION:-6}}"
DEPLOYMENT_TARGET="${OSX_DEPLOYMENT_TARGET:-}"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"
BUILD_DIR=""
INSTALL_PREFIX=""
CLEAN=0
CLEAN_ONLY=0
SKIP_SIGN=0
SCRIPT_START_TIME=$SECONDS

usage() {
  cat <<'EOF'
Usage: ./build-macos.sh [options]

Build and install MuseScore 3.6.2 on macOS.

Options:
  --arch ARCH              host, arm64, or x86_64. Default: host
  --debug                  Build Debug instead of Release
  --build-config CONFIG    Product channel: dev, testing, or release
  --clean                  Remove the selected build and install directories
  --clean-only             Remove the selected build and install directories and exit
  --jobs N                 Parallel build jobs
  --build-dir DIR          Override the CMake build directory
  --install-prefix DIR     Override the install directory
  --deployment-target VER  Override CMAKE_OSX_DEPLOYMENT_TARGET
  --qt-major VERSION       Qt major version, 5 or 6
  --skip-sign              Do not ad-hoc sign the installed app
  -h, --help               Show this help

Environment:
  QT_MAJOR_VERSION         Qt major version, 5 or 6 (default: 6)
  MUSESCORE_BUILD_CONFIG   Product channel (default: dev)
  QT_PREFIX                Selected Qt installation prefix
  OSX_ARCHITECTURES        Default architecture
  OSX_DEPLOYMENT_TARGET    Default deployment target
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
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
    --arch)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      ARCH="$2"
      shift 2
      ;;
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    --build-config)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      BUILD_CONFIG="$2"
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --clean-only)
      CLEAN=1
      CLEAN_ONLY=1
      shift
      ;;
    --jobs)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      JOBS="$2"
      shift 2
      ;;
    --build-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      BUILD_DIR="$2"
      shift 2
      ;;
    --install-prefix)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      INSTALL_PREFIX="$2"
      shift 2
      ;;
    --deployment-target)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      DEPLOYMENT_TARGET="$2"
      shift 2
      ;;
    --qt-major)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      QT_MAJOR_VERSION="$2"
      shift 2
      ;;
    --skip-sign)
      SKIP_SIGN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "this script must run on macOS"

case "$QT_MAJOR_VERSION" in
  5|6) ;;
  *) die "Qt major version must be 5 or 6" ;;
esac

case "$ARCH" in
  host)
    ARCH="$(uname -m)"
    ;;
  aarch64)
    ARCH="arm64"
    ;;
  amd64)
    ARCH="x86_64"
    ;;
esac

case "$ARCH" in
  arm64)
    : "${DEPLOYMENT_TARGET:=11.0}"
    ;;
  x86_64)
    : "${DEPLOYMENT_TARGET:=10.10}"
    ;;
  *)
    die "unsupported architecture: $ARCH"
    ;;
esac

case "$CONFIGURATION" in
  release|Release|RELEASE)
    CONFIGURATION="release"
    CMAKE_BUILD_TYPE="RELEASE"
    ;;
  debug|Debug|DEBUG)
    CONFIGURATION="debug"
    CMAKE_BUILD_TYPE="DEBUG"
    ;;
  *)
    die "unsupported configuration: $CONFIGURATION"
    ;;
esac

case "$BUILD_CONFIG" in
  dev|testing|release) ;;
  *) die "unsupported product build config: $BUILD_CONFIG" ;;
esac

BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build.macos-qt${QT_MAJOR_VERSION}-${ARCH}-${CONFIGURATION}}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${ROOT_DIR}/build.artifacts/macos/qt${QT_MAJOR_VERSION}/${ARCH}/${CONFIGURATION}}"

if [[ -z "${QT_PREFIX:-}" ]] && command -v brew >/dev/null 2>&1; then
  if [[ "$QT_MAJOR_VERSION" == "6" ]]; then
    QT_PREFIX="$(brew --prefix qt 2>/dev/null || true)"
  else
    QT_PREFIX="$(brew --prefix qt@5 2>/dev/null || true)"
  fi
fi

if [[ -n "${QT_PREFIX:-}" ]]; then
  export PATH="${QT_PREFIX}/bin:${PATH}"
  export CMAKE_PREFIX_PATH="${QT_PREFIX}:${CMAKE_PREFIX_PATH:-}"
fi

if [[ "$CLEAN" == "1" ]]; then
  rm -rf "$BUILD_DIR" "$INSTALL_PREFIX"

  if [[ "$CLEAN_ONLY" == "1" ]]; then
    echo
    echo "MuseScore clean completed:"
    echo "  Build directory: $BUILD_DIR"
    echo "  Install prefix: $INSTALL_PREFIX"
    exit 0
  fi
fi

command -v cmake >/dev/null 2>&1 || die "cmake is not installed"
if [[ "$QT_MAJOR_VERSION" == "6" ]]; then
  QMAKE_BIN="$(command -v qmake6 2>/dev/null || command -v qmake 2>/dev/null || true)"
else
  QMAKE_BIN="$(command -v qmake 2>/dev/null || command -v qmake-qt5 2>/dev/null || true)"
fi
[[ -n "$QMAKE_BIN" ]] || die "Qt $QT_MAJOR_VERSION qmake is not in PATH; set QT_PREFIX"
QMAKE_VERSION="$("$QMAKE_BIN" -query QT_VERSION)"
[[ "$QMAKE_VERSION" == "$QT_MAJOR_VERSION".* ]] || die "$QMAKE_BIN reports Qt $QMAKE_VERSION, but Qt $QT_MAJOR_VERSION was requested"
QT_PREFIX="${QT_PREFIX:-$("$QMAKE_BIN" -query QT_INSTALL_PREFIX)}"
command -v xcrun >/dev/null 2>&1 || die "Xcode command line tools are not installed"

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"

OSX_SYSROOT="${OSX_SYSROOT:-$(xcrun --sdk macosx --show-sdk-path)}"

cmake -S "$ROOT_DIR" -B "$BUILD_DIR" -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_NUMBER="0" \
  -DMUSESCORE_BUILD_CONFIG="$BUILD_CONFIG" \
  -DMUSESCORE_REVISION="" \
  -DMSCORE_QT_MAJOR_VERSION="$QT_MAJOR_VERSION" \
  -DTELEMETRY_TRACK_ID="" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DCMAKE_OSX_SYSROOT="$OSX_SYSROOT"

cmake --build "$BUILD_DIR" --target lrelease -- -j"$JOBS"
cmake --build "$BUILD_DIR" --target install -- -j"$JOBS"

APP_PATH="$INSTALL_PREFIX/mscore.app"
BINARY_PATH="$APP_PATH/Contents/MacOS/mscore"

[[ -x "$BINARY_PATH" ]] || die "expected application binary was not produced: $BINARY_PATH"

if command -v lipo >/dev/null 2>&1; then
  APP_ARCHES="$(lipo -archs "$BINARY_PATH")"
  case " $APP_ARCHES " in
    *" $ARCH "*) ;;
    *) die "built binary architecture '$APP_ARCHES' does not contain '$ARCH'" ;;
  esac
fi

DEPLOY_ARGS=(
  --app "$APP_PATH"
  --qt-prefix "$QT_PREFIX"
  --qt-major "$QT_MAJOR_VERSION"
)
VERIFY_ARGS=(
  --app "$APP_PATH"
  --arch "$ARCH"
  --qt-major "$QT_MAJOR_VERSION"
)

if [[ "$CONFIGURATION" == "debug" ]]; then
  DEPLOY_ARGS+=(--no-strip)
fi

if [[ "$SKIP_SIGN" == "1" ]]; then
  DEPLOY_ARGS+=(--skip-sign)
  VERIFY_ARGS+=(--skip-signature)
fi

"$ROOT_DIR/scripts/deploy_macos_app.sh" "${DEPLOY_ARGS[@]}"
"$ROOT_DIR/scripts/verify_macos_app.sh" "${VERIFY_ARGS[@]}"

echo
echo "MuseScore build completed:"
echo "  Architecture: $ARCH"
echo "  Configuration: $CMAKE_BUILD_TYPE"
echo "  Product build config: $BUILD_CONFIG"
echo "  Application: $APP_PATH"
