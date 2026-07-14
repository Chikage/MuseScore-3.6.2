#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$ROOT_DIR}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/build.artifacts/linux}"
BUILD_ROOT="$ROOT_DIR/build.linux"
UBUNTU_IMAGE="${UBUNTU_IMAGE:-ubuntu:20.04}"
USE_DOCKER_BUILDER_IMAGE="${USE_DOCKER_BUILDER_IMAGE:-1}"
DOCKER_BUILDER_IMAGE="${DOCKER_BUILDER_IMAGE:-}"
DOCKER_REBUILD_BUILDER_IMAGE="${DOCKER_REBUILD_BUILDER_IMAGE:-0}"
DOCKER_CPUS="${DOCKER_CPUS:-}"
DOCKER_MEMORY="${DOCKER_MEMORY:-}"
DOCKER_MEMORY_SWAP="${DOCKER_MEMORY_SWAP:-}"
ARCHES_RAW="${ARCHES:-host}"
FORMATS_RAW="${FORMATS:-tbz2}"
USE_DOCKER="${USE_DOCKER:-auto}"
INSIDE_CONTAINER=0
INSTALL_DEPS="${INSTALL_DEPS:-1}"
CLEAN="${CLEAN:-0}"
CLEAN_ONLY="${CLEAN_ONLY:-0}"
JOBS="${JOBS:-}"
SCRIPT_START_TIME=$SECONDS

BUILD_NUMBER="${BUILD_NUMBER:-0}"
MUSESCORE_BUILD_CONFIG="${MUSESCORE_BUILD_CONFIG:-release}"
MUSESCORE_REVISION="${MUSESCORE_REVISION:-}"
TELEMETRY_TRACK_ID="${TELEMETRY_TRACK_ID:-}"

BUILD_LAME="${BUILD_LAME:-ON}"
BUILD_PULSEAUDIO="${BUILD_PULSEAUDIO:-ON}"
BUILD_JACK="${BUILD_JACK:-ON}"
BUILD_ALSA="${BUILD_ALSA:-ON}"
BUILD_PORTAUDIO="${BUILD_PORTAUDIO:-ON}"
BUILD_PORTMIDI="${BUILD_PORTMIDI:-ON}"
BUILD_WEBENGINE="${BUILD_WEBENGINE:-ON}"
BUILD_PCH="${BUILD_PCH:-OFF}"
USE_SYSTEM_FREETYPE="${USE_SYSTEM_FREETYPE:-ON}"
DOWNLOAD_SOUNDFONT="${DOWNLOAD_SOUNDFONT:-OFF}"
USE_ZITA_REVERB="${USE_ZITA_REVERB:-ON}"

die() {
  echo "error: $*" >&2
  exit 1
}

log() {
  printf '\n==> %s\n' "$*"
}

print_elapsed_time() {
  [ "${MUSESCORE_PRINT_ELAPSED:-1}" = "1" ] || return 0

  local elapsed=$((SECONDS - SCRIPT_START_TIME))
  local hours=$((elapsed / 3600))
  local minutes=$(((elapsed % 3600) / 60))
  local seconds=$((elapsed % 60))

  printf '\n==> Total elapsed time: %02d:%02d:%02d\n' "$hours" "$minutes" "$seconds"
}

trap print_elapsed_time EXIT

