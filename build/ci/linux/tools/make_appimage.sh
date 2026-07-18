#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="${1:-}" # MuseScore was installed here
APPIMAGE_NAME="${2:-}" # name for AppImage file (created outside $INSTALL_DIR)

if [ -z "$INSTALL_DIR" ]; then echo "error: not set INSTALL_DIR"; exit 1; fi
if [ -z "$APPIMAGE_NAME" ]; then echo "error: not set APPIMAGE_NAME"; exit 1; fi

APPIMAGE_ARCH="${APPIMAGE_ARCH:-$(uname -m)}"
case "${APPIMAGE_ARCH}" in
  amd64|x86_64) APPIMAGE_ARCH=x86_64 ;;
  arm64|aarch64) APPIMAGE_ARCH=aarch64 ;;
  *) echo "error: unsupported AppImage architecture '${APPIMAGE_ARCH}'"; exit 1 ;;
esac

HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
  amd64|x86_64) HOST_ARCH=x86_64 ;;
  arm64|aarch64) HOST_ARCH=aarch64 ;;
  *) echo "error: unsupported build host architecture '${HOST_ARCH}'"; exit 1 ;;
esac

FOREIGN_APPIMAGE_BUILD=0
TARGET_TRIPLET=""
TARGET_LOADER=""
TARGET_SYSROOT=""
TARGET_LIBRARY_PATH=""

function target_path()
{
  local -r prefix="$1" path="$2"
  if [[ "${prefix}" == "/" ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s%s\n' "${prefix%/}" "${path}"
  fi
}

function find_target_runtime()
{
  local compiler="${CC:-}"
  local compiler_sysroot=""
  local candidate=""
  local loader_path=""
  local -a sysroot_candidates=()
  local -a loader_candidates=()

  case "${APPIMAGE_ARCH}" in
    aarch64)
      TARGET_TRIPLET=aarch64-linux-gnu
      loader_candidates=(
        /lib/ld-linux-aarch64.so.1
        /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1
        /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1
        )
      ;;
    x86_64)
      TARGET_TRIPLET=x86_64-linux-gnu
      loader_candidates=(
        /lib64/ld-linux-x86-64.so.2
        /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2
        /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2
        )
      ;;
  esac

  [[ -n "${APPIMAGE_SYSROOT:-}" ]] && sysroot_candidates+=("${APPIMAGE_SYSROOT}")
  [[ -n "${CMAKE_SYSROOT:-}" ]] && sysroot_candidates+=("${CMAKE_SYSROOT}")

  if [[ -f CMakeCache.txt ]]; then
    candidate="$(sed -n 's/^CMAKE_SYSROOT[^=]*=//p' CMakeCache.txt | head -n 1)"
    [[ -n "${candidate}" ]] && sysroot_candidates+=("${candidate}")
    if [[ -z "${compiler}" ]]; then
      compiler="$(sed -n 's/^CMAKE_C_COMPILER[^=]*=//p' CMakeCache.txt | head -n 1)"
    fi
  fi

  if [[ -z "${compiler}" ]] && command -v "${TARGET_TRIPLET}-gcc" >/dev/null 2>&1; then
    compiler="$(command -v "${TARGET_TRIPLET}-gcc")"
  fi
  if [[ -n "${compiler}" && -x "${compiler}" ]]; then
    compiler_sysroot="$("${compiler}" -print-sysroot 2>/dev/null || true)"
    [[ -n "${compiler_sysroot}" ]] && sysroot_candidates+=("${compiler_sysroot}")
  fi

  sysroot_candidates+=("/usr/${TARGET_TRIPLET}" /)
  for candidate in "${sysroot_candidates[@]}"; do
    [[ -n "${candidate}" ]] || continue
    candidate="${candidate%/}"
    [[ -n "${candidate}" ]] || candidate=/
    for loader_path in "${loader_candidates[@]}"; do
      loader_path="$(target_path "${candidate}" "${loader_path}")"
      if [[ -x "${loader_path}" ]]; then
        TARGET_SYSROOT="${candidate}"
        TARGET_LOADER="${loader_path}"
        return 0
      fi
    done
  done

  echo "$0: error: unable to find the ${APPIMAGE_ARCH} dynamic loader." >&2
  echo "$0: Set APPIMAGE_SYSROOT to the target sysroot (for example /usr/${TARGET_TRIPLET})." >&2
  return 1
}

