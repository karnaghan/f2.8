#!/bin/bash
# Builds build/f2.8.app with nothing but the Xcode Command Line Tools (no Xcode, no SwiftPM).
#
#   scripts/build.sh            universal (Apple silicon + Intel) release build, self-tests, app bundle
#   scripts/build.sh --native   this Mac's architecture only (faster)
#   scripts/build.sh --debug    unoptimised, this Mac's architecture only
#
# Intermediates go to $F28_WORK (default: a temp folder), so nothing heavy lands in the
# project — handy when the project lives in a synced folder such as OneDrive.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${F28_WORK:-${TMPDIR:-/tmp}/f28-work}"
APP="$ROOT/build/f2.8.app"
NATIVE="$(uname -m)"
OPT="-O"
ARCHS=(arm64 x86_64)
case "${1:-}" in
  --debug) OPT="-Onone -g"; ARCHS=("$NATIVE") ;;
  --native) ARCHS=("$NATIVE") ;;
esac

APP_SOURCES=()
while IFS= read -r -d '' file; do APP_SOURCES+=("$file"); done < <(find "$ROOT/Sources/F28" -name '*.swift' -print0)

swiftc_for() { # arch, args...
  local arch="$1"; shift
  swiftc $OPT -swift-version 5 -target "$arch-apple-macos14.0" -module-cache-path "$WORK/module-cache/$arch" "$@"
}

BINARIES=()
for arch in "${ARCHS[@]}"; do
  OUT="$WORK/$arch"
  mkdir -p "$OUT"
  echo "→ F28Core ($arch)"
  swiftc_for "$arch" -parse-as-library -emit-library -static -emit-module -module-name F28Core \
    -emit-module-path "$OUT/F28Core.swiftmodule" -o "$OUT/libF28Core.a" "$ROOT"/Sources/F28Core/*.swift

  if [[ "$arch" == "$NATIVE" ]]; then
    echo "→ self-tests"
    swiftc_for "$arch" -I "$OUT" -L "$OUT" -lF28Core "$ROOT/Sources/F28SelfTest/main.swift" -o "$OUT/F28SelfTest"
    "$OUT/F28SelfTest" | tail -1
  fi

  echo "→ F28 ($arch)"
  swiftc_for "$arch" -module-name F28 -I "$OUT" -L "$OUT" -lF28Core \
    -framework Carbon -framework ServiceManagement "${APP_SOURCES[@]}" -o "$OUT/F28"
  BINARIES+=("$OUT/F28")
done

echo "→ icon"
swiftc_for "$NATIVE" "$ROOT/scripts/make-icon.swift" -o "$WORK/make-icon"
ICONSET="$WORK/AppIcon.iconset"
"$WORK/make-icon" "$ICONSET" "$WORK/AppIcon.icns" >/dev/null

echo "→ bundle"
# Replace only the previous build of this exact bundle.
if [[ -d "$APP" && "$APP" == "$ROOT/build/f2.8.app" ]]; then rm -rf "$APP"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/F28"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/en.lproj/InfoPlist.strings" "$APP/Contents/Resources/en.lproj/"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$ROOT/build/icon"
cp "$ICONSET/icon_512x512@2x.png" "$ROOT/build/icon/f2.8-icon-1024.png"
codesign --force --sign - --identifier app.f28.focus --timestamp=none "$APP" || echo "  (codesign failed; the app still runs locally)"

echo "✓ $APP ($(lipo -archs "$APP/Contents/MacOS/F28"))"