usage() {
  cat <<'EOF'
Usage: ./build-linux.sh [options]

Build MuseScore 3.6.2 Linux artifacts for x86_64 and arm64.

Options:
  -a, --arch LIST          all, host, x86_64, amd64, arm64, aarch64
                           Default: host
  -f, --format LIST        all, appimage, deb, tbz2
                           Default: tbz2
      --deb                Build only the Debian package, same as --format deb
      --docker             Force Docker builds
      --no-docker          Build directly on this Linux system
      --inside-container   Internal flag used by Docker mode
      --skip-deps          Do not install apt build dependencies
      --clean              Remove the selected build directories first
      --clean-only         Remove the selected build directories and exit
      --jobs N             Parallel build jobs
      --ubuntu-image IMG   Docker image, default ubuntu:20.04
      --docker-builder-image IMG
                           Build/reuse a dependency image instead of apt installing every run
      --no-docker-builder-image
                           Use --ubuntu-image directly and install dependencies in each run
      --rebuild-docker-builder-image
                           Rebuild the dependency image without Docker layer cache
      --docker-cpus N      Limit container CPUs, e.g. 8
      --docker-memory SIZE Limit container RAM, e.g. 24g
      --docker-memory-swap SIZE
                           Limit container RAM+swap, e.g. 32g or -1 for unlimited
      --artifacts-dir DIR  Output directory, default build.artifacts/linux
  -h, --help               Show this help

Useful environment overrides:
  BUILD_WEBENGINE=OFF      Disable Qt WebEngine if the target distro lacks it
  BUILD_PCH=ON             Enable precompiled headers for faster but heavier builds
  USE_DOCKER_BUILDER_IMAGE=0
                           Disable the reusable Docker dependency image
  DOCKER_REBUILD_BUILDER_IMAGE=1
                           Same as --rebuild-docker-builder-image
  DOCKER_CPUS=8            Same as --docker-cpus 8
  DOCKER_MEMORY=24g        Same as --docker-memory 24g
  DOWNLOAD_SOUNDFONT=ON    Let CMake refresh the bundled SoundFont
  BUILD_NUMBER=123         Package build number passed to CMake
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -a|--arch)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      ARCHES_RAW="$2"
      shift 2
      ;;
    -f|--format)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      FORMATS_RAW="$2"
      shift 2
      ;;
    --deb)
      FORMATS_RAW="deb"
      shift
      ;;
    --docker)
      USE_DOCKER=1
      shift
      ;;
    --no-docker)
      USE_DOCKER=0
      shift
      ;;
    --inside-container)
      INSIDE_CONTAINER=1
      shift
      ;;
    --skip-deps)
      INSTALL_DEPS=0
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
      [ "$#" -ge 2 ] || die "$1 requires a value"
      JOBS="$2"
      shift 2
      ;;
    --ubuntu-image)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      UBUNTU_IMAGE="$2"
      shift 2
      ;;
    --docker-builder-image)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      USE_DOCKER_BUILDER_IMAGE=1
      DOCKER_BUILDER_IMAGE="$2"
      shift 2
      ;;
    --no-docker-builder-image)
      USE_DOCKER_BUILDER_IMAGE=0
      shift
      ;;
    --rebuild-docker-builder-image)
      DOCKER_REBUILD_BUILDER_IMAGE=1
      shift
      ;;
    --docker-cpus)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      DOCKER_CPUS="$2"
      shift 2
      ;;
    --docker-memory)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      DOCKER_MEMORY="$2"
      shift 2
      ;;
    --docker-memory-swap)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      DOCKER_MEMORY_SWAP="$2"
      shift 2
      ;;
    --artifacts-dir)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      ARTIFACTS_DIR="$2"
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

if [ -n "$DOCKER_MEMORY_SWAP" ] && [ -z "$DOCKER_MEMORY" ]; then
  die "--docker-memory-swap requires --docker-memory"
fi

if [ "$CLEAN_ONLY" = "1" ]; then
  CLEAN=1
fi

cpu_count() {
  getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN 2>/dev/null || echo 1
}

if [ -z "$JOBS" ]; then
  case "$DOCKER_CPUS" in
    ''|0|*[!0-9]*) JOBS="$(cpu_count)" ;;
    *) JOBS="$DOCKER_CPUS" ;;
  esac
fi

normalize_arch() {
  case "$1" in
    x86_64|amd64) echo "x86_64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) die "unsupported architecture '$1' (use x86_64 or arm64)" ;;
  esac
}

appimage_arch() {
  case "$1" in
    x86_64) echo "x86_64" ;;
    arm64) echo "aarch64" ;;
    *) die "unsupported architecture '$1'" ;;
  esac
}

docker_platform() {
  case "$1" in
    x86_64) echo "linux/amd64" ;;
    arm64) echo "linux/arm64" ;;
    *) die "unsupported architecture '$1'" ;;
  esac
}

expand_arches() {
  local raw="$1"
  local out=""
  local token=""
  local norm=""

  if [ "$raw" = "all" ]; then
    raw="x86_64 arm64"
  elif [ "$raw" = "host" ]; then
    raw="$(uname -m)"
  fi

  raw="$(printf '%s' "$raw" | tr ',' ' ')"
  for token in $raw; do
    norm="$(normalize_arch "$token")"
    case " $out " in
      *" $norm "*) ;;
      *) [ -n "$out" ] && out="$out $norm" || out="$norm" ;;
    esac
  done

  echo "$out"
}

normalize_format() {
  case "$1" in
    appimage|AppImage|APPIMAGE) echo "appimage" ;;
    deb|DEB) echo "deb" ;;
    tbz2|TBZ2|tar.bz2) echo "tbz2" ;;
    *) die "unsupported format '$1' (use appimage, deb, tbz2, or all)" ;;
  esac
}