function build_target_library_path()
{
  local dir=""
  local existing=""
  local -a dirs=()

  function add_target_library_dir()
  {
    local -r new_dir="$1"
    [[ -d "${new_dir}" ]] || return 0
    for existing in "${dirs[@]}"; do
      [[ "${existing}" == "${new_dir}" ]] && return 0
    done
    dirs+=("${new_dir}")
  }

  if [[ -n "${APPIMAGE_TARGET_LIBRARY_PATH:-}" ]]; then
    while IFS= read -r dir; do
      [[ -n "${dir}" ]] && add_target_library_dir "${dir}"
    done < <(printf '%s' "${APPIMAGE_TARGET_LIBRARY_PATH}" | tr ':' '\n')
  fi

  add_target_library_dir "$(dirname "${TARGET_LOADER}")"
  add_target_library_dir "${INSTALL_DIR%/}/lib"
  add_target_library_dir "${INSTALL_DIR%/}/lib/${TARGET_TRIPLET}"
  add_target_library_dir "$(target_path "${TARGET_SYSROOT}" "/lib/${TARGET_TRIPLET}")"
  add_target_library_dir "$(target_path "${TARGET_SYSROOT}" "/usr/lib/${TARGET_TRIPLET}")"
  if [[ "${TARGET_SYSROOT}" != "/" ]]; then
    add_target_library_dir "$(target_path "${TARGET_SYSROOT}" /lib)"
    add_target_library_dir "$(target_path "${TARGET_SYSROOT}" /lib64)"
    add_target_library_dir "$(target_path "${TARGET_SYSROOT}" /usr/lib)"
    add_target_library_dir "$(target_path "${TARGET_SYSROOT}" /usr/lib64)"
  fi
  add_target_library_dir "/lib/${TARGET_TRIPLET}"
  add_target_library_dir "/usr/lib/${TARGET_TRIPLET}"

  if [[ -n "${QT_PATH:-}" ]]; then
    add_target_library_dir "${QT_PATH%/}/lib/${TARGET_TRIPLET}"
    if [[ "${QT_PATH}" != "/usr" && "${QT_PATH}" != "/usr/" ]]; then
      add_target_library_dir "${QT_PATH%/}/lib"
      add_target_library_dir "${QT_PATH%/}/lib64"
    fi
  fi

  TARGET_LIBRARY_PATH="$(IFS=:; printf '%s' "${dirs[*]}")"
  [[ -n "${TARGET_LIBRARY_PATH}" ]] || {
    echo "$0: error: unable to construct a target library search path for ${APPIMAGE_ARCH}." >&2
    return 1
  }
}

function setup_foreign_appimage_build()
{
  [[ "${HOST_ARCH}" != "${APPIMAGE_ARCH}" ]] || return 0
  FOREIGN_APPIMAGE_BUILD=1

  find_target_runtime
  build_target_library_path
  export QEMU_LD_PREFIX="${TARGET_SYSROOT}"

  local -r binfmt_handler="qemu-${APPIMAGE_ARCH}"
  local -r binfmt_registration="/proc/sys/fs/binfmt_misc/${binfmt_handler}"
  if [[ ! -r "${binfmt_registration}" ]] || ! grep -q '^enabled' "${binfmt_registration}"; then
    cat >&2 <<EOF
$0: error: ${APPIMAGE_ARCH} executables cannot run on the ${HOST_ARCH} host.
Install and enable qemu-user-binfmt/binfmt-support (qemu-user-static on older Ubuntu),
or run the build with --docker.
Expected enabled handler: ${binfmt_registration}
EOF
    return 1
  fi

  local -r probe="${INSTALL_DIR%/}/bin/findlib"
  if [[ -x "${probe}" ]] && ! "${probe}" --help >/dev/null 2>&1; then
    cat >&2 <<EOF
$0: error: QEMU could not execute the ${APPIMAGE_ARCH} target helper '${probe}'.
Target sysroot: ${TARGET_SYSROOT}
Set APPIMAGE_SYSROOT explicitly or run the build with --docker.
EOF
    return 1
  fi

  local -r cross_tools_dir="${PWD%/}/.appimage-cross-tools"
  mkdir -p "${cross_tools_dir}"
  printf '#!/usr/bin/env bash\nexec %q --inhibit-cache --library-path %q --list "$@"\n' \
    "${TARGET_LOADER}" "${TARGET_LIBRARY_PATH}" > "${cross_tools_dir}/ldd"
  chmod +x "${cross_tools_dir}/ldd"
  export PATH="${cross_tools_dir}:${PATH}"

  echo "Cross-bundling ${APPIMAGE_ARCH} AppImage on ${HOST_ARCH} with QEMU (sysroot: ${TARGET_SYSROOT})"
}

