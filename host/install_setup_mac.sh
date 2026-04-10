#!/bin/bash

# Local TCP Bridge - Professional Mac Installer
# This script registers the bridge with Chrome.

HOST_NAME="com.algoramming.localtcp"
INSTALL_DIR="$HOME/Library/Application Support/LocalTCP"
TARGET_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

clear
echo -e "\033[1;34m--------------------------------------------------\033[0m"
echo -e "\033[1;36m           🚀 Local TCP Bridge Setup             \033[0m"
echo -e "\033[1;34m--------------------------------------------------\033[0m"

# 1. Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$TARGET_DIR"

# 2. Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "📂 Installing to: $INSTALL_DIR"

# 3. Copy files
cp "$SCRIPT_DIR/index.js" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/$HOST_NAME.json" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/index.js"

# 4. Generate manifest with absolute path
sed "s|HOST_PATH|$INSTALL_DIR/index.js|g" "$INSTALL_DIR/$HOST_NAME.json" > "$TARGET_DIR/$HOST_NAME.json"

echo -e "\033[1;32m✅ Bridge installed successfully!\033[0m"
echo ""
echo -e "\033[1;33m👉 IMPORTANT: Please restart Chrome to activate.\033[0m"
echo -e "\033[1;34m--------------------------------------------------\033[0m"