expand_formats() {
  local raw="$1"
  local out=""
  local token=""
  local norm=""

  if [ "$raw" = "all" ]; then
    raw="appimage deb tbz2"
  fi

  raw="$(printf '%s' "$raw" | tr ',' ' ')"
  for token in $raw; do
    norm="$(normalize_format "$token")"
    case " $out " in
      *" $norm "*) ;;
      *) [ -n "$out" ] && out="$out $norm" || out="$norm" ;;
    esac
  done

  echo "$out"
}

contains_word() {
  case " $1 " in
    *" $2 "*) return 0 ;;
    *) return 1 ;;
  esac
}

has_foreign_arch_targets() {
  local host_arch=""
  local arch=""

  [ "$(uname -s)" = "Linux" ] || return 1
  host_arch="$(normalize_arch "$(uname -m)")"
  for arch in $ARCHES; do
    [ "$arch" = "$host_arch" ] || return 0
  done

  return 1
}

binfmt_handler_for_arch() {
  case "$1" in
    x86_64) echo "qemu-x86_64" ;;
    arm64) echo "qemu-aarch64" ;;
    *) die "unsupported architecture '$1'" ;;
  esac
}

ensure_foreign_arch_emulation() {
  has_foreign_arch_targets || return 0

  local host_arch=""
  local arch=""
  local handler=""
  local registration=""
  local root_cmd=()

  if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || die "sudo is required to enable QEMU binfmt for cross-architecture builds"
    root_cmd=(sudo)
  fi

  command -v update-binfmts >/dev/null 2>&1 ||
    die "update-binfmts was not found; install binfmt-support and qemu-user-static, or use --docker"

  if [ ! -e /proc/sys/fs/binfmt_misc/register ]; then
    "${root_cmd[@]}" mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc >/dev/null 2>&1 || true
  fi

  host_arch="$(normalize_arch "$(uname -m)")"
  for arch in $ARCHES; do
    [ "$arch" = "$host_arch" ] && continue

    handler="$(binfmt_handler_for_arch "$arch")"
    registration="/proc/sys/fs/binfmt_misc/$handler"
    if [ -r "$registration" ] && grep -q '^enabled' "$registration"; then
      continue
    fi

    "${root_cmd[@]}" update-binfmts --enable "$handler" >/dev/null 2>&1 || true
    if [ ! -r "$registration" ] || ! grep -q '^enabled' "$registration"; then
      die "QEMU binfmt handler '$handler' is unavailable; install/enable qemu-user-static or rerun with --docker"
    fi
  done
}

artifact_abs_path() {
  local path="$1"
  local dir=""
  local base=""

  if command -v realpath >/dev/null 2>&1; then
    realpath "$path" 2>/dev/null && return 0
  fi

  dir="$(cd "$(dirname "$path")" && pwd)"
  base="$(basename "$path")"
  printf '%s/%s\n' "$dir" "$base"
}

artifact_format() {
  case "$1" in
    *.AppImage) echo "appimage" ;;
    *.deb) echo "deb" ;;
    *.tar.bz2|*.tbz2) echo "tbz2" ;;
    *) echo "package" ;;
  esac
}

artifact_size() {
  local size=""

  if size="$(du -h "$1" 2>/dev/null | awk '{print $1}')"; then
    if [ -n "$size" ]; then
      echo "$size"
      return 0
    fi
  fi

  if size="$(wc -c < "$1" 2>/dev/null)"; then
    size="${size//[[:space:]]/}"
    echo "${size}B"
    return 0
  fi

  echo "-"
}

find_artifact_files() {
  [ -d "$ARTIFACTS_DIR" ] || return 0

  find "$ARTIFACTS_DIR" -type f \
    \( -name '*.AppImage' -o -name '*.deb' -o -name '*.tar.bz2' -o -name '*.tbz2' \) \
    ! -path "$ARTIFACTS_DIR/latest/*" | sort
}

artifact_arch_from_path() {
  local artifact="$1"
  local rel=""
  local arch=""

  rel="${artifact#$ARTIFACTS_DIR/}"
  arch="${rel%%/*}"
  if [ "$arch" = "$rel" ] || [ -z "$arch" ]; then
    echo "-"
  else
    echo "$arch"
  fi
}

link_artifact_in_latest() {
  local artifact="$1"
  local arch="$2"
  local format="$3"
  local latest_dir="$4"
  local base=""
  local safe_arch=""
  local link=""
  local abs=""

  base="$(basename "$artifact")"
  safe_arch="$(printf '%s' "$arch" | tr -c '[:alnum:]_.-' '_')"
  link="$latest_dir/${safe_arch}-${format}-${base}"
  abs="$(artifact_abs_path "$artifact")"

  rm -f "$link"
  ln -s "$abs" "$link" 2>/dev/null || cp -f "$artifact" "$link"
}

