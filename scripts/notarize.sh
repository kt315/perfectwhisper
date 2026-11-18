#!/bin/bash
# Notarize the DMG. Requires a notarytool profile created with:
#   xcrun notarytool store-credentials "AC_PASSWORD" \
#       --apple-id "you@example.com" --team-id XXXXXXXXXX --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")/.."

DMG=$(ls -t dist/*.dmg | head -1)
PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"

echo "Submitting for notarization: $DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "Stapling the ticket..."
xcrun stapler staple "$DMG"

echo "Gatekeeper check:"
spctl -a -vvv -t install "$DMG" || true
