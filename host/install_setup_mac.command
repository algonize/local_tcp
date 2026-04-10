#!/bin/bash

# Algonize Local TCP - MacOS Setup
# Double-click this file to register the hardware bridge with Chrome

# Get the absolute path of the directory where this script is located
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
HOST_NAME="com.algonize.localtcp"
MANIFEST_NAME="com.algonize.localtcp.json"
TARGET_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

echo "----------------------------------------------------"
echo "🚀 Algonize Local TCP Bridge - Setup (MacOS)"
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
echo "⚠️  IMPORTANT: Please ensure your Extension ID is whitelisted"
echo "   in the newly created JSON file above."
echo ""
echo "👉 You can now close this terminal and restart Chrome."
echo "----------------------------------------------------"
read -p "Press enter to exit..."