refresh_artifact_index() {
  local latest_dir="$ARTIFACTS_DIR/latest"
  local manifest="$ARTIFACTS_DIR/manifest.txt"
  local artifact=""
  local arch=""
  local format=""
  local size=""
  local count=0

  mkdir -p "$ARTIFACTS_DIR"
  rm -rf "$latest_dir"
  mkdir -p "$latest_dir"

  {
    printf 'MuseScore Linux build artifacts\n'
    printf 'Generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'Artifacts directory: %s\n\n' "$(artifact_abs_path "$ARTIFACTS_DIR")"
    printf '%-10s %-10s %-10s %s\n' "ARCH" "FORMAT" "SIZE" "PATH"

    while IFS= read -r artifact; do
      [ -n "$artifact" ] || continue
      arch="$(artifact_arch_from_path "$artifact")"
      format="$(artifact_format "$artifact")"
      size="$(artifact_size "$artifact")"
      link_artifact_in_latest "$artifact" "$arch" "$format" "$latest_dir"
      printf '%-10s %-10s %-10s %s\n' "$arch" "$format" "$size" "$(artifact_abs_path "$artifact")"
      count=$((count + 1))
    done < <(find_artifact_files)

    if [ "$count" -eq 0 ]; then
      printf '\nNo AppImage/DEB/TBZ2 artifacts found.\n'
    fi
  } > "$manifest"
}

print_artifact_summary() {
  local latest_dir="$ARTIFACTS_DIR/latest"
  local manifest="$ARTIFACTS_DIR/manifest.txt"
  local artifact=""
  local arch=""
  local format=""
  local size=""
  local count=0

  log "Linux build artifacts"
  printf 'Artifacts directory: %s\n' "$(artifact_abs_path "$ARTIFACTS_DIR")"
  printf 'Latest shortcuts:    %s\n' "$(artifact_abs_path "$latest_dir")"
  printf 'Manifest:            %s\n' "$(artifact_abs_path "$manifest")"

  while IFS= read -r artifact; do
    [ -n "$artifact" ] || continue
    arch="$(artifact_arch_from_path "$artifact")"
    format="$(artifact_format "$artifact")"
    size="$(artifact_size "$artifact")"
    printf '  - [%s/%s] %s (%s)\n' "$arch" "$format" "$(artifact_abs_path "$artifact")" "$size"
    count=$((count + 1))
  done < <(find_artifact_files)

  if [ "$count" -eq 0 ]; then
    printf '  No AppImage/DEB/TBZ2 artifacts were found.\n'
  fi
}

ARCHES="$(expand_arches "$ARCHES_RAW")"
FORMATS="$(expand_formats "$FORMATS_RAW")"

clean_selected_build_dirs() {
  local arch=""

  for arch in $ARCHES; do
    if contains_word "$FORMATS" "appimage"; then
      log "Removing build.linux/$arch-appimage"
      rm -rf "$BUILD_ROOT/$arch-appimage"
    fi

    if contains_word "$FORMATS" "deb" || contains_word "$FORMATS" "tbz2"; then
      log "Removing build.linux/$arch-package"
      rm -rf "$BUILD_ROOT/$arch-package"
    fi
  done
}

if [ "$CLEAN_ONLY" = "1" ]; then
  clean_selected_build_dirs
  log "Clean completed"
  exit 0
fi

needs_docker() {
  local host_arch=""
  local arch=""

  [ "$INSIDE_CONTAINER" -eq 1 ] && return 1
  [ "$USE_DOCKER" = "1" ] && return 0
  [ "$USE_DOCKER" = "0" ] && return 1
  [ "$(uname -s)" != "Linux" ] && return 0

  host_arch="$(normalize_arch "$(uname -m)")"
  for arch in $ARCHES; do
    [ "$arch" = "$host_arch" ] || return 0
  done

  return 1
}

