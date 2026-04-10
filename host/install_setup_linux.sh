#!/bin/bash

# Algoramming Local TCP - Professional Linux Installer
# Registers the hardware bridge with Chrome securely.

HOST_NAME="com.algoramming.localtcp"
INSTALL_DIR="$HOME/.local/lib/algoramming/localtcp"
TARGET_DIR="$HOME/.config/google-chrome/NativeMessagingHosts"

echo "----------------------------------------------------"
echo "🚀 Local TCP Bridge - Setup (Linux)"
echo "----------------------------------------------------"

# 1. Detect Node Path
echo "🔍 Detecting Node.js environment..."
NODE_PATH=$(command -v node)

if [ -z "$NODE_PATH" ]; then
    echo -e "\033[1;31m❌ Error: Node.js was not found in your Terminal path.\033[0m"
    echo "Please install Node.js and try again."
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

# 5. Patch Shebang with Absolute Path
echo "🔧 Patching execution path for Chrome stability..."
sed -i "1s|.*|#!$NODE_PATH|" "$INSTALL_DIR/index.js"
chmod +x "$INSTALL_DIR/index.js"

# 6. Generate manifest
sed "s|HOST_PATH|$INSTALL_DIR/index.js|g" "$INSTALL_DIR/$HOST_NAME.json" > "$TARGET_DIR/$HOST_NAME.json"

echo "✅ Bridge installed successfully!"
echo "📍 Location: $INSTALL_DIR"
echo ""
echo "👉 Please restart Chrome to complete the setup."
echo "----------------------------------------------------"
