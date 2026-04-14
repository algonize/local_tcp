#!/bin/bash

# Local TCP Bridge - Smart Mac Installer
# Registers the bridge with Chrome and ensures Node.js is ready.

set -e

HOST_NAME="com.algoramming.localtcp"
INSTALL_DIR="$HOME/Library/Application Support/LocalTCP"
TARGET_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

# Colors for professional output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

error_handler() {
    echo -e "\n${RED}❌ ERROR: Installation failed at line $1${NC}"
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "1. Ensure you have an active internet connection."
    echo "2. Visit https://nodejs.org/ to install Node.js manually if auto-install fails."
    exit 1
}

trap 'error_handler $LINENO' ERR

ensure_node_installed() {
    echo -e "🔍 Detecting Node.js environment..."
    if ! command -v node &> /dev/null; then
        echo -e "${YELLOW}⚠️ Node.js not found. Attempting automatic installation...${NC}"
        
        if command -v brew &> /dev/null; then
            echo -e "${CYAN}📦 Found Homebrew. Installing Node.js...${NC}"
            brew install node
        else
            echo -e "${RED}❌ Error: Node.js is missing and Homebrew was not found.${NC}"
            echo "Please install Node.js from https://nodejs.org/ and try again."
            exit 1
        fi
    fi
    echo -e "📍 Found Node at: ${GREEN}$(command -v node)${NC}"
}

run_installer() {
    clear
    echo -e "${BLUE}--------------------------------------------------${NC}"
    echo -e "${CYAN}           🚀 Local TCP Bridge - Smart Setup      ${NC}"
    echo -e "${BLUE}--------------------------------------------------${NC}"

    # 1. Ensure Node is present
    ensure_node_installed
    NODE_PATH=$(command -v node)

    # 2. Create directories
    echo "📁 Creating application directories..."
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$TARGET_DIR"

    # 3. Get the directory where the script is located
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    # 4. Copy files
    echo "📂 Installing bridge files..."
    cp "$SCRIPT_DIR/index.js" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/$HOST_NAME.json" "$INSTALL_DIR/"

    # 5. Patch Shebang with Absolute Path
    echo "🔧 Patching execution path for stability..."
    # On Mac, sed -i '' is required
    sed -i '' "1s|.*|#!$NODE_PATH|" "$INSTALL_DIR/index.js"
    chmod +x "$INSTALL_DIR/index.js"

    # 6. Generate manifest with absolute path
    sed "s|HOST_PATH|$INSTALL_DIR/index.js|g" "$INSTALL_DIR/$HOST_NAME.json" > "$TARGET_DIR/$HOST_NAME.json"

    echo -e "\n${GREEN}✅ Bridge installed successfully!${NC}"
    echo -e "${YELLOW}👉 IMPORTANT: Please restart Chrome fully to activate.${NC}"
    echo -e "${BLUE}--------------------------------------------------${NC}"
}

run_installer
