#!/bin/bash

# Algonize Local TCP - Professional Linux Installer
# Registers the hardware bridge with Chrome securely.

HOST_NAME="com.algoramming.localtcp"
INSTALL_DIR="$HOME/.local/lib/algonize/localtcp"
TARGET_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"

echo "----------------------------------------------------"
echo "🚀 Local TCP Bridge - Setup (Linux)"
echo "----------------------------------------------------"

# 1. Create directory structure
mkdir -p "$INSTALL_DIR"
mkdir -p "$TARGET_DIR"

# 2. Copy files
cp index.js "$INSTALL_DIR/"
cp "$HOST_NAME.json" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/index.js"

# 3. Generate manifest with absolute path
sed "s|HOST_PATH|$INSTALL_DIR/index.js|g" "$INSTALL_DIR/$HOST_NAME.json" > "$TARGET_DIR/$HOST_NAME.json"

echo "✅ Bridge installed successfully!"
echo "📍 Location: $INSTALL_DIR"
echo ""
echo "👉 Please restart Chrome to complete the setup."
echo "----------------------------------------------------"
