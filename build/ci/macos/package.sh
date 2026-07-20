#!/usr/bin/env bash

echo "Package MuseScore"
trap 'echo Package failed; exit 1' ERR

ARTIFACTS_DIR="build.artifacts"
SIGN_CERTIFICATE_ENCRYPT_SECRET="''"
SIGN_CERTIFICATE_PASSWORD="''"
MACOS_ARCHITECTURES="${OSX_ARCHITECTURES:-${CMAKE_OSX_ARCHITECTURES:-}}"
QT_MAJOR_VERSION="${QT_MAJOR_VERSION:-${MSCORE_QT_MAJOR_VERSION:-5}}"
QT_PREFIX="${QT_PREFIX:-${QT_MACOS:-}}"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --signsecret) SIGN_CERTIFICATE_ENCRYPT_SECRET="$2"; shift ;;
        --signpass) SIGN_CERTIFICATE_PASSWORD="$2"; shift ;;
        --arch) MACOS_ARCHITECTURES="$2"; shift ;;
        --qt-major) QT_MAJOR_VERSION="$2"; shift ;;
        --qt-prefix) QT_PREFIX="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$SIGN_CERTIFICATE_ENCRYPT_SECRET" ]; then echo "warning: not set SIGN_CERTIFICATE_ENCRYPT_SECRET"; fi
if [ -z "$SIGN_CERTIFICATE_PASSWORD" ]; then echo "warning: not set SIGN_CERTIFICATE_PASSWORD"; fi

echo "SIGN_CERTIFICATE_ENCRYPT_SECRET: $SIGN_CERTIFICATE_ENCRYPT_SECRET"
echo "SIGN_CERTIFICATE_PASSWORD: $SIGN_CERTIFICATE_PASSWORD"
echo "MACOS_ARCHITECTURES: ${MACOS_ARCHITECTURES:-auto}"
echo "QT_MAJOR_VERSION: $QT_MAJOR_VERSION"
echo "QT_PREFIX: ${QT_PREFIX:-auto}"

case "$QT_MAJOR_VERSION" in
    5|6) ;;
    *) echo "Unsupported Qt major version: $QT_MAJOR_VERSION"; exit 1 ;;
esac

mkdir -p applebuild/mscore.app/Contents/Resources/Frameworks
if [ -z "$MACOS_ARCHITECTURES" ] && [ -f applebuild/mscore.app/Contents/MacOS/mscore ]; then
    MACOS_ARCHITECTURES=$(lipo -archs applebuild/mscore.app/Contents/MacOS/mscore)
fi

if [ -z "${MACOS_DEPENDENCIES_URL+x}" ]; then
    if [[ "$MACOS_ARCHITECTURES" == *arm64* ]]; then
        MACOS_DEPENDENCIES_URL=""
    else
        MACOS_DEPENDENCIES_URL="http://utils.musescore.org.s3.amazonaws.com/musescore_dependencies_macos.zip"
    fi
fi

if [ -n "$MACOS_DEPENDENCIES_URL" ]; then
    wget -c --no-check-certificate -nv -O musescore_dependencies_macos.zip "$MACOS_DEPENDENCIES_URL"
    unzip musescore_dependencies_macos.zip -d applebuild/mscore.app/Contents/Resources/Frameworks
else
    echo "Skip prebuilt macOS dependency bundle for $MACOS_ARCHITECTURES"
fi

# install Sparkle when the available framework matches the package architecture
SPARKLE_FRAMEWORK="${MACOS_SPARKLE_FRAMEWORK:-$HOME/Library/Frameworks/Sparkle.framework}"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_BINARY="$SPARKLE_FRAMEWORK/Versions/A/Sparkle"
    SPARKLE_ARCHS=""
    if [ -f "$SPARKLE_BINARY" ]; then
        SPARKLE_ARCHS=$(lipo -archs "$SPARKLE_BINARY" 2>/dev/null || true)
    fi
    if [[ "$MACOS_ARCHITECTURES" == *arm64* && "$SPARKLE_ARCHS" != *arm64* ]]; then
        echo "Skip Sparkle.framework without arm64 slice: $SPARKLE_ARCHS"
    else
        mkdir -p applebuild/mscore.app/Contents/Frameworks
        cp -Rf "$SPARKLE_FRAMEWORK" applebuild/mscore.app/Contents/Frameworks
    fi
else
    echo "Sparkle.framework not found; skip bundling Sparkle"
fi

# The final DMG step only copies and signs an already deployed bundle. Stage
# any optional resources above, then establish and verify the complete runtime
# exactly once before package_mac is allowed to consume it.
DEPLOY_ARGS=(
    --app applebuild/mscore.app
    --qt-major "$QT_MAJOR_VERSION"
)
if [ -n "$QT_PREFIX" ]; then
    DEPLOY_ARGS+=(--qt-prefix "$QT_PREFIX")