setup_foreign_appimage_build

##########################################################################
# INSTALL APPIMAGETOOL AND LINUXDEPLOY
##########################################################################

function download_github_release()
{
  local -r repo_slug="$1" release_tag="$2" file="$3"
  wget -q --show-progress "https://github.com/${repo_slug}/releases/download/${release_tag}/${file}"
  chmod +x "${file}"
}

function extract_appimage_with_unsquashfs()
{
  local -r appimage="$1"
  local offset=""

  command -v unsquashfs >/dev/null || {
    echo "$0: error: '${appimage}' could not self-extract and unsquashfs is not installed." >&2
    return 1
  }

  while IFS=: read -r offset _; do
    rm -rf squashfs-root
    if unsquashfs -q -o "${offset}" -d squashfs-root "${appimage}" >/dev/null 2>&1 && [[ -e squashfs-root/AppRun ]]; then
      return 0
    fi
  done < <(LC_ALL=C grep -abo 'hsqs' "${appimage}")

  echo "$0: error: failed to extract '${appimage}' with unsquashfs." >&2
  return 1
}

function extract_appimage()
{
  # Extract AppImage so we can run it without having to install FUSE
  local -r appimage="$1" binary_name="$2"
  local -r appdir="${appimage%.AppImage}.AppDir"
  rm -rf squashfs-root "${appdir}"
  if ! "./${appimage}" --appimage-extract >/dev/null 2>&1; then # dest folder "squashfs-root"
    echo "$0: '${appimage}' could not self-extract; falling back to unsquashfs." >&2
    extract_appimage_with_unsquashfs "${appimage}"
  fi
  mv squashfs-root "${appdir}" # rename folder to avoid collisions
  cat > "${binary_name}" <<EOF
#!/usr/bin/env bash
tool_dir="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec "\${tool_dir}/${appdir}/AppRun" "\$@"
EOF
  chmod +x "${binary_name}"
  rm -f "${appimage}"
}

function download_appimage_release()
{
  local -r github_repo_slug="$1" binary_name="$2" tag="$3"
  local -r appimage="${binary_name}-${APPIMAGE_ARCH}.AppImage"
  download_github_release "${github_repo_slug}" "${tag}" "${appimage}"
  extract_appimage "${appimage}" "${binary_name}"
}

if [[ ! -x "appimagetool/appimagetool" || -L "appimagetool/appimagetool" ]]; then
  rm -rf appimagetool
  mkdir appimagetool
  cd appimagetool
  # `12` and not `continuous` because see https://github.com/AppImage/AppImageKit/issues/1060
  download_appimage_release AppImage/AppImageKit appimagetool 12
  cd ..
fi
export PATH="${PWD%/}/appimagetool:${PATH}"
appimagetool --version

if [[ -n "${UPDATE_INFORMATION:-}" ]]; then
  if [[ ! -x "appimageupdatetool/appimageupdatetool" || -L "appimageupdatetool/appimageupdatetool" ]]; then
    rm -rf appimageupdatetool
    mkdir appimageupdatetool
    cd appimageupdatetool
    download_appimage_release AppImage/AppImageUpdate appimageupdatetool continuous
    cd ..
  fi
  export PATH="${PWD%/}/appimageupdatetool:${PATH}"
  appimageupdatetool --version
fi

function download_linuxdeploy_component()
{
  download_appimage_release "linuxdeploy/$1" "$1" continuous
}

if [[ ! -x "linuxdeploy/linuxdeploy" || ! -x "linuxdeploy/linuxdeploy-plugin-qt" || -L "linuxdeploy/linuxdeploy" || -L "linuxdeploy/linuxdeploy-plugin-qt" ]]; then
  rm -rf linuxdeploy
  mkdir linuxdeploy
  cd linuxdeploy
  download_linuxdeploy_component linuxdeploy
  download_linuxdeploy_component linuxdeploy-plugin-qt
  cd ..
fi
export PATH="${PWD%/}/linuxdeploy:${PATH}"
linuxdeploy --list-plugins

