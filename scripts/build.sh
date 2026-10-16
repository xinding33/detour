#!/bin/bash
# Builds dist/Detour.app and dist/Detour.zip.
#
#   APP_VERSION    version to stamp (releases pass it from the tag; default: latest tag, else 0.0.0)
#   SIGN_IDENTITY  codesign identity (default: this Mac's Developer ID if it has one, else ad hoc)
#   APP_BUILD      "development" (default) or "release". Only release builds install updates.
#   ARCHS          "arm64" (default) or "arm64 x86_64" (releases)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${APP_VERSION:-$( (git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true) | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
BUILD="${APP_BUILD:-development}"
# A stable identity keeps Accessibility and other privacy grants across rebuilds. Ad hoc
# signatures change every build, so macOS treats each build as a new app.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
IDENTITY="${IDENTITY:--}"

ARCH_FLAGS=()
for arch in ${ARCHS:-arm64}; do ARCH_FLAGS+=(--arch "$arch"); done
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf dist
APP="$PWD/dist/Detour.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Detour" "$APP/Contents/MacOS/Detour"
cp scripts/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace DetourBuild -string "$BUILD" "$APP/Contents/Info.plist"
if [ -f LICENSE ]; then cp LICENSE "$APP/Contents/Resources/LICENSE"; fi
swift scripts/make-icon.swift "$APP/Contents/Resources/AppIcon.icns"

if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
elif [ "$BUILD" = release ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  # Only notarization needs Apple's timestamp, and a local build shouldn't need the internet.
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/Detour.zip"
printf 'Built: %s (%s, %s, signed by %s)\n' "$APP" "$VERSION" "$BUILD" "$IDENTITY"
