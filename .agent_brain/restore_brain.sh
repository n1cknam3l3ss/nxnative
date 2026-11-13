#!/bin/bash
# Restores this Antigravity session on Linux / LinuxRunner / macOS
DEST="$HOME/.gemini/antigravity/brain/aea7e786-0b8b-42da-a023-c86877d59996"
mkdir -p "$DEST"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unzip -o "$DIR/conversation_brain.zip" -d "$DEST"
echo "=== Brain restored! ==="
echo "You can now run: agy --resume aea7e786-0b8b-42da-a023-c86877d59996"
