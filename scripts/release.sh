#!/bin/bash
# Builds a Developer ID signed, notarized and stapled dist/Detour-VERSION.zip.
# Notary credentials: NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER_ID (an App Store Connect
# API key, as in CI), or else the notarytool keychain profile named by NOTARY_PROFILE.
set -euo pipefail
cd "$(dirname "$0")/.."
export SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
APP_BUILD=release ARCHS="arm64 x86_64" bash scripts/build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Detour.app/Contents/Info.plist)"

if [ -n "${NOTARY_KEY_ID:-}" ]; then
  CREDENTIALS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  CREDENTIALS=(--keychain-profile "${NOTARY_PROFILE:-wink-notary}")
fi
RESULT="$(xcrun notarytool submit dist/Detour.zip "${CREDENTIALS[@]}" --wait --output-format json)"
ID="$(plutil -extract id raw -o - - <<<"$RESULT")"
if [ "$(plutil -extract status raw -o - - <<<"$RESULT")" != "Accepted" ]; then
  xcrun notarytool log "$ID" "${CREDENTIALS[@]}" >&2
  exit 1
fi

# Staple the app, then zip it again so the published zip carries the ticket.
xcrun stapler staple dist/Detour.app
spctl --assess --type execute --verbose=2 dist/Detour.app
ZIP="dist/Detour-$VERSION.zip"
rm dist/Detour.zip
ditto -c -k --sequesterRsrc --keepParent dist/Detour.app "$ZIP"
printf 'Notarized: %s\nsha256: %s\n' "$ZIP" "$(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"
