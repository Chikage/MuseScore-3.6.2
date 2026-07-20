#!/usr/bin/env bash
set -Eeuo pipefail

CACHE_DIR="${CCACHE_DIR:-${HOME}/Library/Caches/ccache}"
MAX_SIZE="${CCACHE_MAXSIZE:-20G}"
INSTALL=1

usage() {
  cat <<'EOF'
Usage: scripts/setup_ccache_macos.sh [options]

Install and configure ccache for the MuseScore macOS build scripts.

Options:
  --cache-dir DIR  Cache directory. Default: ~/Library/Caches/ccache
  --max-size SIZE  Maximum cache size. Default: 20G
  --no-install     Fail instead of installing ccache when it is missing
  -h, --help       Show this help

Environment:
  CCACHE_DIR       Default cache directory
  CCACHE_MAXSIZE   Default maximum cache size
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cache-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      CACHE_DIR="$2"
      shift 2
      ;;
    --max-size)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      MAX_SIZE="$2"
      shift 2
      ;;
    --no-install)
      INSTALL=0
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
[[ -n "$CACHE_DIR" ]] || die "cache directory must not be empty"
[[ -n "$MAX_SIZE" ]] || die "maximum cache size must not be empty"

if ! command -v ccache >/dev/null 2>&1; then
  [[ "$INSTALL" == "1" ]] || die "ccache is not installed"
  command -v brew >/dev/null 2>&1 || die "Homebrew is required to install ccache; see https://brew.sh/"

  echo "==> Installing ccache"
  brew install ccache
fi

CCACHE_BIN="$(command -v ccache)"
mkdir -p "$CACHE_DIR"
export CCACHE_DIR="$CACHE_DIR"

echo "==> Configuring ccache"
"$CCACHE_BIN" --set-config "cache_dir=$CACHE_DIR"
"$CCACHE_BIN" --set-config "max_size=$MAX_SIZE"
"$CCACHE_BIN" --set-config "compression=true"

echo
echo "ccache is ready:"
echo "  Executable: $CCACHE_BIN"
echo "  Cache directory: $CACHE_DIR"
echo "  Maximum size: $MAX_SIZE"
echo
echo "The macOS build scripts will detect it automatically. Run:"
echo "  ./build-macos.sh"
echo
"$CCACHE_BIN" --show-stats
