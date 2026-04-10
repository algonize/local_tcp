#!/bin/bash

# Local TCP - Professional Linux Uninstaller
# Removes the hardware bridge and Chrome registration.

HOST_NAME="com.algoramming.localtcp"
INSTALL_DIR="$HOME/.local/lib/algonize/localtcp"
TARGET_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"

echo "----------------------------------------------------"
echo "🗑️ Local TCP Bridge - Uninstaller (Linux)"
echo "----------------------------------------------------"

# 1. Remove Chrome Registration
if [ -f "$TARGET_DIR/$HOST_NAME.json" ]; then
    rm -f "$TARGET_DIR/$HOST_NAME.json"
    echo "✅ Chrome registration removed."
fi

# 2. Remove Installed Files
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "✅ Bridge files removed."
fi

echo "----------------------------------------------------"
echo "Done. The bridge has been completely removed."
