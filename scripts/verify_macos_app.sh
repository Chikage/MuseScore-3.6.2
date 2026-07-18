#!/usr/bin/env bash
set -euo pipefail

APP_PATH=""
EXPECTED_ARCH=""
EXPECTED_QT_MAJOR=""
VERIFY_SIGNATURE=1

usage() {
  cat <<'EOF'
Usage: scripts/verify_macos_app.sh --app APP [options]

Options:
  --app APP              Application bundle to verify.
  --arch ARCH            Required architecture, for example arm64 or x86_64.
  --qt-major VERSION     Expected Qt major version, 5 or 6.
  --skip-signature       Do not require code signatures.
  -h, --help             Show this help.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      APP_PATH="$2"
      shift 2
      ;;
    --arch)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      EXPECTED_ARCH="$2"
      shift 2
      ;;
    --qt-major)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      EXPECTED_QT_MAJOR="$2"
      shift 2
      ;;
    --skip-signature)
      VERIFY_SIGNATURE=0
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
[[ -n "$APP_PATH" ]] || die "--app is required"

CONTENTS_PATH="$APP_PATH/Contents"
APP_BIN="$CONTENTS_PATH/MacOS/mscore"
APP_BIN_DIR="$CONTENTS_PATH/MacOS"

[[ -x "$APP_BIN" ]] || die "missing app binary: $APP_BIN"
[[ -d "$CONTENTS_PATH/Resources/workspaces" ]] || die "missing installed workspaces"
[[ -d "$CONTENTS_PATH/Resources/fonts" ]] || die "missing installed fonts"
[[ -d "$CONTENTS_PATH/Resources/templates" ]] || die "missing installed templates"
[[ -f "$CONTENTS_PATH/Resources/qt.conf" ]] || die "missing macdeployqt qt.conf"
[[ -d "$CONTENTS_PATH/Frameworks/QtCore.framework" ]] || die "missing deployed QtCore.framework"
[[ -f "$CONTENTS_PATH/PlugIns/platforms/libqcocoa.dylib" ]] || die "missing Cocoa platform plugin"

case "$EXPECTED_QT_MAJOR" in
  ""|5|6) ;;
  *) die "Qt major version must be 5 or 6" ;;
esac

FAILURES=0
MACHO_COUNT=0

report_failure() {
  echo "error: $*" >&2
  FAILURES=$((FAILURES + 1))
}

resolve_dependency() {
  local binary_path="$1"
  local dependency="$2"
  local relative_path
  local executable_dir="$APP_BIN_DIR"
  local relative_binary_path="${binary_path#"$CONTENTS_PATH"/}"

  # @executable_path is relative to the executable of the current process,
  # not necessarily the outer application. QtWebEngineProcess is a nested app
  # and must resolve against its own Contents/MacOS directory.
  if [[ "$relative_binary_path" == *.app/Contents/* ]]; then
    local nested_app_path="${relative_binary_path%%.app/Contents/*}.app"
    executable_dir="$CONTENTS_PATH/$nested_app_path/Contents/MacOS"
  fi

  case "$dependency" in
    @executable_path/*)
      relative_path="${dependency#@executable_path/}"
      [[ -e "$executable_dir/$relative_path" ]]
      ;;
    @loader_path/*)
      relative_path="${dependency#@loader_path/}"
      [[ -e "$(dirname "$binary_path")/$relative_path" ]]
      ;;
    @rpath/*)
      relative_path="${dependency#@rpath/}"
      [[ -e "$CONTENTS_PATH/Frameworks/$relative_path" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

while IFS= read -r -d '' file_path; do
  if ! file "$file_path" | grep -q "Mach-O"; then
    continue
  fi

  MACHO_COUNT=$((MACHO_COUNT + 1))

  if [[ -n "$EXPECTED_ARCH" ]]; then
    FILE_ARCHES="$(lipo -archs "$file_path" 2>/dev/null || true)"
    case " $FILE_ARCHES " in
      *" $EXPECTED_ARCH "*) ;;
      *) report_failure "$file_path does not contain $EXPECTED_ARCH (architectures: ${FILE_ARCHES:-unknown})" ;;
    esac
  fi

  INSTALL_ID="$(otool -D "$file_path" 2>/dev/null | sed -n '2p')"
  while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    [[ "$dependency" == "$INSTALL_ID" ]] && continue

    case "$dependency" in
      /System/Library/*|/usr/lib/*)
        ;;
      @executable_path/*)
        if [[ "$file_path" != "$APP_BIN" ]]; then
          report_failure "$file_path has a context-sensitive @executable_path dependency: $dependency"
        elif ! resolve_dependency "$file_path" "$dependency"; then
          report_failure "$file_path has an unresolved bundled dependency: $dependency"
        fi
        ;;
      @loader_path/*|@rpath/*)
        if ! resolve_dependency "$file_path" "$dependency"; then
          report_failure "$file_path has an unresolved bundled dependency: $dependency"
        fi
        ;;
      /*)
        report_failure "$file_path has an external absolute dependency: $dependency"
        ;;
      *)
        report_failure "$file_path has an unsupported dependency path: $dependency"
        ;;
    esac
  done < <(otool -L "$file_path" | tail -n +2 | awk '{print $1}')

  if [[ "$VERIFY_SIGNATURE" == "1" && "$file_path" != "$APP_BIN" ]]; then
    if ! codesign --verify --strict --verbose=2 "$file_path" >/dev/null 2>&1; then
      report_failure "$file_path does not have a valid code signature"
    fi
  fi
done < <(find "$CONTENTS_PATH" -type f -print0)

while IFS= read -r -d '' broken_link; do
  report_failure "$broken_link is a broken symbolic link"
done < <(find -L "$CONTENTS_PATH" -type l -print0)

[[ "$MACHO_COUNT" -gt 0 ]] || report_failure "no Mach-O files found in $APP_PATH"

if [[ "$VERIFY_SIGNATURE" == "1" ]]; then
  if ! codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null 2>&1; then
    codesign --verify --deep --strict --verbose=2 "$APP_PATH" || true
    report_failure "$APP_PATH failed deep code-signature verification"
  fi
fi

if [[ "$FAILURES" -ne 0 ]]; then
  die "macOS application verification failed with $FAILURES problem(s)"
fi

APP_ARCHES="$(lipo -archs "$APP_BIN")"
echo "Application architectures: $APP_ARCHES"
if [[ -n "$EXPECTED_QT_MAJOR" ]]; then
  echo "Expected Qt major version: $EXPECTED_QT_MAJOR"
fi
echo "Verified Mach-O files: $MACHO_COUNT"
echo "macOS application verification passed: $APP_PATH"
