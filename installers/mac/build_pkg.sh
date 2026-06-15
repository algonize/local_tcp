#!/bin/bash
# Local TCP Bridge — macOS .pkg Builder
# ------------------------------------------------------------
# Run this ON A MAC (pkgbuild/productbuild are macOS-only) after
# running host-go/build.sh to produce the darwin binaries.
#
#   ./build_pkg.sh
#
# Output: dist/LocalTCP-Setup-Mac.pkg
# End-user experience: double-click the .pkg → Next → Next → Done.
# No terminal, no Node.js, no drag-and-drop into Terminal.
#
# (Recommended) Sign + notarize before distribution to avoid Gatekeeper
# warnings (also codesign the bundled Uninstall app):
#   codesign --force --deep --sign "Developer ID Application: Algoramming Systems Ltd. (JL9DB72PWR)" \
#       "uninstaller-app/Uninstall Local TCP.app"
#   productsign --sign "Developer ID Installer: Algoramming Systems Ltd. (JL9DB72PWR)" \
#       dist/LocalTCP-Setup-Mac.pkg dist/LocalTCP-Setup-Mac-signed.pkg
#   xcrun notarytool submit dist/LocalTCP-Setup-Mac-signed.pkg \
#       --keychain-profile "AC_PROFILE" --wait
#   xcrun stapler staple dist/LocalTCP-Setup-Mac-signed.pkg

set -e
cd "$(dirname "$0")"

HOST_NAME="com.algoramming.localtcp"
VERSION="2.0.0"
IDENTIFIER="com.algoramming.localtcp.bridge"
GO_DIST="../../host-go/dist"

# System-wide install locations (fixed paths → manifest needs no patching)
APP_DIR="Library/Application Support/LocalTCP"
CHROME_NMH_DIR="Library/Google/Chrome/NativeMessagingHosts"
EDGE_NMH_DIR="Library/Microsoft/Edge/NativeMessagingHosts"

ROOT="$(mktemp -d)/root"
mkdir -p "$ROOT/$APP_DIR" "$ROOT/$CHROME_NMH_DIR" "$ROOT/$EDGE_NMH_DIR"

# 1. Binary — prefer Universal (Intel + Apple Silicon), build via lipo if needed
if [[ -f "$GO_DIST/localtcp-darwin-universal" ]]; then
  cp "$GO_DIST/localtcp-darwin-universal" "$ROOT/$APP_DIR/localtcp"
elif command -v lipo &> /dev/null && [[ -f "$GO_DIST/localtcp-darwin-amd64" && -f "$GO_DIST/localtcp-darwin-arm64" ]]; then
  lipo -create -output "$ROOT/$APP_DIR/localtcp" \
    "$GO_DIST/localtcp-darwin-amd64" "$GO_DIST/localtcp-darwin-arm64"
else
  echo "❌ Missing darwin binaries. Run host-go/build.sh first."; exit 1
fi
chmod 755 "$ROOT/$APP_DIR/localtcp"

# 1b. Ship a double-clickable uninstaller app into /Applications
mkdir -p "$ROOT/Applications"
cp -R "uninstaller-app/Uninstall Local TCP.app" "$ROOT/Applications/"
chmod 755 "$ROOT/Applications/Uninstall Local TCP.app/Contents/MacOS/uninstall"

# 2. Native Messaging manifest (absolute path is fixed for system installs)
MANIFEST='{
  "name": "'"$HOST_NAME"'",
  "description": "Your browser can finally talk with local TCP.",
  "path": "/Library/Application Support/LocalTCP/localtcp",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://ngbakchodnmhndnghhejmocfadjfekkf/"
  ]
}'
echo "$MANIFEST" > "$ROOT/$CHROME_NMH_DIR/$HOST_NAME.json"
echo "$MANIFEST" > "$ROOT/$EDGE_NMH_DIR/$HOST_NAME.json"

# 3. Build the package
mkdir -p dist
pkgbuild \
  --root "$ROOT" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  "dist/LocalTCP-Setup-Mac.pkg"

echo ""
echo "✅ Built dist/LocalTCP-Setup-Mac.pkg"
echo "👉 Sign + notarize before publishing (see header comments)."