##########################################################################
# BUNDLE DEPENDENCIES INTO APPDIR
##########################################################################

cd "$(dirname "${INSTALL_DIR}")"
appdir="$(basename "${INSTALL_DIR}")" # directory that will become the AppImage

# The portable AppDir intentionally aliases usr to its root so linuxdeploy's
# standard usr/bin layout resolves to CMake's bin/lib/share installation.
if [[ ! -L "${appdir}/usr" ]]; then
  echo "$0: error: '${appdir}/usr' must be a symbolic link to '.' before deployment." >&2
  exit 1
fi
if [[ "$(readlink "${appdir}/usr")" != "." ]]; then
  echo "$0: error: '${appdir}/usr' must be a symbolic link to '.' before deployment." >&2
  exit 1
fi

# Prevent linuxdeploy setting RUNPATH in binaries that shouldn't have it
mv "${appdir}/bin/findlib" "${appdir}/../findlib"

# A previous interrupted deployment may have left top-level Qt payload. The
# caller recreates the install prefix before packaging; remove these generated
# paths as an additional guard before qmlimportscanner runs.
rm -rf "${appdir}/plugins" "${appdir}/qml" "${appdir}/fallback"

# Remove Qt plugins for MySQL and PostgreSQL to prevent
# linuxdeploy-plugin-qt from failing due to missing dependencies.
# SQLite plugin alone should be enough for our AppImage.
# rm -f ${QT_PATH}/plugins/sqldrivers/libqsql{mysql,psql}.so
qt_plugins_path="${QT_PLUGIN_PATH:-}"
qt_plugins_path="${qt_plugins_path%%:*}"
if [[ -z "${qt_plugins_path}" ]]; then
  qt_plugins_path="${QT_PATH%/}/plugins"
fi

# Some plugins shipped in the fixed Qt SDK are optional for MuseScore but pull
# in Qt add-ons that are not part of that SDK installation. Hide them while
# linuxdeploy-plugin-qt scans the plugin tree, then restore them even when a
# deployment command fails so a reused builder remains deterministic.
qt_optional_plugins_tmp="$(mktemp -d "${TMPDIR:-/tmp}/qtplugins.XXXXXX")"
qt_optional_plugins_moved=()

function move_optional_qt_plugin()
{
  local -r relative_path="$1"
  local -r source_path="${qt_plugins_path}/${relative_path}"
  [[ -f "${source_path}" ]] || return 0

  mkdir -p "${qt_optional_plugins_tmp}/$(dirname "${relative_path}")"
  mv "${source_path}" "${qt_optional_plugins_tmp}/${relative_path}"
  qt_optional_plugins_moved+=("${relative_path}")
}

function restore_optional_qt_plugins()
{
  local relative_path=""
  for relative_path in "${qt_optional_plugins_moved[@]}"; do
    [[ -f "${qt_optional_plugins_tmp}/${relative_path}" ]] || continue
    mkdir -p "${qt_plugins_path}/$(dirname "${relative_path}")"
    mv "${qt_optional_plugins_tmp}/${relative_path}" \
      "${qt_plugins_path}/${relative_path}"
  done
  rm -rf "${qt_optional_plugins_tmp}"
}

trap restore_optional_qt_plugins EXIT

qt_sql_drivers_path="${qt_plugins_path}/sqldrivers"
while IFS= read -r -d '' driver_path; do
  move_optional_qt_plugin "sqldrivers/$(basename "${driver_path}")"
done < <(find "${qt_sql_drivers_path}" -maxdepth 1 -type f \
  -name 'libqsql*.so' ! -name 'libqsqlite.so' -print0)

# The NMEA positioning backend depends on Qt SerialPort, which MuseScore does
# not use and which is intentionally absent from the pinned Linux Qt SDK.
move_optional_qt_plugin "position/libqtposition_nmea.so"

# qmlimportscanner reports MuseScore's C++-registered MuseScore/FileIO modules
# and Qt's optional non-Linux Controls styles as missing modules. Those reports
# are expected; linuxdeploy-plugin-qt still deploys the Qt modules imported by
# the installed application and plugins. Do not copy the entire SDK QML tree:
# it also contains test/experimental modules whose private libraries are not
# installed in the pinned runtime SDK.
unset QML_SOURCES_PATHS QML_MODULES_PATHS

