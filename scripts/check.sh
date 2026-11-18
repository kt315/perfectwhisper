#!/bin/bash
# Local pre-PR check: build and tests.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "-> generating the project"
xcodegen generate >/dev/null

echo "-> building"
xcodebuild -project PerfectWhisper.xcodeproj \
    -scheme PerfectWhisper \
    -configuration Debug \
    -derivedDataPath .build \
    CODE_SIGNING_ALLOWED=NO \
    build | tail -3

echo "-> testing"
xcodebuild test \
    -project PerfectWhisper.xcodeproj \
    -scheme PerfectWhisper \
    -destination 'platform=macOS' \
    -derivedDataPath .build \
    CODE_SIGNING_ALLOWED=NO | grep -E "Executed [0-9]+ tests"

echo "Done"
