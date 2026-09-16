#!/bin/zsh
# Skald for iOS — archive, sign (automatic, Ivan's team 975ZZPJQNB) and
# upload to App Store Connect / TestFlight.
#
# Usage:  ./release-ios.sh [build-number]
#   build-number defaults to the next integer after the last one uploaded
#   (kept in .last-build). Marketing version comes from project.yml.
#
# Needs: the ASC API key file for Ivan's account (Key ID 3DS6DPGNHT) at
# ~/.appstoreconnect/private_keys/AuthKey_3DS6DPGNHT.p8 (see
# ~/Documents/CLAUDE/_shared/registry.md), Xcode 26+, xcodegen.
set -euo pipefail
cd "$(dirname "$0")"

KEY_ID=3DS6DPGNHT
ISSUER_ID=e26124bc-b508-422a-890c-9512544e2252
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
[[ -f "$KEY_PATH" ]] || { echo "ASC key not found: $KEY_PATH"; exit 1; }

LAST=$(cat .last-build 2>/dev/null || echo 0)
BUILD=${1:-$((LAST + 1))}
ARCHIVE=build/Skald-$BUILD.xcarchive
AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$KEY_ID"
      -authenticationKeyIssuerID "$ISSUER_ID")

echo "▶ xcodegen"
xcodegen generate >/dev/null

echo "▶ archive (build $BUILD)"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project Skald.xcodeproj -scheme Skald -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  "${AUTH[@]}" \
  | grep -E "error|warning: .*(provision|sign|entitle)|ARCHIVE" || true
[[ -d "$ARCHIVE" ]] || { echo "archive failed"; exit 1; }

echo "▶ export + upload to App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "build/export-$BUILD" \
  "${AUTH[@]}" \
  | grep -E "error|Upload|EXPORT" || true

echo "$BUILD" > .last-build
echo "✓ build $BUILD uploaded. It shows up in App Store Connect → TestFlight after processing (5–15 min)."
