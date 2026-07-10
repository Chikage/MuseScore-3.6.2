#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-build}"

for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [[ -x "${_brew}" ]]; then
    export PATH="$(dirname "${_brew}"):${PATH}"
    break
  fi
done

if [[ "${ACTION:-}" == "clean" && "${MODE}" == "build" ]]; then
  MODE="clean"
fi

export BUILD_DIR="${MUSESCORE_CMAKE_BUILD_DIR:-${ROOT_DIR}/build.release}"
export INSTALL_PREFIX="${MUSESCORE_INSTALL_PREFIX:-${ROOT_DIR}/applebuild}"
export OSX_ARCHITECTURES="arm64"
export OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
export OSX_GENERATOR="${OSX_GENERATOR:-Unix Makefiles}"

case "${MODE}" in
  build)
    "${ROOT_DIR}/scripts/build_macos_arm64.sh" --skip-package
    ;;
  package)
    "${ROOT_DIR}/scripts/build_macos_arm64.sh" --skip-sign
    ;;
  clean)
    rm -rf "${BUILD_DIR}" "${INSTALL_PREFIX}"
    ;;
  *)
    echo "Usage: $0 [build|package|clean]" >&2
    exit 2
    ;;
esac
