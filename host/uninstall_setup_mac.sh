#!/bin/bash

# Local TCP Bridge - Professional Mac Uninstaller
# Removes the bridge and Chrome registration.

HOST_NAME="com.algoramming.localtcp"
INSTALL_DIR="$HOME/Library/Application Support/LocalTCP"
TARGET_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

clear
echo -e "\033[1;31m--------------------------------------------------\033[0m"
echo -e "\033[1;33m           🗑️ Local TCP Bridge Removal          \033[0m"
echo -e "\033[1;31m--------------------------------------------------\033[0m"

# 1. Remove Chrome Registration
if [ -f "$TARGET_DIR/$HOST_NAME.json" ]; then
    rm -f "$TARGET_DIR/$HOST_NAME.json"
    echo "✅ Chrome registration removed."
fi

# 2. Remove Files
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "✅ Bridge files removed."
fi

echo ""
echo -e "\033[1;32mDone. The bridge has been completely removed.\033[0m"
echo -e "\033[1;31m--------------------------------------------------\033[0m"
