#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This setup script is for macOS only." >&2
  exit 1
fi

echo "==> Checking Xcode command line tools"
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode command line tools are not selected. Install Xcode, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi
xcodebuild -version

echo "==> Checking Homebrew"
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it from https://brew.sh/ and re-run this script." >&2
  exit 1
fi

echo "==> Installing build dependencies"
brew install cmake pkgconf qt@5 jack lame libogg libvorbis flac libsndfile portaudio wget p7zip

QT_PREFIX="$(brew --prefix qt@5)"

cat <<EOF

Setup complete.

Use these environment variables in new shells before building:

  export PATH="${QT_PREFIX}/bin:\$PATH"
  export CMAKE_PREFIX_PATH="${QT_PREFIX}:\${CMAKE_PREFIX_PATH:-}"

Or run:

  scripts/build_macos_arm64.sh --skip-sign

EOF
