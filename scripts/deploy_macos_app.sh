#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH=""
QT_PREFIX="${QT_PREFIX:-}"
QT_MAJOR_VERSION="${QT_MAJOR_VERSION:-${MSCORE_QT_MAJOR_VERSION:-6}}"
SIGN_IDENTITY="-"
SIGN_APP=1
NO_STRIP=0
QML_DIRS=()

usage() {
  cat <<EOF
Usage: scripts/deploy_macos_app.sh --app APP [options]

Options:
  --app APP                 Application bundle to deploy.
  --qt-prefix DIR           Selected Qt installation prefix.
  --qt-major VERSION        Qt major version, 5 or 6. Default: ${QT_MAJOR_VERSION}
  --qml-dir DIR             QML source directory to scan. May be repeated.
  --no-strip                Preserve debug symbols while deploying.
  --skip-sign               Leave the deployed bundle unsigned.
  --sign-identity NAME      Code-sign identity. Default: ad-hoc signing.
  -h, --help                Show this help.
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
    --qt-prefix)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      QT_PREFIX="$2"
      shift 2
      ;;
    --qt-major)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      QT_MAJOR_VERSION="$2"
      shift 2
      ;;
    --qml-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      QML_DIRS+=("$2")
      shift 2
      ;;
    --no-strip)
      NO_STRIP=1
      shift
      ;;
    --skip-sign)
      SIGN_APP=0
      shift
      ;;
    --sign-identity)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      SIGN_IDENTITY="$2"
      shift 2
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
[[ -x "$APP_PATH/Contents/MacOS/mscore" ]] || die "missing application binary in $APP_PATH"

case "$QT_MAJOR_VERSION" in
  5|6) ;;
  *) die "Qt major version must be 5 or 6" ;;
esac

if [[ -z "$QT_PREFIX" ]]; then
  if [[ "$QT_MAJOR_VERSION" == "6" ]]; then
    QMAKE_BIN="$(command -v qmake6 2>/dev/null || command -v qmake 2>/dev/null || true)"
  else
    QMAKE_BIN="$(command -v qmake 2>/dev/null || command -v qmake-qt5 2>/dev/null || true)"
  fi
  [[ -n "$QMAKE_BIN" ]] || die "could not find qmake for Qt $QT_MAJOR_VERSION"
  QT_PREFIX="$("$QMAKE_BIN" -query QT_INSTALL_PREFIX)"
fi

QMAKE_BIN="$QT_PREFIX/bin/qmake"
if [[ "$QT_MAJOR_VERSION" == "6" && -x "$QT_PREFIX/bin/qmake6" ]]; then
  QMAKE_BIN="$QT_PREFIX/bin/qmake6"
fi
[[ -x "$QMAKE_BIN" ]] || die "missing qmake under $QT_PREFIX/bin"

QMAKE_VERSION="$("$QMAKE_BIN" -query QT_VERSION)"
[[ "$QMAKE_VERSION" == "$QT_MAJOR_VERSION".* ]] || die "$QMAKE_BIN reports Qt $QMAKE_VERSION, but Qt $QT_MAJOR_VERSION was requested"

MACDEPLOYQT="$QT_PREFIX/bin/macdeployqt"
[[ -x "$MACDEPLOYQT" ]] || die "missing macdeployqt: $MACDEPLOYQT"