fi
scripts/deploy_macos_app.sh "${DEPLOY_ARGS[@]}"

VERIFY_ARGS=(
    --app applebuild/mscore.app
    --qt-major "$QT_MAJOR_VERSION"
)
if [[ "$MACOS_ARCHITECTURES" =~ ^[[:alnum:]_]+$ ]]; then
    VERIFY_ARGS+=(--arch "$MACOS_ARCHITECTURES")
fi
scripts/verify_macos_app.sh "${VERIFY_ARGS[@]}"

# Setup keychain for code sign
if [ "$SIGN_CERTIFICATE_ENCRYPT_SECRET" != "''" ]; then 

    7z x -y ./build/ci/macos/resources/mac_musescore.p12.enc -o./build/ci/macos/resources/ -p${SIGN_CERTIFICATE_ENCRYPT_SECRET}

    export CERTIFICATE_P12=./build/ci/macos/resources/mac_musescore.p12
    export KEYCHAIN=build.keychain
    security create-keychain -p ci $KEYCHAIN
    security default-keychain -s $KEYCHAIN
    security unlock-keychain -p ci $KEYCHAIN
    # Set keychain timeout to 1 hour for long builds
    # see http://www.egeek.me/2013/02/23/jenkins-and-xcode-user-interaction-is-not-allowed/
    security set-keychain-settings -t 3600 -l $KEYCHAIN
    security import $CERTIFICATE_P12 -k $KEYCHAIN -P "$SIGN_CERTIFICATE_PASSWORD" -T /usr/bin/codesign

    security set-key-partition-list -S apple-tool:,apple: -s -k ci $KEYCHAIN
fi

BUILD_MODE=$(cat $ARTIFACTS_DIR/env/build_mode.env)
BUILD_VERSION=$(cat $ARTIFACTS_DIR/env/build_version.env)
BUILD_REVISION=$(cat $ARTIFACTS_DIR/env/build_revision.env)

VERSION_MAJOR="$(cut -d'.' -f1 <<<"$BUILD_VERSION")"
VERSION_MINOR="$(cut -d'.' -f2 <<<"$BUILD_VERSION")"
VERSION_PATCH="$(cut -d'.' -f3 <<<"$BUILD_VERSION")"

APP_LONGER_NAME="MuseScore $VERSION_MAJOR"
PACKAGE_VERSION="$BUILD_VERSION"
if [ "$BUILD_MODE" == "devel_build" ]; then
  APP_LONGER_NAME="MuseScore $BUILD_VERSION Devel"
  PACKAGE_VERSION="${VERSION_MAJOR}.${VERSION_MINOR}b-${BUILD_REVISION}"
fi
if [ "$BUILD_MODE" == "nightly_build" ]; then
  APP_LONGER_NAME="MuseScore $BUILD_VERSION Nightly";
  PACKAGE_VERSION="${VERSION_MAJOR}.${VERSION_MINOR}b-${BUILD_REVISION}"
fi
if [ "$BUILD_MODE" == "testing_build" ]; then
  APP_LONGER_NAME="MuseScore $BUILD_VERSION Testing";
  PACKAGE_VERSION="${VERSION_MAJOR}.${VERSION_MINOR}b-${BUILD_REVISION}"
fi
if [ "$BUILD_MODE" == "stable_build" ]; then
  APP_LONGER_NAME="MuseScore $VERSION_MAJOR";
  PACKAGE_VERSION="${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}"
fi

build/package_mac --longer_name "$APP_LONGER_NAME" --version "$PACKAGE_VERSION"

DMGFILE="$(ls applebuild/*.dmg)"
echo "DMGFILE: $DMGFILE"

if [ "$BUILD_MODE" == "nightly_build" ]; then

  BUILD_DATETIME=$(cat $ARTIFACTS_DIR/env/build_datetime.env)
  BUILD_BRANCH=$(cat $ARTIFACTS_DIR/env/build_branch.env)
  ARTIFACT_NAME=MuseScoreNightly-${BUILD_DATETIME}-${BUILD_BRANCH}-${BUILD_REVISION}

else

  ARTIFACT_NAME=MuseScore-${BUILD_VERSION}

fi

if [[ "$MACOS_ARCHITECTURES" == *arm64* && "$MACOS_ARCHITECTURES" == *x86_64* ]]; then
  ARTIFACT_NAME=${ARTIFACT_NAME}-universal
elif [[ "$MACOS_ARCHITECTURES" == *arm64* ]]; then
  ARTIFACT_NAME=${ARTIFACT_NAME}-arm64
fi

ARTIFACT_NAME=${ARTIFACT_NAME}.dmg

mv $DMGFILE $ARTIFACTS_DIR/$ARTIFACT_NAME

bash ./build/ci/tools/make_artifact_name_env.sh $ARTIFACT_NAME
