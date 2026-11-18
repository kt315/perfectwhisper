#!/bin/bash
# Download a Core ML Whisper model from Hugging Face into the layout WhisperKit expects.
# This is a convenience for development; the app can do the same itself.
set -euo pipefail

VARIANT="${1:-openai_whisper-large-v3-v20240930_turbo}"
DEST="$HOME/Library/Application Support/PerfectWhisper/Models/models/argmaxinc/whisperkit-coreml/$VARIANT"
BASE="https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main"
API="https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/main/$VARIANT?recursive=true"

mkdir -p "$DEST"
echo "Destination: $DEST"

curl -s "$API" | python3 -c '
import json, sys
for item in json.load(sys.stdin):
    if item.get("type") == "file":
        print(item["path"])
' | while read -r path; do
    rel="${path#*/}"
    mkdir -p "$DEST/$(dirname "$rel")"
    if [ -s "$DEST/$rel" ]; then
        echo "· already present: $rel"
        continue
    fi
    echo "-> $rel"
    curl -L --fail --retry 3 --retry-delay 2 -o "$DEST/$rel" "$BASE/$path"
done

du -sh "$DEST"
echo done > "$DEST/.download-complete"
echo "DONE"