linuxdeploy --appdir "${appdir}" # adds all shared library dependencies
linuxdeploy-plugin-qt --appdir "${appdir}" # adds all Qt dependencies

# In case this container is reused multiple times, return the hidden plugins.
restore_optional_qt_plugins
trap - EXIT

# Put the non-RUNPATH binaries back
mv "${appdir}/../findlib" "${appdir}/bin/findlib"

##########################################################################
# BUNDLE REMAINING DEPENDENCIES MANUALLY
##########################################################################

function find_library()
{
  # Print full path to a library or return exit status 1 if not found
  if [[ "${FOREIGN_APPIMAGE_BUILD}" == "1" ]]; then
    local qemu_set_env="LD_LIBRARY_PATH=${TARGET_LIBRARY_PATH}"
    [[ -n "${QEMU_SET_ENV:-}" ]] && qemu_set_env="${qemu_set_env},${QEMU_SET_ENV}"
    env -u LD_LIBRARY_PATH QEMU_SET_ENV="${qemu_set_env}" "${appdir}/bin/findlib" "$@"
  else
    "${appdir}/bin/findlib" "$@"
  fi
}

function fallback_library()
{
  # Copy a library into a special fallback directory inside the AppDir.
  # Fallback libraries are not loaded at runtime by default, but they can
  # be loaded if it is found that the application would crash otherwise.
  local library="$1"
  local full_path=""
  local new_path="${appdir}/fallback/${library}"
  if ! full_path="$(find_library "$1")"; then
    echo "$0: Warning: Unable to find fallback library '${library}'. Skipping." >&2
    return 0
  fi
  mkdir -p "${new_path}" # directory has the same name as the library
  cp -L "${full_path}" "${new_path}/${library}"
  # Use the AppRun script to check at runtime whether the user has a copy of
  # this library. If not then add our copy's directory to $LD_LIBRARY_PATH.
}

# UNWANTED FILES
# linuxdeploy or linuxdeploy-plugin-qt may have added some files or folders
# that we don't want. List them here using paths relative to AppDir root.
# Report new additions at https://github.com/linuxdeploy/linuxdeploy/issues
# or https://github.com/linuxdeploy/linuxdeploy-plugin-qt/issues for Qt libs.
unwanted_files=(
  # none
)

# REQUIRED QT COMPONENTS
# The offscreen plugin makes the packaged binary testable and usable for
# command-line conversion on systems without an X server. Missing it is a
# deployment error rather than an optional feature loss.
required_qt_components=(
  platforms/libqoffscreen.so
)

# ADDITIONAL OPTIONAL QT COMPONENTS
additional_qt_components=(
  platforms/libqminimal.so
  printsupport/libcupsprintersupport.so
)

# ADDITIONAL LIBRARIES
# linuxdeploy may have missed some libraries that we need
# Report new additions at https://github.com/linuxdeploy/linuxdeploy/issues
additional_library_alternatives=(
  "libssl.so.1.0.0 libssl.so.1.1 libssl.so.3"       # OpenSSL (for Save Online)
  "libcrypto.so.1.0.0 libcrypto.so.1.1 libcrypto.so.3"
  # Keep a copy inside the extracted AppDir. The outer AppImage runtime still
  # needs a host FUSE library before it can mount the image, so the generated
  # .AppImage.run launcher below provides the no-FUSE bootstrap fallback.
  "libfuse.so.2"
)

# FALLBACK LIBRARIES
# These get bundled in the AppImage, but are only loaded if the user does not
# already have a version of the library installed on their system. This is
# helpful in cases where it is necessary to use a system library in order for
# a particular feature to work properly, but where the program would crash at
# startup if the library was not found. The fallback library may not provide
# the full functionality of the system version, but it does avoid the crash.
# Report new additions at https://github.com/linuxdeploy/linuxdeploy/issues
fallback_libraries=(
  libjack.so.0 # https://github.com/LMMS/lmms/pull/3958
)

# PREVIOUSLY EXTRACTED APPIMAGES
# These include their own dependencies. We bundle them uncompressed to avoid
# creating a double layer of compression (AppImage inside AppImage).
extracted_appimages=(
  # none when automatic AppImage updates are disabled
)
if [[ -n "${UPDATE_INFORMATION:-}" ]]; then
  extracted_appimages+=(appimageupdatetool)
fi

for file in "${unwanted_files[@]}"; do
  rm -rf "${appdir}/${file}"