apt_dependency_packages() {
  cat <<'EOF'
appstream
binutils
build-essential
ca-certificates
cmake
curl
desktop-file-utils
dpkg-dev
fakeroot
file
g++
gcc
git
gzip
libasound2-dev
libcups2-dev
libdrm-dev
libegl1-mesa-dev
libfontconfig1-dev
libfreetype6-dev
libgl1-mesa-dev
libjack-jackd2-dev
libmp3lame-dev
libnss3-dev
libogg-dev
libpoppler-qt5-dev
libportmidi-dev
libpulse-dev
libsndfile1-dev
libssl-dev
libvorbis-dev
libxcomposite-dev
libxcursor-dev
libxi-dev
libxkbcommon-x11-0
libxml2-utils
libxrandr-dev
libxtst-dev
make
patchelf
pkg-config
portaudio19-dev
qml-module-qtgraphicaleffects
qml-module-qtqml-models2
qml-module-qtquick-controls
qml-module-qtquick-controls2
qml-module-qtquick-dialogs
qml-module-qtquick-layouts
qml-module-qtquick-window2
qml-module-qtquick2
qt5-qmake
qtbase5-dev
qtbase5-dev-tools
qtdeclarative5-dev
libqt5opengl5-dev
libqt5svg5-dev
libqt5xmlpatterns5-dev
qtquickcontrols2-5-dev
qtscript5-dev
qttools5-dev
qttools5-dev-tools
squashfs-tools
wget
xz-utils
zlib1g-dev
EOF
}

apt_webengine_packages() {
  cat <<'EOF'
qtwebengine5-dev
EOF
}

apt_fuse_package() {
  if command -v apt-cache >/dev/null 2>&1; then
    if apt-cache show libfuse2 >/dev/null 2>&1; then
      echo "libfuse2"
      return 0
    fi
    if apt-cache show libfuse2t64 >/dev/null 2>&1; then
      echo "libfuse2t64"
      return 0
    fi
  fi

  echo "libfuse2"
}

docker_safe_tag_component() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/-/g'
}

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    cksum | awk '{print $1 "-" $2}'
  fi
}

docker_builder_image_for_arch() {
  local arch="$1"
  local base_tag=""

  if [ -n "$DOCKER_BUILDER_IMAGE" ]; then
    echo "$DOCKER_BUILDER_IMAGE"
    return 0
  fi

  base_tag="$(docker_safe_tag_component "$UBUNTU_IMAGE")"
  echo "musescore-linux-builder:${base_tag}-${arch}"
}

docker_builder_env_key() {
  local arch="$1"

  {
    printf 'base=%s\n' "$UBUNTU_IMAGE"
    printf 'arch=%s\n' "$arch"
    printf 'build_webengine=%s\n' "$BUILD_WEBENGINE"
    printf 'appimage_fuse_runtime=libfuse2-or-libfuse2t64\n'
    apt_dependency_packages
    [ "$BUILD_WEBENGINE" = "ON" ] && apt_webengine_packages
  } | sha256_text
}

