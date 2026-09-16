#!/bin/zsh
# Skald for iOS — archive, sign and upload to App Store Connect / TestFlight.
#
# Usage:  ./release-ios.sh [build-number]
#   build-number defaults to the next integer after the last one uploaded
#   (kept in .last-build). Marketing version comes from project.yml.
#
# Signing is MANUAL with the two App Store profiles created via the ASC API
# ("Skald iOS App Store", "Skald Keyboard iOS App Store", Apple Distribution
# cert of team 975ZZPJQNB). They must be installed in
# ~/Library/Developer/Xcode/UserData/Provisioning Profiles (Xcode 16+) or
# ~/Library/MobileDevice/Provisioning Profiles. Upload uses altool with the
# ASC API key 3DS6DPGNHT, which altool finds in ~/.appstoreconnect/private_keys.
set -euo pipefail
cd "$(dirname "$0")"

KEY_ID=3DS6DPGNHT
ISSUER_ID=e26124bc-b508-422a-890c-9512544e2252

LAST=$(cat .last-build 2>/dev/null || echo 0)
BUILD=${1:-$((LAST + 1))}
ARCHIVE=build/Skald-$BUILD.xcarchive
EXPORT=build/export-$BUILD

echo "▶ xcodegen"
xcodegen generate >/dev/null

echo "▶ archive (build $BUILD)"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project Skald.xcodeproj -scheme Skald -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  | grep -E "error|warning: .*(provision|sign|entitle)|ARCHIVE" || true
[[ -d "$ARCHIVE" ]] || { echo "archive failed"; exit 1; }

echo "▶ export IPA"
rm -rf "$EXPORT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$EXPORT" \
  | grep -E "error|EXPORT" || true
IPA=$(ls "$EXPORT"/*.ipa 2>/dev/null | head -1)
[[ -n "$IPA" ]] || { echo "export failed"; exit 1; }

echo "▶ upload to App Store Connect"
xcrun altool --upload-app -t ios -f "$IPA" --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"

echo "$BUILD" > .last-build
echo "✓ build $BUILD uploaded. It shows up in App Store Connect → TestFlight after processing (5–15 min)."
