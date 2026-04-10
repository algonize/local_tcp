#!/bin/bash

# Algonize Local TCP - Linux Setup
# Run this script to register the hardware bridge with Chrome

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HOST_NAME="com.algonize.localtcp"
MANIFEST_NAME="com.algonize.localtcp.json"
TARGET_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"

echo "----------------------------------------------------"
echo "🚀 Algonize Local TCP Bridge - Setup (Linux)"
echo "----------------------------------------------------"

# 1. Ensure directory exists
mkdir -p "$TARGET_DIR"

# 2. Make host executable
chmod +x "$DIR/index.js"

# 3. Register Manifest
# The Extension ID is now locked in the manifest.json and hardcoded in the bridge
sed "s|HOST_PATH|$DIR/index.js|g" "$DIR/$MANIFEST_NAME" > "$TARGET_DIR/$HOST_NAME.json"

echo "✅ Bridge registered successfully."
echo "📍 Location: $TARGET_DIR/$HOST_NAME.json"
echo ""
echo "👉 Restart Chrome to activate the bridge."
echo "----------------------------------------------------"