ensure_docker_builder_image() {
  local platform="$1"
  local arch="$2"
  local image="$3"
  local build_env_key=""
  local current_env_key=""
  local docker_build_args=()
  local packages=""

  build_env_key="$(docker_builder_env_key "$arch")"
  if [ "$DOCKER_REBUILD_BUILDER_IMAGE" != "1" ]; then
    current_env_key="$(docker image inspect --format '{{ index .Config.Labels "org.musescore.build-env-key" }}' "$image" 2>/dev/null || true)"
    if [ "$current_env_key" = "$build_env_key" ]; then
      log "Using cached Docker builder image $image ($platform)"
      return 0
    fi
  fi

  if [ "$BUILD_WEBENGINE" = "ON" ]; then
    packages="$(printf '%s\n%s\n' "$(apt_dependency_packages)" "$(apt_webengine_packages)" | tr '\n' ' ')"
  else
    packages="$(apt_dependency_packages | tr '\n' ' ')"
  fi

  docker_build_args=(
    --platform "$platform"
    --build-arg BASE_IMAGE="$UBUNTU_IMAGE"
    --build-arg BUILD_ENV_KEY="$build_env_key"
    -t "$image"
  )
  if [ "$DOCKER_REBUILD_BUILDER_IMAGE" = "1" ]; then
    docker_build_args+=(--pull --no-cache)
  fi

  log "Preparing Docker builder image $image ($platform)"
  docker build "${docker_build_args[@]}" - <<EOF
ARG BASE_IMAGE=$UBUNTU_IMAGE
FROM \${BASE_IMAGE}
ARG BUILD_ENV_KEY
LABEL org.musescore.build-env-key="\${BUILD_ENV_KEY}"
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \\
    && apt-get install -y --no-install-recommends ${packages} \\
    && if apt-cache show libfuse2 >/dev/null 2>&1; then \\
         apt-get install -y --no-install-recommends libfuse2; \\
       else \\
         apt-get install -y --no-install-recommends libfuse2t64; \\
       fi \\
    && rm -rf /var/lib/apt/lists/*
EOF
}

run_docker_builds() {
  command -v docker >/dev/null 2>&1 || die "Docker is required for cross/Linux builds from this host"

  local arch=""
  local platform=""
  local image=""
  local install_deps=""
  local docker_run_args=()
  local uid=""
  local gid=""
  local host_artifacts_dir=""

  uid="$(id -u)"
  gid="$(id -g)"
  mkdir -p "$ARTIFACTS_DIR"
  host_artifacts_dir="$(artifact_abs_path "$ARTIFACTS_DIR")"

  for arch in $ARCHES; do
    platform="$(docker_platform "$arch")"
    image="$UBUNTU_IMAGE"
    install_deps="$INSTALL_DEPS"
    if [ "$USE_DOCKER_BUILDER_IMAGE" = "1" ]; then
      image="$(docker_builder_image_for_arch "$arch")"
      ensure_docker_builder_image "$platform" "$arch" "$image"
      install_deps=0
    fi

    log "Docker build for $arch ($platform) using $image"
    docker_run_args=(--rm --platform "$platform")
    [ -n "$DOCKER_CPUS" ] && docker_run_args+=(--cpus "$DOCKER_CPUS")
    [ -n "$DOCKER_MEMORY" ] && docker_run_args+=(--memory "$DOCKER_MEMORY")
    [ -n "$DOCKER_MEMORY_SWAP" ] && docker_run_args+=(--memory-swap "$DOCKER_MEMORY_SWAP")

    docker run "${docker_run_args[@]}" \
      -e DEBIAN_FRONTEND=noninteractive \
      -e HOST_UID="$uid" \
      -e HOST_GID="$gid" \
      -e INSTALL_DEPS="$install_deps" \
      -e CLEAN="$CLEAN" \
      -e MUSESCORE_PRINT_ELAPSED=0 \
      -e JOBS="$JOBS" \
      -e BUILD_NUMBER="$BUILD_NUMBER" \
      -e MUSESCORE_BUILD_CONFIG="$MUSESCORE_BUILD_CONFIG" \
      -e MUSESCORE_REVISION="$MUSESCORE_REVISION" \
      -e TELEMETRY_TRACK_ID="$TELEMETRY_TRACK_ID" \
      -e BUILD_LAME="$BUILD_LAME" \
      -e BUILD_PULSEAUDIO="$BUILD_PULSEAUDIO" \
      -e BUILD_JACK="$BUILD_JACK" \
      -e BUILD_ALSA="$BUILD_ALSA" \
      -e BUILD_PORTAUDIO="$BUILD_PORTAUDIO" \
      -e BUILD_PORTMIDI="$BUILD_PORTMIDI" \
      -e BUILD_WEBENGINE="$BUILD_WEBENGINE" \
      -e BUILD_PCH="$BUILD_PCH" \
      -e USE_SYSTEM_FREETYPE="$USE_SYSTEM_FREETYPE" \
      -e DOWNLOAD_SOUNDFONT="$DOWNLOAD_SOUNDFONT" \
      -e USE_ZITA_REVERB="$USE_ZITA_REVERB" \
      -v "$ROOT_DIR:/work" \
      -v "$host_artifacts_dir:/work/build.artifacts/linux" \
      -w /work \
      "$image" \
      bash ./build-linux.sh --inside-container --no-docker --arch "$arch" --format "$FORMATS" --artifacts-dir /work/build.artifacts/linux
  done
}

if needs_docker; then
  run_docker_builds
  refresh_artifact_index
  print_artifact_summary
  exit 0
fi

[ "$(uname -s)" = "Linux" ] || die "--no-docker mode requires Linux"

install_apt_dependencies() {
  [ "$INSTALL_DEPS" = "1" ] || return 0
  command -v apt-get >/dev/null 2>&1 || die "automatic dependency install currently supports Debian/Ubuntu apt"

  local apt_cmd=()
  local package=""
  local packages=()
  local webengine_packages=()
  if [ "$(id -u)" -eq 0 ]; then
    apt_cmd=(apt-get)
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required to install apt dependencies"
    apt_cmd=(sudo apt-get)
  fi

  log "Installing build dependencies"
  "${apt_cmd[@]}" update

  while IFS= read -r package; do
    [ -n "$package" ] && packages+=("$package")
  done < <(apt_dependency_packages)
  if has_foreign_arch_targets; then
    packages+=(binfmt-support qemu-user-static)
  fi
  packages+=("$(apt_fuse_package)")
  "${apt_cmd[@]}" install -y --no-install-recommends "${packages[@]}"

  if [ "$BUILD_WEBENGINE" = "ON" ]; then
    while IFS= read -r package; do
      [ -n "$package" ] && webengine_packages+=("$package")
    done < <(apt_webengine_packages)
    "${apt_cmd[@]}" install -y --no-install-recommends "${webengine_packages[@]}"
  fi
}

detect_revision() {
  if [ -n "$MUSESCORE_REVISION" ]; then
    echo "$MUSESCORE_REVISION"
  elif git -C "$SOURCE_DIR" rev-parse --short=7 HEAD >/dev/null 2>&1; then
    git -C "$SOURCE_DIR" rev-parse --short=7 HEAD
  else
    echo "exported"
  fi
}

configure_qt_environment() {
  local qmake_bin=""

  qmake_bin="${QMAKE:-}"
  if [ -z "$qmake_bin" ]; then
    qmake_bin="$(command -v qmake 2>/dev/null || true)"
  fi
  if [ -z "$qmake_bin" ]; then
    qmake_bin="$(command -v qmake-qt5 2>/dev/null || true)"
  fi
  [ -n "$qmake_bin" ] || die "qmake was not found"

  export QT_PATH="$("$qmake_bin" -query QT_INSTALL_PREFIX)"
  export QT_PLUGIN_PATH="$("$qmake_bin" -query QT_INSTALL_PLUGINS)"
  export QML2_IMPORT_PATH="$("$qmake_bin" -query QT_INSTALL_QML)"
  export PATH="$("$qmake_bin" -query QT_INSTALL_BINS):$PATH"

  log "Using Qt from $QT_PATH"
}

cmake_common_args() {
  local prefix="$1"
  local suffix="$2"
  local label="$3"
  local skip_rpath="$4"
  local arch="$5"
  local revision="$6"

  CMAKE_ARGS=(
    -G "Unix Makefiles"
    -DCMAKE_BUILD_TYPE=RELEASE
    -DCMAKE_INSTALL_PREFIX="$prefix"
    -DMSCORE_INSTALL_SUFFIX="$suffix"
    -DMUSESCORE_LABEL="$label"
    -DMUSESCORE_BUILD_CONFIG="$MUSESCORE_BUILD_CONFIG"
    -DMUSESCORE_REVISION="$revision"
    -DCMAKE_BUILD_NUMBER="$BUILD_NUMBER"
    -DTELEMETRY_TRACK_ID="$TELEMETRY_TRACK_ID"
    -DBUILD_LAME="$BUILD_LAME"
    -DBUILD_PULSEAUDIO="$BUILD_PULSEAUDIO"
    -DBUILD_PORTMIDI="$BUILD_PORTMIDI"
    -DBUILD_JACK="$BUILD_JACK"
    -DBUILD_ALSA="$BUILD_ALSA"
    -DBUILD_PORTAUDIO="$BUILD_PORTAUDIO"
    -DBUILD_WEBENGINE="$BUILD_WEBENGINE"
    -DBUILD_PCH="$BUILD_PCH"
    -DUSE_SYSTEM_FREETYPE="$USE_SYSTEM_FREETYPE"
    -DDOWNLOAD_SOUNDFONT="$DOWNLOAD_SOUNDFONT"
    -DUSE_ZITA_REVERB="$USE_ZITA_REVERB"
    -DCMAKE_SKIP_RPATH="$skip_rpath"
    -DARCH="$arch"
  )
}

configure_and_build() {
  local build_dir="$1"
  shift

  cmake -S "$SOURCE_DIR" -B "$build_dir" "$@"
  cmake --build "$build_dir" --target lrelease
  cmake --build "$build_dir" -- -j "$JOBS"
}

prepare_portable_appdir() {
  local build_dir="$1"
  local install_dir="$2"
  local mscore="mscore-portable"
  local desktop_src="share/applications/${mscore}.desktop"
  local desktop_dst="${mscore}.desktop"
  local icon_src="share/icons/hicolor/scalable/apps/${mscore}.svg"
  local icon_dst="${mscore}.svg"

  (
    cd "$install_dir"
    [ -L usr ] || ln -s . usr
    if [ ! -e "$desktop_dst" ] || ! cmp -s "$desktop_src" "$desktop_dst"; then
      cp "$desktop_src" "$desktop_dst"
    fi
    if [ ! -e "$icon_dst" ] || ! cmp -s "$icon_src" "$icon_dst"; then
      cp "$icon_src" "$icon_dst"
    fi
    sed -rn 's/.*(share\/)(man|mime|icons|applications)(.*)/\1\2\3/p' \
      < "$build_dir/install_manifest.txt" > install_manifest.txt
  )
}

build_appimage() {
  local arch="$1"
  local ai_arch="$2"
  local revision="$3"
  local build_dir="$BUILD_ROOT/$arch-appimage"
  local out_dir="$ARTIFACTS_DIR/$arch/appimage"
  local install_dir=""
  local version=""
  local appimage_name=""
  local produced=""

  [ "$CLEAN" = "1" ] && rm -rf "$build_dir"
  mkdir -p "$build_dir" "$out_dir"

  log "Configuring AppImage build for $arch"
  cmake_common_args "$build_dir/appdir/MuseScore" "-portable" "Portable AppImage" "TRUE" "$ai_arch" "$revision"
  configure_and_build "$build_dir" "${CMAKE_ARGS[@]}"

  log "Installing portable AppDir for $arch"
  cmake --build "$build_dir" --target install/strip

  [ -f "$build_dir/PREFIX.txt" ] || die "CMake did not produce $build_dir/PREFIX.txt"
  install_dir="$(cat "$build_dir/PREFIX.txt")"
  [ -d "$install_dir" ] || die "AppDir was not created at $install_dir"
  prepare_portable_appdir "$build_dir" "$install_dir"

  version="$(cmake -P "$SOURCE_DIR/config.cmake" | sed -n -e 's/^-- MUSESCORE_VERSION_FULL  *//p')"
  [ -n "$version" ] || version="3.6.2"
  appimage_name="MuseScore-${version}-${ai_arch}.AppImage"

  log "Bundling AppImage for $arch"
  (
    cd "$build_dir"
    APPIMAGE_ARCH="$ai_arch" bash "$SOURCE_DIR/build/ci/linux/tools/make_appimage.sh" "$install_dir" "$appimage_name"
  )

  produced="$(dirname "$install_dir")/$appimage_name"
  [ -f "$produced" ] || die "AppImage was not produced at $produced"
  cp -f "$produced" "$out_dir/"
}

