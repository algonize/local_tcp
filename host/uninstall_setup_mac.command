#!/bin/bash

# Algonize Local TCP - MacOS Uninstaller
# Double-click this file to remove the hardware bridge from your system

HOST_NAME="com.algonize.localtcp"
TARGET_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

echo "----------------------------------------------------"
echo "🗑️ Algonize Local TCP Bridge - Uninstaller"
echo "----------------------------------------------------"

if [ -f "$TARGET_DIR/$HOST_NAME.json" ]; then
    rm "$TARGET_DIR/$HOST_NAME.json"
    echo "✅ Bridge registration removed from Chrome."
else
    echo "ℹ️ No registration found. Nothing to remove."
fi

echo ""
echo "👉 You can now safely delete the extension folder if desired."
echo "----------------------------------------------------"
read -p "Press enter to exit..."
