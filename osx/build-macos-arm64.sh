#!/usr/bin/env bash
# Build a native arm64 FontForge.app with Homebrew dependencies.
#
# Environment overrides:
#   BUILD_DIR                    CMake binary directory (default: <source>/build-arm64)
#   MACOS_DEPLOYMENT_TARGET      Minimum macOS version (default: current major version)
#   BREW_PREFIX                  Homebrew prefix (default: brew --prefix)
#   FONTFORGE_CODESIGN_IDENTITY  codesign identity (default: "-" ad-hoc)
#   CREATE_DMG=1                 Also create a compressed DMG next to the app
#
# Any extra arguments are passed to the initial cmake configure step.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="${BUILD_DIR:-$SOURCE_DIR/build-arm64}"
BREW_PREFIX="${BREW_PREFIX:-$(brew --prefix)}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-$(sw_vers -productVersion | cut -d. -f1)}"
FONTFORGE_CODESIGN_IDENTITY="${FONTFORGE_CODESIGN_IDENTITY:--}"
export FONTFORGE_CODESIGN_IDENTITY

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "error: this script builds native arm64 binaries and must run on Apple Silicon." >&2
    exit 1
fi

echo "Source:            $SOURCE_DIR"
echo "Build directory:   $BUILD_DIR"
echo "Homebrew prefix:   $BREW_PREFIX"
echo "Deployment target: macOS $MACOS_DEPLOYMENT_TARGET"
echo "Codesign identity: $FONTFORGE_CODESIGN_IDENTITY"

cmake -GNinja \
    -S "$SOURCE_DIR" \
    -B "$BUILD_DIR" \
    -DCMAKE_PREFIX_PATH="$BREW_PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
    -DENABLE_DOCS=OFF \
    "$@"

cmake --build "$BUILD_DIR" --target macbundle --parallel

APP="$BUILD_DIR/osx/FontForge.app"
file "$APP/Contents/Resources/opt/local/bin/fontforge"

echo
echo "Built: $APP"

if [[ "${CREATE_DMG:-0}" == "1" ]]; then
    DMG="$BUILD_DIR/FontForge-arm64.dmg"
    hdiutil create -size 800m -volname FontForge -srcfolder "$APP" -ov -format UDBZ "$DMG"
    echo "Built: $DMG"
fi