if [[ ${#QML_DIRS[@]} -eq 0 ]]; then
  QML_DIRS=(
    "$ROOT_DIR/mscore"
    "$ROOT_DIR/telemetry"
    "$ROOT_DIR/share/plugins"
    # Scan the reviewed, pinned runtime installed into the bundle. Scanning the
    # submodule worktree here would let unrelated local plugin edits influence
    # which QML modules are deployed even though those edits are not packaged.
    "$APP_PATH/Contents/Resources/plugins/musescore-xen-tuner"
  )
fi

DEPLOY_ARGS=("$APP_PATH" -always-overwrite -verbose=1)
if [[ "$NO_STRIP" == "1" ]]; then
  DEPLOY_ARGS+=(-no-strip)
fi

# macdeployqt accepts one QML scan root. Assemble a small temporary tree that
# contains only QML sources from each requested group. This captures all
# imports in one pass without recursively scanning build/install artifacts or
# repeatedly redeploying frameworks copied by an earlier invocation.
QML_SCAN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/musescore-qml-scan.XXXXXX")"
QML_MODULE_LIST="$QML_SCAN_DIR/modules.txt"
cleanup_qml_scan() {
  rm -rf "$QML_SCAN_DIR"
}
trap cleanup_qml_scan EXIT

QML_GROUP_INDEX=0
for qml_dir in "${QML_DIRS[@]}"; do
  if [[ ! -d "$qml_dir" ]]; then
    continue
  fi

  QML_GROUP_INDEX=$((QML_GROUP_INDEX + 1))
  while IFS= read -r -d '' qml_source; do
    QML_RELATIVE_PATH="${qml_source#"$qml_dir"/}"
    QML_TARGET="$QML_SCAN_DIR/group-$QML_GROUP_INDEX/$QML_RELATIVE_PATH"
    mkdir -p "$(dirname "$QML_TARGET")"
    cp -p "$qml_source" "$QML_TARGET"
  done < <(find "$qml_dir" -type f \( -name "*.qml" -o -name "*.js" -o -name "qmldir" \) -print0)
done

QT_QML_PATH="$("$QMAKE_BIN" -query QT_INSTALL_QML)"
QML_IMPORT_SCANNER="$QT_PREFIX/libexec/qmlimportscanner"
if [[ ! -x "$QML_IMPORT_SCANNER" ]]; then
  QML_IMPORT_SCANNER="$QT_PREFIX/share/qt/libexec/qmlimportscanner"
fi
if [[ -x "$QML_IMPORT_SCANNER" && -d "$QT_QML_PATH" ]]; then
  "$QML_IMPORT_SCANNER" -rootPath "$QML_SCAN_DIR" -importPath "$QT_QML_PATH" \
    | sed -n 's/^[[:space:]]*"relativePath": "\([^"]*\)".*/\1/p' \
    | LC_ALL=C sort -u > "$QML_MODULE_LIST"
fi

# Repeated deployments must not retain frameworks, plugins, or QML modules
# copied by an earlier Qt installation.
rm -rf "$APP_PATH/Contents/Frameworks" "$APP_PATH/Contents/PlugIns" \
       "$APP_PATH/Contents/Resources/qml"
rm -f "$APP_PATH/Contents/Resources/qt.conf"

if [[ "$QT_MAJOR_VERSION" == "6" ]]; then
  # Qt 6 QML modules are deployed below from qmlimportscanner's exact module
  # list. Passing -qmldir here makes Homebrew's macdeployqt traverse its QML
  # symlink farm and bundle many unrelated modules.
  "$MACDEPLOYQT" "${DEPLOY_ARGS[@]}"
else
  "$MACDEPLOYQT" "${DEPLOY_ARGS[@]}" "-qmldir=$QML_SCAN_DIR"
fi

# Homebrew exposes Qt 6 QML modules through a symlink farm. macdeployqt copies
# those links verbatim, making them point inside the application bundle and
# leaving thousands of broken links. Rebuild the QML tree from the scanner's
# exact module list while dereferencing the Homebrew links.
if [[ "$QT_MAJOR_VERSION" == "6" && -s "$QML_MODULE_LIST" && -d "$QT_QML_PATH" ]]; then
  QML_DEPLOY_PATH="$APP_PATH/Contents/Resources/qml"
  rm -rf "$QML_DEPLOY_PATH"
  mkdir -p "$QML_DEPLOY_PATH"

  while IFS= read -r -d '' qml_root_file; do
    cp -Lp "$qml_root_file" "$QML_DEPLOY_PATH/"
  done < <(find -L "$QT_QML_PATH" -mindepth 1 -maxdepth 1 -type f -print0)

  while IFS= read -r module_path; do
    [[ -n "$module_path" && "$module_path" != *".."* ]] || continue
    module_source="$QT_QML_PATH/$module_path"
    module_target="$QML_DEPLOY_PATH/$module_path"
    [[ -d "$module_source" ]] || continue
    mkdir -p "$module_target"

    while IFS= read -r -d '' module_entry; do
      # A child directory with its own qmldir is another module and will be
      # copied only if qmlimportscanner selected it.
      if [[ -d "$module_entry" && -f "$module_entry/qmldir" ]]; then
        continue
      fi
      cp -RLp "$module_entry" "$module_target/"
    done < <(find -L "$module_source" -mindepth 1 -maxdepth 1 -print0)
  done < "$QML_MODULE_LIST"
fi

# MuseScore has no virtual-keyboard UI. Homebrew may install its platform
# plugin without the corresponding frameworks, which makes macdeployqt leave
# unresolved @rpath references.
if [[ "$QT_MAJOR_VERSION" == "6" ]]; then
  rm -f "$APP_PATH/Contents/PlugIns/platforminputcontexts/libqtvirtualkeyboardplugin.dylib"
  rm -f "$APP_PATH/Contents/Frameworks/QtVirtualKeyboard" \
        "$APP_PATH/Contents/Frameworks/QtVirtualKeyboardQml"
fi

[[ -f "$APP_PATH/Contents/PlugIns/platforms/libqcocoa.dylib" ]] || die "macdeployqt did not deploy the Cocoa platform plugin"
[[ -d "$APP_PATH/Contents/Frameworks/QtCore.framework" ]] || die "macdeployqt did not deploy QtCore.framework"

CONTENTS_PATH="$APP_PATH/Contents"
APP_BIN_DIR="$CONTENTS_PATH/MacOS"
FRAMEWORKS_PATH="$CONTENTS_PATH/Frameworks"
HOMEBREW_PREFIX=""
if command -v brew >/dev/null 2>&1; then
  HOMEBREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
fi

dependency_is_resolved() {
  local binary_path="$1"
  local dependency="$2"
  local relative_path
  local executable_dir="$APP_BIN_DIR"
  local relative_binary_path="${binary_path#"$CONTENTS_PATH"/}"

  if [[ "$relative_binary_path" == *.app/Contents/* ]]; then
    local nested_app_path="${relative_binary_path%%.app/Contents/*}.app"
    executable_dir="$CONTENTS_PATH/$nested_app_path/Contents/MacOS"
  fi

  case "$dependency" in
    /System/Library/*|/usr/lib/*)
      return 0
      ;;
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
      [[ -e "$FRAMEWORKS_PATH/$relative_path" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

find_dependency_source() {
  local dependency="$1"
  local file_name="${dependency##*/}"
  local candidate

  if [[ "$dependency" == /* && -f "$dependency" ]]; then
    echo "$dependency"
    return 0
  fi

  for candidate in \
    "$QT_PREFIX/lib/$file_name" \
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/lib/$file_name}"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  if [[ -n "$HOMEBREW_PREFIX" && -d "$HOMEBREW_PREFIX/opt" ]]; then
    candidate="$(find -L "$HOMEBREW_PREFIX/opt" -type f -name "$file_name" -print -quit 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi

  return 1
}

find_framework_source() {
  local dependency="$1"
  local framework_name="$2"
  local dependency_framework_path="${dependency%%.framework/*}.framework"
  local candidate

  for candidate in \
    "$dependency_framework_path" \
    "$QT_PREFIX/lib/$framework_name" \
    "${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/lib/$framework_name}"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      # The aggregate Homebrew Qt prefix exposes frameworks as symlinks into
      # individual formulae. Resolve only that outer link; framework-internal
      # relative links must remain intact when copied.
      (cd "$candidate" && pwd -P)
      return 0
    fi
  done

  if [[ -n "$HOMEBREW_PREFIX" && -d "$HOMEBREW_PREFIX/opt" ]]; then
    candidate="$(find -L "$HOMEBREW_PREFIX/opt" -type d -name "$framework_name" -print -quit 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
      (cd "$candidate" && pwd -P)
      return 0
    fi
  fi

  return 1
}

# macdeployqt follows most non-Qt dependencies, but Homebrew libraries can
# themselves refer to a transitive dylib through @rpath. Close that dependency
# graph and rewrite every added edge to the app's Frameworks directory.
for _pass in {1..10}; do
  COPIED_DEPENDENCY=0

  while IFS= read -r -d '' binary_path; do
    if ! file "$binary_path" | grep -q "Mach-O"; then
      continue
    fi

    INSTALL_ID="$(otool -D "$binary_path" 2>/dev/null | sed -n '2p')"
    if [[ "$INSTALL_ID" =~ ^@executable_path/(.*/)?Frameworks/(.+)$ ]]; then
      NORMALIZED_INSTALL_ID="@rpath/${BASH_REMATCH[2]}"
      install_name_tool -id "$NORMALIZED_INSTALL_ID" "$binary_path" 2>/dev/null || true
      INSTALL_ID="$NORMALIZED_INSTALL_ID"
      COPIED_DEPENDENCY=1
    fi

    while IFS= read -r dependency; do
      [[ -n "$dependency" ]] || continue
      [[ "$dependency" == "$INSTALL_ID" ]] && continue

      # Frameworks are shared by the main executable and nested helpers such
      # as QtWebEngineProcess. @executable_path changes meaning between those
      # processes, so normalize macdeployqt's bundled paths to @rpath.
      if [[ "$dependency" =~ ^@executable_path/(.*/)?Frameworks/(.+)$ ]]; then
        NORMALIZED_DEPENDENCY="@rpath/${BASH_REMATCH[2]}"
        if [[ -e "$FRAMEWORKS_PATH/${BASH_REMATCH[2]}" ]]; then
          install_name_tool -change "$dependency" "$NORMALIZED_DEPENDENCY" "$binary_path"
          COPIED_DEPENDENCY=1
          continue
        fi
      fi

      dependency_is_resolved "$binary_path" "$dependency" && continue

      if [[ "$dependency" =~ /([^/]+\.framework)/(Versions/[^/]+/[^/]+)$ ]]; then
        FRAMEWORK_NAME="${BASH_REMATCH[1]}"
        FRAMEWORK_INNER_PATH="${BASH_REMATCH[2]}"
        FRAMEWORK_RELATIVE_PATH="$FRAMEWORK_NAME/$FRAMEWORK_INNER_PATH"
        FRAMEWORK_TARGET="$FRAMEWORKS_PATH/$FRAMEWORK_NAME"

        if [[ ! -e "$FRAMEWORKS_PATH/$FRAMEWORK_RELATIVE_PATH" ]]; then
          FRAMEWORK_SOURCE="$(find_framework_source "$dependency" "$FRAMEWORK_NAME" || true)"
          [[ -n "$FRAMEWORK_SOURCE" ]] || die "could not bundle framework $dependency required by $binary_path"

          rm -rf "$FRAMEWORK_TARGET"
          # Framework-internal links (Versions/Current and the top-level
          # binary) are relative and remain valid in the app bundle. Preserve
          # them so each Mach-O binary is processed and signed only once.
          cp -Rp "$FRAMEWORK_SOURCE" "$FRAMEWORK_TARGET"
          chmod -R u+w "$FRAMEWORK_TARGET"
        fi

        [[ -e "$FRAMEWORKS_PATH/$FRAMEWORK_RELATIVE_PATH" ]] || \
          die "framework $FRAMEWORK_NAME does not contain $FRAMEWORK_INNER_PATH"
        install_name_tool -id "@rpath/$FRAMEWORK_RELATIVE_PATH" \
          "$FRAMEWORKS_PATH/$FRAMEWORK_RELATIVE_PATH" 2>/dev/null || true
        install_name_tool -change "$dependency" \
          "@rpath/$FRAMEWORK_RELATIVE_PATH" "$binary_path"
        COPIED_DEPENDENCY=1
        continue
      fi

      SOURCE_PATH="$(find_dependency_source "$dependency" || true)"
      [[ -n "$SOURCE_PATH" ]] || die "could not bundle dependency $dependency required by $binary_path"

      FILE_NAME="${SOURCE_PATH##*/}"
      TARGET_PATH="$FRAMEWORKS_PATH/$FILE_NAME"
      if [[ ! -e "$TARGET_PATH" ]]; then
        cp -p "$SOURCE_PATH" "$TARGET_PATH"
        chmod u+w "$TARGET_PATH"
        install_name_tool -id "@rpath/$FILE_NAME" "$TARGET_PATH" 2>/dev/null || true
      fi

      install_name_tool -change "$dependency" "@rpath/$FILE_NAME" "$binary_path"
      COPIED_DEPENDENCY=1
    done < <(otool -L "$binary_path" | tail -n +2 | awk '{print $1}')
  done < <(find "$CONTENTS_PATH" -type f -print0)

  [[ "$COPIED_DEPENDENCY" == "1" ]] || break
done

bundle_framework_rpath() {
  local binary_path="$1"
  local binary_dir
  local relative_dir
  local depth=1
  local result="@loader_path"
  local i

  binary_dir="$(dirname "$binary_path")"
  if [[ "$binary_dir" == "$FRAMEWORKS_PATH" ]]; then
    echo "$result"
    return 0
  fi

  if [[ "$binary_dir" == "$FRAMEWORKS_PATH/"* ]]; then
    relative_dir="${binary_dir#"$FRAMEWORKS_PATH/"}"
    while [[ "$relative_dir" == */* ]]; do
      depth=$((depth + 1))
      relative_dir="${relative_dir#*/}"
    done
    for ((i = 0; i < depth; ++i)); do
      result="$result/.."
    done
    echo "$result"
    return 0
  fi

  [[ "$binary_dir" == "$CONTENTS_PATH/"* ]] \
    || die "Mach-O file is outside the application bundle: $binary_path"
  relative_dir="${binary_dir#"$CONTENTS_PATH/"}"
  while [[ "$relative_dir" == */* ]]; do
    depth=$((depth + 1))
    relative_dir="${relative_dir#*/}"
  done
  for ((i = 0; i < depth; ++i)); do
    result="$result/.."
  done
  echo "$result/Frameworks"
}

rpath_resolves_inside_bundle() {
  local binary_path="$1"
  local rpath="$2"
  local resolved_path=""

  case "$rpath" in
    @loader_path)
      resolved_path="$(cd "$(dirname "$binary_path")" && pwd -P)"
      ;;
    @loader_path/*)
      resolved_path="$(cd "$(dirname "$binary_path")/${rpath#@loader_path/}" 2>/dev/null && pwd -P || true)"
      ;;
    *)
      return 1
      ;;
  esac

  case "$resolved_path" in
    "$CONTENTS_PATH"|"$CONTENTS_PATH"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Homebrew's Qt packages and their transitive libraries commonly carry build-
# machine LC_RPATH entries. An @rpath dependency can then prefer /opt/homebrew
# over the copy in Contents/Frameworks, making an apparently complete bundle
# fail on a clean Mac. Replace every external runpath with a loader-relative
# route to this bundle and give copied dylibs without LC_RPATH the same route.
while IFS= read -r -d '' binary_path; do
  if ! file "$binary_path" | grep -q "Mach-O"; then
    continue
  fi

  DESIRED_RPATH="$(bundle_framework_rpath "$binary_path")"
  HAS_DESIRED_RPATH=0
  INVALID_RPATHS=()
  while IFS= read -r existing_rpath; do
    [[ -n "$existing_rpath" ]] || continue
    if [[ "$existing_rpath" == "$DESIRED_RPATH" ]]; then
      HAS_DESIRED_RPATH=1
    elif ! rpath_resolves_inside_bundle "$binary_path" "$existing_rpath"; then
      INVALID_RPATHS+=("$existing_rpath")
    fi
  done < <(otool -l "$binary_path" | awk '
    /cmd LC_RPATH/ { in_rpath=1; next }
    in_rpath && $1 == "path" { print $2; in_rpath=0 }
  ')

  NEEDS_FRAMEWORK_RPATH=0
  if otool -L "$binary_path" | tail -n +2 | awk '{print $1}' | grep -q '^@rpath/'; then
    NEEDS_FRAMEWORK_RPATH=1
  fi

  INVALID_RPATH_INDEX=0
  if [[ "$NEEDS_FRAMEWORK_RPATH" == "1" && "$HAS_DESIRED_RPATH" == "0" ]]; then
    if [[ ${#INVALID_RPATHS[@]} -gt 0 ]]; then
      install_name_tool -rpath "${INVALID_RPATHS[0]}" "$DESIRED_RPATH" "$binary_path"
      INVALID_RPATH_INDEX=1
    else
      install_name_tool -add_rpath "$DESIRED_RPATH" "$binary_path"
    fi
  fi

  while [[ "$INVALID_RPATH_INDEX" -lt ${#INVALID_RPATHS[@]} ]]; do
    install_name_tool -delete_rpath "${INVALID_RPATHS[$INVALID_RPATH_INDEX]}" "$binary_path"
    INVALID_RPATH_INDEX=$((INVALID_RPATH_INDEX + 1))
  done
done < <(find "$CONTENTS_PATH" -type f -print0)

if [[ "$SIGN_APP" == "1" ]]; then
  # QML plugins are stored in Resources, so sign those Mach-O files before
  # the final deep pass seals the complete application bundle.
  if [[ -d "$APP_PATH/Contents/Resources" ]]; then
    while IFS= read -r -d '' file_path; do
      if file "$file_path" | grep -q "Mach-O"; then
        codesign --force --sign "$SIGN_IDENTITY" "$file_path"
      fi
    done < <(find "$APP_PATH/Contents/Resources" -type f -print0)
  fi
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"
fi

echo "Deployed macOS application: $APP_PATH"
echo "Qt: $QMAKE_VERSION ($QT_PREFIX)"
