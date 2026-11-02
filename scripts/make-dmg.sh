#!/bin/bash
# Packages build/f2.8.app into build/f2.8.dmg: the app beside an Applications shortcut,
# so installing is a single drag. Run scripts/build.sh first (or `make dmg`).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/f2.8.app"
DMG="$ROOT/build/f2.8.dmg"
[[ -d "$APP" ]] || { echo "build/f2.8.app is missing — run scripts/build.sh first"; exit 1; }

STAGE="$(mktemp -d)/f2.8"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/f2.8.app"
ln -s /Applications "$STAGE/Applications"

# Replace only the previous image at this exact path.
[[ -f "$DMG" ]] && rm -f "$DMG"
hdiutil create -quiet -volname "f2.8" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"
codesign --force --sign - --timestamp=none "$DMG" >/dev/null 2>&1 || true
hdiutil verify -quiet "$DMG"

echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