done

for file in "${required_qt_components[@]}"; do
  if [[ ! -f "${qt_plugins_path}/${file}" ]]; then
    echo "$0: error: Required Qt component is missing: '${qt_plugins_path}/${file}'." >&2
    exit 1
  fi
  mkdir -p "${appdir}/plugins/$(dirname "${file}")"
  cp -L "${qt_plugins_path}/${file}" "${appdir}/plugins/${file}"
  echo "$0: Bundled required Qt component '${file}'."
done

for file in "${additional_qt_components[@]}"; do
  if [[ ! -f "${qt_plugins_path}/${file}" ]]; then
    echo "$0: Warning: Unable to find Qt component '${qt_plugins_path}/${file}'. Skipping." >&2
    continue
  fi
  mkdir -p "${appdir}/plugins/$(dirname "${file}")"
  cp -L "${qt_plugins_path}/${file}" "${appdir}/plugins/${file}"
done

for alternatives in "${additional_library_alternatives[@]}"; do
  full_path=""
  selected_library=""
  for lib in ${alternatives}; do
    if full_path="$(find_library "${lib}" 2>/dev/null)"; then
      selected_library="${lib}"
      break
    fi
  done
  if [[ -z "${selected_library}" ]]; then
    echo "$0: Warning: Unable to find any additional library from '${alternatives}'. Skipping." >&2
    continue
  fi
  destination="${appdir}/lib/${selected_library}"
  cp -L "${full_path}" "${destination}"
  patchelf --set-rpath '$ORIGIN' "${destination}"
done

if [[ ! -f "${appdir}/lib/libfuse.so.2" ]]; then
  echo "$0: error: libfuse.so.2 is required for the packaged FUSE fallback." >&2
  exit 1
fi

for fb_lib in "${fallback_libraries[@]}"; do
  fallback_library "${fb_lib}"
done

