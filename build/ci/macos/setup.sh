#!/usr/bin/env bash

echo "Setup MacOS build environment"

trap 'echo Setup failed; exit 1' ERR
SKIP_ERR_FLAG=true

OSX_ARCHITECTURES="${OSX_ARCHITECTURES:-${CMAKE_OSX_ARCHITECTURES:-$(uname -m)}}"
if [[ "$OSX_ARCHITECTURES" == *arm64* ]]; then
  DEFAULT_MACOSX_DEPLOYMENT_TARGET=11.0
else
  DEFAULT_MACOSX_DEPLOYMENT_TARGET=10.10
fi
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$DEFAULT_MACOSX_DEPLOYMENT_TARGET}"

echo "OSX_ARCHITECTURES: $OSX_ARCHITECTURES"
echo "MACOSX_DEPLOYMENT_TARGET: $MACOSX_DEPLOYMENT_TARGET"

brew update >/dev/null | $SKIP_ERR_FLAG

BREW_CELLAR=$(brew --cellar)
BREW_PREFIX=$(brew --prefix)

function fixBrewPath {
  DYLIB_FILE=$1
  BREW_CELLAR=$(brew --cellar)
  BREW_PREFIX=$(brew --prefix)
  chmod 644 $DYLIB_FILE
  # change ID
  DYLIB_ID=$(otool -D  $DYLIB_FILE | tail -n 1)
  if [[ "$DYLIB_ID" == *@@HOMEBREW_CELLAR@@* ]]
  then
      PSLASH=$(echo $DYLIB_ID | sed "s,@@HOMEBREW_CELLAR@@,$BREW_CELLAR,g")
      install_name_tool -id $PSLASH $DYLIB_FILE
  fi
  if [[ "$DYLIB_ID" == *@@HOMEBREW_PREFIX@@* ]]
  then
      PSLASH=$(echo $DYLIB_ID | sed "s,@@HOMEBREW_PREFIX@@,$BREW_PREFIX,g")
      install_name_tool -id $PSLASH $DYLIB_FILE
  fi
  # Change dependencies
  for P in `otool -L $DYLIB_FILE | awk '{print $1}'`
  do
    if [[ "$P" == *@@HOMEBREW_CELLAR@@* ]]
    then
        PSLASH=$(echo $P | sed "s,@@HOMEBREW_CELLAR@@,$BREW_CELLAR,g")
        install_name_tool -change $P $PSLASH $DYLIB_FILE
    fi
    if [[ "$P" == *@@HOMEBREW_PREFIX@@* ]]
    then
        PSLASH=$(echo $P | sed "s,@@HOMEBREW_PREFIX@@,$BREW_PREFIX,g")
        install_name_tool -change $P $PSLASH $DYLIB_FILE
    fi
  done
  chmod 444 $DYLIB_FILE
}
export -f fixBrewPath

function installBottleManually {
  brew unlink $1
  rm -rf "$BREW_CELLAR/$1"
  tar xzvf bottles/$1*.tar.gz -C $BREW_CELLAR
  find $BREW_CELLAR/$1 -type f -name '*.pc' -exec sed -i '' "s:@@HOMEBREW_CELLAR@@:$BREW_CELLAR:g" {} +
  find $BREW_CELLAR/$1 -type f -name '*.dylib' -exec bash -c 'fixBrewPath "$1"' _ {} \;
  brew link $1
}

if [[ "$OSX_ARCHITECTURES" == *arm64* ]]; then
  brew install cmake pkgconf qt@5 jack lame libogg libvorbis flac libsndfile portaudio

  QT_BREW_PREFIX=$(brew --prefix qt@5 2>/dev/null || brew --prefix qt 2>/dev/null || true)
  if [ -z "$QT_MACOS" ] && [ -n "$QT_BREW_PREFIX" ]; then
    export QT_MACOS="$QT_BREW_PREFIX"
  fi
else
  # install dependencies
  wget -c --no-check-certificate -nv -O bottles.zip https://musescore.org/sites/musescore.org/files/2020-02/bottles-MuseScore-3.0-yosemite.zip
  unzip bottles.zip

  # we don't use freetype
  rm bottles/freetype* | $SKIP_ERR_FLAG

  # fixing install python 3.9 error (it is a dependency for JACK)
  rm -f "$BREW_PREFIX/bin/2to3"

  # additional dependencies
  brew install pkgconf jack lame

  installBottleManually libogg
  installBottleManually libvorbis
  installBottleManually flac
  installBottleManually libsndfile
  installBottleManually portaudio

  export QT_SHORT_VERSION="${QT_SHORT_VERSION:-5.9}"
  export QT_PATH="${QT_PATH:-$HOME/Qt}"
  export QT_HOST_SPEC="${QT_HOST_SPEC:-clang_64}"
  export QT_MACOS="${QT_MACOS:-$QT_PATH/$QT_SHORT_VERSION/$QT_HOST_SPEC}"
  if [ ! -x "$QT_MACOS/bin/qmake" ]; then
    wget -nv -O qt5.zip https://s3.amazonaws.com/utils.musescore.org/qt598_mac.zip
    mkdir -p $QT_MACOS
    unzip -qq qt5.zip -d $QT_MACOS
    rm qt5.zip
  fi
fi

if [ -n "$QT_MACOS" ]; then
  export PATH=$QT_MACOS/bin:$PATH
  export CMAKE_PREFIX_PATH="$QT_MACOS${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
fi

if [ -n "$GITHUB_ENV" ]; then
  echo "PATH=$PATH" >> "$GITHUB_ENV"
  echo "CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH" >> "$GITHUB_ENV"
  echo "OSX_ARCHITECTURES=$OSX_ARCHITECTURES" >> "$GITHUB_ENV"
  echo "MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET" >> "$GITHUB_ENV"
fi


if [[ "$OSX_ARCHITECTURES" == *arm64* ]]; then
  echo "Skip Sparkle 1.x setup for arm64; provide an arm64-compatible Sparkle.framework separately when BUILD_AUTOUPDATE=ON"
else
  #install sparkle
  export SPARKLE_VERSION=1.20.0
  mkdir Sparkle-${SPARKLE_VERSION}
  cd Sparkle-${SPARKLE_VERSION}
  wget -nv https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.bz2
  tar jxf Sparkle-${SPARKLE_VERSION}.tar.bz2
  cd ..
  mkdir -p ~/Library/Frameworks
  mv Sparkle-${SPARKLE_VERSION}/Sparkle.framework ~/Library/Frameworks/
  rm -rf Sparkle-${SPARKLE_VERSION}
fi

echo "Setup script done"
