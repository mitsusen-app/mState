#!/bin/bash
# Builds a universal (arm64 + x86_64) build/mState.app, ad-hoc signed.
# Usage: scripts/bundle.sh [--open] [--dmg]
#   --open  relaunch the app after building
#   --dmg   also write dist/mState-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=0.1.0
BUNDLE_ID=io.github.mitsusen-app.mstate
MIN_MACOS=14.0

for arch in arm64 x86_64; do
    swift build -c release --product mState --scratch-path ".build-$arch" --triple "$arch-apple-macosx$MIN_MACOS"
done

APP=build/mState.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create .build-arm64/release/mState .build-x86_64/release/mState -output "$APP/Contents/MacOS/mState"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>mState</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>mState</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <!-- Menu bar only: no Dock icon, no app menu. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/mState"))"

for arg in "$@"; do
    case "$arg" in
    --dmg)
        DMG="dist/mState-$VERSION.dmg"
        STAGE=$(mktemp -d)
        cp -R "$APP" "$STAGE/"
        ln -s /Applications "$STAGE/Applications"
        mkdir -p dist
        rm -f "$DMG"
        hdiutil create -quiet -volname "mState $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
        rm -rf "$STAGE"
        echo "Built $DMG"
        ;;
    --open)
        pkill -x mState 2>/dev/null || true
        open "$APP"
        ;;
    esac
done
