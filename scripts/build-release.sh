#!/bin/bash
# Build the Release configuration, sign with Developer ID and export the .app.
#
# Requires a "Developer ID Application" certificate and DEVELOPMENT_TEAM:
#
#   DEVELOPMENT_TEAM=XXXXXXXXXX ./scripts/build-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team identifier}"

ARCHIVE=".build/PerfectWhisper.xcarchive"
EXPORT=".build/release-export"

rm -rf "$ARCHIVE" "$EXPORT"

xcodebuild -project PerfectWhisper.xcodeproj \
    -scheme PerfectWhisper \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    archive

cat > .build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>$DEVELOPMENT_TEAM</string>
	<key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist .build/ExportOptions.plist \
    -exportPath "$EXPORT" \
    -allowProvisioningUpdates

echo "Done: $EXPORT/PerfectWhisper.app"
