#!/bin/bash
# Builds TidyDisk.app into the project root.
# Usage:
#   ./build.sh            # local build (ad-hoc signed)
#   ./build.sh --install  # local build + copy to /Applications
#   ./build.sh --release  # Developer ID sign + notarize + staple → TidyDisk-1.0.zip
#                         # (needs a "Developer ID Application" cert and
#                         #  `xcrun notarytool store-credentials riekclean` done once)
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ Building (release, universal arm64+x86_64)…"
swift build -c release --arch arm64 --arch x86_64

APP="TidyDisk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/apple/Products/Release/TidyDisk "$APP/Contents/MacOS/TidyDisk"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Scripts/AppIcon.icns ]; then
  echo "▸ Generating app icon…"
  swift Scripts/gen_icon.swift Scripts
  iconutil -c icns Scripts/AppIcon.iconset -o Scripts/AppIcon.icns
  rm -rf Scripts/AppIcon.iconset
fi
cp Scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ "${1:-}" = "--release" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
  if [ -z "$IDENTITY" ]; then
    echo "✗ No 'Developer ID Application' certificate found."
    echo "  Create one in Xcode → Settings → Accounts → Manage Certificates."
    exit 1
  fi
  echo "▸ Signing with: $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

  ZIP="TidyDisk-1.1.zip"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

  echo "▸ Notarizing (takes a few minutes)…"
  xcrun notarytool submit "$ZIP" --keychain-profile riekclean --wait

  echo "▸ Stapling ticket…"
  xcrun stapler staple "$APP"

  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  spctl -a -vv "$APP" && echo "✓ Notarized. Share $PWD/$ZIP — it opens cleanly on any Mac."
  exit 0
fi

echo "▸ Signing (ad-hoc)…"
codesign --force --sign - "$APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/TidyDisk.app
  cp -R "$APP" /Applications/
  echo "✓ Installed to /Applications/TidyDisk.app"
else
  echo "✓ Built $PWD/$APP"
fi
