#!/usr/bin/env bash

echo "Build MuseScore"
#set -x
trap 'echo Build failed; exit 1' ERR
SKIP_ERR=true

ARTIFACTS_DIR=build.artifacts
TELEMETRY_TRACK_ID=""
BUILD_UI_MU4=OFF 		# not used, only for easier synchronization and compatibility
OSX_ARCHITECTURES="${OSX_ARCHITECTURES:-}"
OSX_DEPLOYMENT_TARGET="${OSX_DEPLOYMENT_TARGET:-}"
OSX_GENERATOR="${OSX_GENERATOR:-}"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -n|--number) BUILD_NUMBER="$2"; shift ;;
        --telemetry) TELEMETRY_TRACK_ID="$2"; shift ;;
        --build_mu4) BUILD_UI_MU4="$2"; shift;;
        --arch) OSX_ARCHITECTURES="$2"; shift ;;
        --deployment-target) OSX_DEPLOYMENT_TARGET="$2"; shift ;;
        --generator) OSX_GENERATOR="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$BUILD_NUMBER" ]; then echo "error: not set BUILD_NUMBER"; exit 1; fi
if [ -z "$TELEMETRY_TRACK_ID" ]; then TELEMETRY_TRACK_ID=""; fi

BUILD_MODE=$(cat $ARTIFACTS_DIR/env/build_mode.env)
MUSESCORE_BUILD_CONFIG=dev
if [ "$BUILD_MODE" == "devel_build" ]; then MUSESCORE_BUILD_CONFIG=dev; fi
if [ "$BUILD_MODE" == "nightly_build" ]; then MUSESCORE_BUILD_CONFIG=dev; fi
if [ "$BUILD_MODE" == "testing_build" ]; then MUSESCORE_BUILD_CONFIG=testing; fi
if [ "$BUILD_MODE" == "stable_build" ]; then MUSESCORE_BUILD_CONFIG=release; fi

echo "MUSESCORE_BUILD_CONFIG: $MUSESCORE_BUILD_CONFIG"
echo "BUILD_NUMBER: $BUILD_NUMBER"
echo "TELEMETRY_TRACK_ID: $TELEMETRY_TRACK_ID"
echo "BUILD_UI_MU4: $BUILD_UI_MU4"
echo "OSX_ARCHITECTURES: ${OSX_ARCHITECTURES:-auto}"
echo "OSX_DEPLOYMENT_TARGET: ${OSX_DEPLOYMENT_TARGET:-auto}"
echo "OSX_GENERATOR: ${OSX_GENERATOR:-auto}"

MUSESCORE_REVISION=$(git rev-parse --short=7 HEAD)

MAKE_ARGS=()
if [ -n "$OSX_ARCHITECTURES" ]; then MAKE_ARGS+=(OSX_ARCHITECTURES="$OSX_ARCHITECTURES"); fi
if [ -n "$OSX_DEPLOYMENT_TARGET" ]; then MAKE_ARGS+=(OSX_DEPLOYMENT_TARGET="$OSX_DEPLOYMENT_TARGET"); fi
if [ -n "$OSX_GENERATOR" ]; then MAKE_ARGS+=(OSX_GENERATOR="$OSX_GENERATOR"); fi

make -f Makefile.osx \
    MUSESCORE_BUILD_CONFIG=$MUSESCORE_BUILD_CONFIG \
    MUSESCORE_REVISION=$MUSESCORE_REVISION \
    BUILD_NUMBER=$BUILD_NUMBER \
    TELEMETRY_TRACK_ID=$TELEMETRY_TRACK_ID \
    "${MAKE_ARGS[@]}" \
    ci


bash ./build/ci/tools/make_release_channel_env.sh -c $MUSESCORE_BUILD_CONFIG
bash ./build/ci/tools/make_version_env.sh $BUILD_NUMBER
bash ./build/ci/tools/make_revision_env.sh $MUSESCORE_REVISION
bash ./build/ci/tools/make_branch_env.sh
bash ./build/ci/tools/make_datetime_env.sh
