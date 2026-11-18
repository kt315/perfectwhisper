#!/bin/bash
# Package the .app into a DMG with a drag-to-Applications window.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=".build/release-export/PerfectWhisper.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=".build/dmg-stage"
OUT_DIR="dist"
DMG="$OUT_DIR/PerfectWhisper-$VERSION.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" "$OUT_DIR"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "PerfectWhisper" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG"

if [ "${NO_SIGN:-0}" != "1" ] && security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    codesign --force --sign "Developer ID Application" --timestamp "$DMG"
    echo "DMG signed"
fi

echo "Done: $DMG"
