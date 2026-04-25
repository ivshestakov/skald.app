#!/usr/bin/env bash
# Build a release-ready Skald.app and zip it for distribution.
#
# Usage:
#   ./release.sh                # uses dev signing identity
#   SKALD_SIGN_IDENTITY="Developer ID Application: …" ./release.sh
#
# Output: dist/Skald-<version>.zip   (the file you upload to a GitHub
# Release / send to a friend / pass through Sparkle's appcast).

set -euo pipefail
cd "$(dirname "$0")"

# Always universal for releases — friends might be on Intel.
unset SKALD_BUILD_ARCH

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)

DIST_DIR="dist"
ZIP_NAME="Skald-${VERSION}.zip"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$ZIP_NAME"

echo "==> Packaging $ZIP_NAME"
# `ditto -c -k --keepParent` produces a Finder-compatible zip that
# preserves resource forks and codesign metadata. Plain `zip` strips
# them and the signed app fails to launch on the recipient's Mac.
ditto -c -k --keepParent Skald.app "$DIST_DIR/$ZIP_NAME"

SIZE=$(du -h "$DIST_DIR/$ZIP_NAME" | awk '{print $1}')
echo "==> Done: $DIST_DIR/$ZIP_NAME ($SIZE)"
echo
echo "Distribute that zip. Recipients should:"
echo "  1. Unzip"
echo "  2. Drag Skald.app into /Applications"
echo "  3. Right-click Skald.app → Open → Open"
echo "     (Gatekeeper warning bypass — only required the very first time)"
