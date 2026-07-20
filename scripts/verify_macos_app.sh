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
APP_PATH="$(cd "$APP_PATH" && pwd -P)"

CONTENTS_PATH="$APP_PATH/Contents"
APP_BIN="$CONTENTS_PATH/MacOS/mscore"
APP_BIN_DIR="$CONTENTS_PATH/MacOS"
QT_CORE_BINARY="$CONTENTS_PATH/Frameworks/QtCore.framework/QtCore"

[[ -x "$APP_BIN" ]] || die "missing app binary: $APP_BIN"
[[ -d "$CONTENTS_PATH/Resources/workspaces" ]] || die "missing installed workspaces"
[[ -d "$CONTENTS_PATH/Resources/fonts" ]] || die "missing installed fonts"
[[ -d "$CONTENTS_PATH/Resources/templates" ]] || die "missing installed templates"
[[ -f "$CONTENTS_PATH/Resources/qt.conf" ]] || die "missing macdeployqt qt.conf"
[[ -d "$CONTENTS_PATH/Frameworks/QtCore.framework" ]] || die "missing deployed QtCore.framework"
[[ -f "$QT_CORE_BINARY" ]] || die "missing deployed QtCore framework binary: $QT_CORE_BINARY"
[[ -f "$CONTENTS_PATH/PlugIns/platforms/libqcocoa.dylib" ]] || die "missing Cocoa platform plugin"

case "$EXPECTED_QT_MAJOR" in
  ""|5|6) ;;
  *) die "Qt major version must be 5 or 6" ;;
esac

FAILURES=0
MACHO_COUNT=0
ACTUAL_QT_MAJOR=""

report_failure() {
  echo "error: $*" >&2
  FAILURES=$((FAILURES + 1))
}

qt_framework_linkages() {
  local binary_path="$1"

  # The compatibility version is part of the Mach-O load command and remains
  # reliable for both layouts used here: Qt 5's Versions/5 and Qt 6's
  # Versions/A. Inspecting it also detects a framework or plugin copied from a
  # different Qt major even when its directory name looks plausible.
  otool -L "$binary_path" 2>/dev/null | awk '
    NR > 1 && $1 ~ /\/Qt[^\/]*\.framework\// &&
        $2 == "(compatibility" && $3 == "version" {
      split($4, version_parts, ".")
      printf "%s\t%s\n", $1, version_parts[1]
    }
  ' | LC_ALL=C sort -u
}

QT_CORE_MAJORS="$(
  qt_framework_linkages "$QT_CORE_BINARY" \
    | awk -F $'\t' '$1 ~ /\/QtCore\.framework\// { print $2 }' \
    | LC_ALL=C sort -u
)"
case "$QT_CORE_MAJORS" in
  5|6)
    ACTUAL_QT_MAJOR="$QT_CORE_MAJORS"
    ;;
  "")
    report_failure "could not determine the bundled QtCore major version from $QT_CORE_BINARY"
    ;;
  *)
    QT_CORE_MAJORS_DISPLAY="${QT_CORE_MAJORS//$'\n'/, }"
    report_failure "the bundled QtCore contains mixed or unsupported major versions: $QT_CORE_MAJORS_DISPLAY"
    ;;
esac

if [[ -n "$EXPECTED_QT_MAJOR" && -n "$ACTUAL_QT_MAJOR" \
      && "$EXPECTED_QT_MAJOR" != "$ACTUAL_QT_MAJOR" ]]; then
  report_failure "--qt-major requested Qt $EXPECTED_QT_MAJOR, but the bundled QtCore is Qt $ACTUAL_QT_MAJOR"
fi

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

resolve_loader_rpath() {
  local binary_path="$1"
  local rpath="$2"

  case "$rpath" in
    @loader_path)
      (cd "$(dirname "$binary_path")" && pwd -P)
      ;;
    @loader_path/*)
      (cd "$(dirname "$binary_path")/${rpath#@loader_path/}" 2>/dev/null && pwd -P)
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
  if [[ "$INSTALL_ID" == /* ]]; then
    report_failure "$file_path has a non-relocatable absolute LC_ID_DYLIB: $INSTALL_ID"
  fi

  while IFS=$'\t' read -r qt_dependency qt_major; do
    [[ -n "$qt_dependency" ]] || continue
    case "$qt_major" in
      5|6) ;;
      *)
        report_failure "$file_path has an unsupported Qt framework compatibility version: $qt_dependency (Qt $qt_major)"
        continue
        ;;
    esac
    if [[ -n "$ACTUAL_QT_MAJOR" && "$qt_major" != "$ACTUAL_QT_MAJOR" ]]; then
      report_failure "$file_path mixes Qt $qt_major linkage $qt_dependency with bundled QtCore $ACTUAL_QT_MAJOR"
    fi
  done < <(qt_framework_linkages "$file_path")

  HAS_FRAMEWORK_RPATH=0
  while IFS= read -r rpath; do
    [[ -n "$rpath" ]] || continue
    RESOLVED_RPATH="$(resolve_loader_rpath "$file_path" "$rpath" || true)"
    if [[ -z "$RESOLVED_RPATH" ]]; then
      report_failure "$file_path has an unsupported or unresolved LC_RPATH: $rpath"
      continue
    fi
    case "$RESOLVED_RPATH" in
      "$CONTENTS_PATH"|"$CONTENTS_PATH"/*) ;;
      *)
        report_failure "$file_path has an LC_RPATH outside the application bundle: $rpath -> $RESOLVED_RPATH"
        continue
        ;;
    esac
    if [[ "$RESOLVED_RPATH" == "$CONTENTS_PATH/Frameworks" ]]; then
      HAS_FRAMEWORK_RPATH=1
    fi
  done < <(otool -l "$file_path" | awk '
    /cmd LC_RPATH/ { in_rpath=1; next }
    in_rpath && $1 == "path" { print $2; in_rpath=0 }
  ')

  HAS_RPATH_DEPENDENCY=0
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
        if [[ "$dependency" == @rpath/* ]]; then
          HAS_RPATH_DEPENDENCY=1
        fi
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
  if [[ "$HAS_RPATH_DEPENDENCY" == "1" && "$HAS_FRAMEWORK_RPATH" == "0" ]]; then
    report_failure "$file_path has @rpath dependencies but no LC_RPATH resolving to Contents/Frameworks"
  fi

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
  echo "Qt major version: ${ACTUAL_QT_MAJOR:-unknown} (expected $EXPECTED_QT_MAJOR)"
else
  echo "Qt major version: ${ACTUAL_QT_MAJOR:-unknown}"
fi
echo "Verified Mach-O files: $MACHO_COUNT"
echo "macOS application verification passed: $APP_PATH"
