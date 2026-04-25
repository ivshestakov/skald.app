#!/usr/bin/env bash
# Generate Skald.icns from a 1024×1024 source PNG.
#
# Usage:
#   ./make-icon.sh <source.png>          # writes Resources/Skald.icns
#   ./make-icon.sh                        # uses ./icon-source.png by default
#
# macOS app icons are .icns files containing every required size from
# 16×16 up to 1024×1024 at @1x and @2x. This script feeds a master PNG
# through `sips` to render each size, then bakes them into an .icns
# bundle with `iconutil`. Both tools ship with macOS — no Homebrew.

set -euo pipefail
cd "$(dirname "$0")"

SRC="${1:-icon-source.png}"
if [ ! -f "$SRC" ]; then
  echo "!! source not found: $SRC" >&2
  echo "   Drop a 1024×1024 PNG here and re-run." >&2
  exit 1
fi

OUT_DIR="Resources"
mkdir -p "$OUT_DIR"

WORK="$(mktemp -d)"
ICONSET="$WORK/Skald.iconset"
mkdir -p "$ICONSET"

# Apple's required sizes for a Mac app icon set.
declare -a SIZES=(
  "16    icon_16x16.png"
  "32    icon_16x16@2x.png"
  "32    icon_32x32.png"
  "64    icon_32x32@2x.png"
  "128   icon_128x128.png"
  "256   icon_128x128@2x.png"
  "256   icon_256x256.png"
  "512   icon_256x256@2x.png"
  "512   icon_512x512.png"
  "1024  icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
  SIZE=$(echo "$entry" | awk '{print $1}')
  NAME=$(echo "$entry" | awk '{print $2}')
  sips -z "$SIZE" "$SIZE" "$SRC" --out "$ICONSET/$NAME" >/dev/null
done

iconutil --convert icns "$ICONSET" --output "$OUT_DIR/Skald.icns"
rm -rf "$WORK"
echo "==> Wrote $OUT_DIR/Skald.icns"
