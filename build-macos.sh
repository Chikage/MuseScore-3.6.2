#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH="${OSX_ARCHITECTURES:-$(uname -m)}"
CONFIGURATION="${MUSESCORE_CONFIGURATION:-release}"
DEPLOYMENT_TARGET="${OSX_DEPLOYMENT_TARGET:-}"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"
BUILD_DIR=""
INSTALL_PREFIX=""
CLEAN=0
CLEAN_ONLY=0
SKIP_SIGN=0

usage() {
  cat <<'EOF'
Usage: ./build-macos.sh [options]

Build and install MuseScore 3.6.2 on macOS.

Options:
  --arch ARCH              host, arm64, or x86_64. Default: host
  --debug                  Build Debug instead of Release
  --clean                  Remove the selected build and install directories
  --clean-only             Remove the selected build and install directories and exit
  --jobs N                 Parallel build jobs
  --build-dir DIR          Override the CMake build directory
  --install-prefix DIR     Override the install directory
  --deployment-target VER  Override CMAKE_OSX_DEPLOYMENT_TARGET
  --skip-sign              Do not ad-hoc sign the installed app
  -h, --help               Show this help

Environment:
  QT_PREFIX                Qt 5 installation prefix
  OSX_ARCHITECTURES        Default architecture
  OSX_DEPLOYMENT_TARGET    Default deployment target
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

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

BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build.macos-${ARCH}-${CONFIGURATION}}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${ROOT_DIR}/build.artifacts/macos/${ARCH}/${CONFIGURATION}}"

if [[ -z "${QT_PREFIX:-}" ]] && command -v brew >/dev/null 2>&1; then
  QT_PREFIX="$(brew --prefix qt@5 2>/dev/null || true)"
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
command -v qmake >/dev/null 2>&1 || die "Qt 5 qmake is not in PATH; set QT_PREFIX"
command -v xcrun >/dev/null 2>&1 || die "Xcode command line tools are not installed"

mkdir -p "$BUILD_DIR" "$INSTALL_PREFIX"

OSX_SYSROOT="${OSX_SYSROOT:-$(xcrun --sdk macosx --show-sdk-path)}"

cmake -S "$ROOT_DIR" -B "$BUILD_DIR" -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_NUMBER="0" \
  -DMUSESCORE_BUILD_CONFIG="$CONFIGURATION" \
  -DMUSESCORE_REVISION="" \
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

if [[ "$SKIP_SIGN" == "0" ]] && command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_PATH"
fi

echo
echo "MuseScore build completed:"
echo "  Architecture: $ARCH"
echo "  Configuration: $CMAKE_BUILD_TYPE"
echo "  Application: $APP_PATH"