for name in "${extracted_appimages[@]}"; do
  symlink="$(command -v "${name}" || true)"
  if [[ -z "${symlink}" ]]; then
     echo "$0: Warning: Unable to find AppImage for '${name}'. Will not bundle." >&2
     continue
  fi
  if [[ -L "${symlink}" ]]; then
    apprun_target="$(readlink "${symlink}" || true)"
    if [[ "${apprun_target}" = /* ]]; then
      apprun="${apprun_target}"
    else
      apprun="$(dirname "${symlink}")/${apprun_target}"
    fi
  else
    apprun="$(dirname "${symlink}")/${name}-${APPIMAGE_ARCH}.AppDir/AppRun"
  fi
  if [[ ! -f "${apprun}" ]]; then
     echo "$0: Warning: Unable to find AppRun for '${name}'. Will not bundle." >&2
     continue
  fi
  extracted_appdir_path="$(dirname "${apprun}")"
  extracted_appdir_name="$(basename "${extracted_appdir_path}")"
  rm -rf "${appdir:?}/${extracted_appdir_name}"
  cp -a "${extracted_appdir_path}" "${appdir}/"
  rm -f "${appdir}/bin/${name}"
  ln -s "../${extracted_appdir_name}/AppRun" "${appdir}/bin/${name}"
done

# METHOD OF LAST RESORT
# Special treatment for some dependencies when all other methods fail

# Bundle libnss3 and friends as fallback libraries. Needed on Chromebook.
# See discussion at https://github.com/probonopd/linuxdeployqt/issues/35
libnss3_files=(
  # https://packages.ubuntu.com/xenial/amd64/libnss3/filelist
  libnss3.so
  libnssutil3.so
  libsmime3.so
  libssl3.so
  nss/libfreebl3.chk
  nss/libfreebl3.so
  nss/libfreeblpriv3.chk
  nss/libfreeblpriv3.so
  nss/libnssckbi.so
  nss/libnssdbm3.chk
  nss/libnssdbm3.so
  nss/libsoftokn3.chk
  nss/libsoftokn3.so
)

if libnss3_path="$(find_library libnss3.so)"; then
  libnss3_system_path="$(dirname "${libnss3_path}")"
  libnss3_appdir_path="${appdir}/fallback/libnss3.so" # directory named like library

  mkdir -p "${libnss3_appdir_path}/nss"

  for file in "${libnss3_files[@]}"; do
    if [[ -f "${libnss3_system_path}/${file}" ]]; then
      cp -L "${libnss3_system_path}/${file}" "${libnss3_appdir_path}/${file}"
      rm -f "${appdir}/lib/$(basename "${file}")" # in case it was already packaged by linuxdeploy
    else
      echo "$0: Warning: Unable to find NSS file '${libnss3_system_path}/${file}'. Skipping." >&2
    fi
  done
else
  echo "$0: Warning: Unable to find libnss3.so. Skipping NSS fallback bundle." >&2
fi

##########################################################################
# TURN APPDIR INTO AN APPIMAGE
##########################################################################

appimage="${APPIMAGE_NAME}" # name to use for AppImage file

appimagetool_args=( # array
  # none
  )

created_files=(
  "${appimage}"
  )

if [[ "${UPDATE_INFORMATION:-}" ]]; then
  appimagetool_args+=( # append to array
    --updateinformation "${UPDATE_INFORMATION}"
    )
  created_files+=(
    "${appimage}.zsync" # this file will contain delta update data
    )
else
  cat >&2 <<EOF
$0: Automatic updates disabled.
To enable automatic updates, please set the env. variable UPDATE_INFORMATION
according to <https://github.com/AppImage/AppImageSpec/blob/master/draft.md>.
EOF
fi

# create AppImage
appimagetool "${appimagetool_args[@]}" "${appdir}" "${appimage}"

# The type-2 runtime loads libfuse before mounting the embedded SquashFS. A
# copy inside the image cannot satisfy that bootstrap dependency, so emit a
# sibling launcher that extracts and runs AppRun when host FUSE is unavailable.
launcher="${appimage}.run"
cat > "${launcher}" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
appimage="${script_dir}/$(basename -- "${BASH_SOURCE[0]}" .run)"
[[ -x "${appimage}" ]] || { echo "error: missing AppImage: ${appimage}" >&2; exit 1; }

case "${1:-}" in
  --appimage-*) exec "${appimage}" "$@" ;;
esac

if [[ "${MUSESCORE_APPIMAGE_FORCE_EXTRACT:-0}" != "1" ]]; then
  if [[ "${APPIMAGE_EXTRACT_AND_RUN:-}" == "1" ]]; then
    exec env APPIMAGE_EXTRACT_AND_RUN=1 "${appimage}" "$@"
  fi
  if command -v ldconfig >/dev/null 2>&1 \
      && ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
    exec "${appimage}" "$@"
  fi
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/musescore-appimage.XXXXXX")"
cleanup() { rm -rf "${work_dir}"; }
trap cleanup EXIT INT TERM

extract_appimage() {
  # Prefer an installed unsquashfs when available. This path does not execute
  # the AppImage ELF runtime at all, which also works on systems where the
  # runtime's FUSE bootstrap cannot be loaded.
  if command -v unsquashfs >/dev/null 2>&1; then
    local offset=""
    while IFS=: read -r offset _; do
      [[ -n "${offset}" ]] || continue
      rm -rf "${work_dir}/squashfs-root"
      if unsquashfs -q -o "${offset}" -d "${work_dir}/squashfs-root" \
          "${appimage}" >/dev/null 2>&1; then
        return 0
      fi
    done < <(LC_ALL=C grep -abo 'hsqs' "${appimage}")
  fi
  (cd "${work_dir}" && "${appimage}" --appimage-extract >/dev/null 2>&1)
}

if ! extract_appimage; then
  exec env APPIMAGE_EXTRACT_AND_RUN=1 "${appimage}" "$@"
fi
appdir="${work_dir}/squashfs-root"
[[ -x "${appdir}/AppRun" ]] || { echo "error: AppImage extraction did not produce AppRun" >&2; exit 1; }
export LD_LIBRARY_PATH="${appdir}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
APPIMAGE="${appimage}" APPDIR="${appdir}" "${appdir}/AppRun" "$@"
status=$?
exit "${status}"
EOF
chmod +x "${launcher}"

# We are running as root in the Docker image so all created files belong to
# root. Allow non-root users outside the Docker image to access these files.
created_files+=("${launcher}")
chmod a+rwx "${created_files[@]}"
parent_dir="${PWD}"
while [[ "$(dirname "${parent_dir}")" != "${parent_dir}" ]]; do
  [[ "$parent_dir" == "/" ]] && break
  chmod a+rwx "$parent_dir"
  parent_dir="$(dirname "$parent_dir")"
done

echo "Making AppImage finished"
