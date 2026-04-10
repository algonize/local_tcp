#!/bin/bash

# Algonize Local TCP - Linux Uninstaller
# Run this script to remove the hardware bridge from your system

HOST_NAME="com.algonize.localtcp"
TARGET_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"

echo "----------------------------------------------------"
echo "🗑️ Algonize Local TCP Bridge - Uninstaller"
echo "----------------------------------------------------"

if [ -f "$TARGET_DIR/$HOST_NAME.json" ]; then
    rm "$TARGET_DIR/$HOST_NAME.json"
    echo "✅ Bridge registration removed from Chrome."
else
    echo "ℹ️ No registration found. Nothing to remove."
fi

echo "----------------------------------------------------"