copy_cpack_artifacts() {
  local build_dir="$1"
  local out_dir="$2"
  local requested_formats="$3"

  if contains_word "$requested_formats" "deb"; then
    find "$build_dir" -maxdepth 1 -type f -name '*.deb' -exec cp -f {} "$out_dir/" \;
  fi

  if contains_word "$requested_formats" "tbz2"; then
    find "$build_dir" -maxdepth 1 -type f \( -name '*.tar.bz2' -o -name '*.tbz2' \) -exec cp -f {} "$out_dir/" \;
  fi
}

build_cpack_packages() {
  local arch="$1"
  local ai_arch="$2"
  local revision="$3"
  local requested_formats="$4"
  local build_dir="$BUILD_ROOT/$arch-package"
  local out_dir="$ARTIFACTS_DIR/$arch/package"
  local generator=""
  local generators=()

  contains_word "$requested_formats" "deb" && generators+=(DEB)
  contains_word "$requested_formats" "tbz2" && generators+=(TBZ2)
  [ "${#generators[@]}" -gt 0 ] || return 0

  [ "$CLEAN" = "1" ] && rm -rf "$build_dir"
  mkdir -p "$build_dir" "$out_dir"

  log "Configuring CPack build for $arch"
  cmake_common_args "/usr" "" "" "TRUE" "$ai_arch" "$revision"
  configure_and_build "$build_dir" "${CMAKE_ARGS[@]}"

  for generator in "${generators[@]}"; do
    log "Creating $generator package for $arch"
    (cd "$build_dir" && cpack -G "$generator" --config CPackConfig.cmake)
  done

  copy_cpack_artifacts "$build_dir" "$out_dir" "$requested_formats"
}

fix_ownership() {
  [ "$(id -u)" -eq 0 ] || return 0
  [ -n "${HOST_UID:-}" ] || return 0
  [ -n "${HOST_GID:-}" ] || return 0
  chown -R "$HOST_UID:$HOST_GID" "$ARTIFACTS_DIR" "$BUILD_ROOT" 2>/dev/null || true
}

install_apt_dependencies
ensure_foreign_arch_emulation
configure_qt_environment
REVISION="$(detect_revision)"

mkdir -p "$ARTIFACTS_DIR"

for arch in $ARCHES; do
  ai_arch="$(appimage_arch "$arch")"
  log "Starting $arch build (AppImage arch: $ai_arch)"

  if contains_word "$FORMATS" "appimage"; then
    build_appimage "$arch" "$ai_arch" "$REVISION"
  fi

  if contains_word "$FORMATS" "deb" || contains_word "$FORMATS" "tbz2"; then
    build_cpack_packages "$arch" "$ai_arch" "$REVISION" "$FORMATS"
  fi
done

refresh_artifact_index
fix_ownership
print_artifact_summary
