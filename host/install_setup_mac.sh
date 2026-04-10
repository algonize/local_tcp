#!/bin/bash

# Local TCP Bridge - Professional Mac Installer (Smart Edition)
# This script registers the bridge with Chrome and auto-detects your Node path.

HOST_NAME="com.algoramming.localtcp"
INSTALL_DIR="$HOME/Library/Application Support/LocalTCP"
TARGET_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

clear
echo -e "\033[1;34m--------------------------------------------------\033[0m"
echo -e "\033[1;36m           🚀 Local TCP Bridge Setup             \033[0m"
echo -e "\033[1;34m--------------------------------------------------\033[0m"

# 1. Detect Node Path
echo "🔍 Detecting Node.js environment..."
NODE_PATH=$(command -v node)

if [ -z "$NODE_PATH" ]; then
    echo -e "\033[1;31m❌ Error: Node.js was not found in your Terminal path.\033[0m"
    echo "Please ensure Node is installed and try again."
    exit 1
fi

echo -e "📍 Found Node at: \033[1;32m$NODE_PATH\033[0m"

# 2. Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$TARGET_DIR"

# 3. Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 4. Copy files
echo "📂 Installing files to: $INSTALL_DIR"
cp "$SCRIPT_DIR/index.js" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/$HOST_NAME.json" "$INSTALL_DIR/"

# 5. Patch Shebang with Absolute Path (The most reliable fix for Chrome)
echo "🔧 Patching execution path for Chrome stability..."
sed -i '' "1s|.*|#!$NODE_PATH|" "$INSTALL_DIR/index.js"
chmod +x "$INSTALL_DIR/index.js"

# 6. Generate manifest with absolute path
sed "s|HOST_PATH|$INSTALL_DIR/index.js|g" "$INSTALL_DIR/$HOST_NAME.json" > "$TARGET_DIR/$HOST_NAME.json"

echo -e "\033[1;32m✅ Bridge installed successfully!\033[0m"
echo ""
echo -e "\033[1;33m👉 IMPORTANT: Please restart Chrome fully to activate.\033[0m"
echo "If still not linked, check that your Extension ID matches what's in guide.txt."
echo -e "\033[1;34m--------------------------------------------------\033[0m"
