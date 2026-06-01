#!/usr/bin/env bash
# Build a release-ready signed + notarized Skald.app, package it as a
# DMG, notarize the DMG, sign it for Sparkle, and emit a ready-to-paste
# <item> block for appcast.xml.
#
# Usage:
#   SKALD_SIGN_IDENTITY="Developer ID Application: Ivan Shestakov (975ZZPJQNB)" \
#     ./release.sh
#
# Requires (one-time setup, see RELEASE.md):
#   • Developer ID Application cert installed in login keychain
#   • notarytool keychain profile named `skald-notarize`
#       xcrun notarytool store-credentials skald-notarize \
#         --apple-id you@example.com --team-id 975ZZPJQNB \
#         --password <app-specific-password>
#   • Sparkle EdDSA keypair (already generated; private key in keychain)
#
# Output: dist/Skald-<version>.dmg — upload to a GitHub Release, then
# add the printed <item> block to gh-pages/appcast.xml.

set -euo pipefail
cd "$(dirname "$0")"

# --- Pre-flight checks ----------------------------------------------------

if [ -z "${SKALD_SIGN_IDENTITY:-}" ]; then
  cat >&2 <<EOF
SKALD_SIGN_IDENTITY not set. For release builds you must use a real
Developer ID Application certificate, e.g.:

  SKALD_SIGN_IDENTITY="Developer ID Application: Ivan Shestakov (975ZZPJQNB)" \\
    ./release.sh

(Self-signed builds cannot be notarized.)
EOF
  exit 1
fi

if [[ "$SKALD_SIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "!! SKALD_SIGN_IDENTITY is not a Developer ID Application identity." >&2
  echo "   Continuing, but Apple notary service will reject the submission." >&2
fi

if ! security find-identity -v -p codesigning | grep -q "$SKALD_SIGN_IDENTITY"; then
  echo "!! '$SKALD_SIGN_IDENTITY' not found in keychain." >&2
  echo "   Generate it at developer.apple.com → Certificates and install via double-click." >&2
  exit 1
fi

NOTARY_PROFILE="${SKALD_NOTARY_PROFILE:-skald-notarize}"
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "!! notarytool keychain profile '$NOTARY_PROFILE' not found." >&2
  echo "   Set it up once with:" >&2
  echo "     xcrun notarytool store-credentials $NOTARY_PROFILE \\" >&2
  echo "       --apple-id you@example.com --team-id 975ZZPJQNB \\" >&2
  echo "       --password <app-specific-password from appleid.apple.com>" >&2
  exit 1
fi

SPARKLE_BIN="Frameworks/Sparkle-bin"
if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
  echo "!! $SPARKLE_BIN/sign_update missing." >&2
  exit 1
fi

# --- Build ---------------------------------------------------------------

unset SKALD_BUILD_ARCH  # Always universal for releases.
./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
DIST_DIR="dist"
DMG_NAME="Skald-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

# --- Notarize the app ----------------------------------------------------
#
# Apple's notary service accepts .zip, .dmg, or .pkg. Notarizing the .app
# (via a transient .zip) lets us staple the ticket *into the .app* before
# we package it in the .dmg, so the .app is independently verifiable
# even after the user copies it out of the DMG.

ZIP_TMP="$(mktemp -d)/Skald-notarize.zip"
trap 'rm -rf "$(dirname "$ZIP_TMP")"' EXIT

echo "==> Zipping app for notarization"
ditto -c -k --keepParent Skald.app "$ZIP_TMP"

echo "==> Submitting app to Apple notary service (this can take 1-5 min)"
xcrun notarytool submit "$ZIP_TMP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling notarization ticket into Skald.app"
xcrun stapler staple Skald.app
xcrun stapler validate Skald.app

# --- Build the DMG -------------------------------------------------------

DMG_STAGE="$(mktemp -d)/dmg-stage"
mkdir -p "$DMG_STAGE"
cp -R Skald.app "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

echo "==> Building $DMG_NAME"
hdiutil create \
  -volname "Skald ${VERSION}" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH" >/dev/null

# --- Sign + notarize the DMG --------------------------------------------

echo "==> Signing DMG"
codesign --sign "$SKALD_SIGN_IDENTITY" --timestamp "$DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling DMG"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

# --- Sparkle signature ---------------------------------------------------

echo "==> Signing for Sparkle (EdDSA)"
SPARKLE_LINE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
# Sample output: sparkle:edSignature="abc..." length="12345"

SIZE_BYTES=$(stat -f %z "$DMG_PATH")
PUB_DATE=$(LC_ALL=en_US.UTF-8 date -u +"%a, %d %b %Y %H:%M:%S +0000")
DMG_URL="https://github.com/ivshestakov/skald.app/releases/download/v${VERSION}/${DMG_NAME}"

cat <<EOF

==============================================================
Release artifact ready: $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))
==============================================================

Next steps:

1. Upload the DMG to a new GitHub Release:

     gh release create v${VERSION} "$DMG_PATH" \\
       --title "Skald ${VERSION}" \\
       --notes "Release notes here (markdown)"

2. Open the panic-kit repo (https://github.com/ivshestakov/panic-kit)
   and add this <item> to /skald/appcast.xml just below the comment
   inside <channel> (newest item first):

  <item>
    <title>Skald ${VERSION}</title>
    <pubDate>${PUB_DATE}</pubDate>
    <sparkle:version>${BUILD}</sparkle:version>
    <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
    <description><![CDATA[
      <ul>
        <li>What's new in ${VERSION}</li>
      </ul>
    ]]></description>
    <enclosure
      url="${DMG_URL}"
      sparkle:version="${BUILD}"
      sparkle:shortVersionString="${VERSION}"
      length="${SIZE_BYTES}"
      type="application/octet-stream"
      ${SPARKLE_LINE} />
  </item>

3. Commit + push to panic-kit/main. Vercel redeploys automatically
   within ~30s. Existing 0.3+ installs poll panic-kit.com/skald/appcast.xml
   every 24h and on relaunch — they pick up the new version from there.
   (0.2.x users have to upgrade once manually; their Sparkle config
    didn't have a working appcast yet.)

EOF
