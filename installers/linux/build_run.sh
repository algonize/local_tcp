#!/bin/bash
# Local TCP Bridge — Linux Installer Builder
# ------------------------------------------------------------
# Produces a single self-extracting installer file the user just runs:
#   chmod +x localtcp-linux-installer.run && ./localtcp-linux-installer.run
# (Most file managers also let users double-click → "Run".)
#
# No Node.js required — the bridge is a static Go binary embedded inside.
#
# Build:  ./build_run.sh   (after running host-go/build.sh)
# Output: dist/localtcp-linux-installer.run

set -e
cd "$(dirname "$0")"
GO_DIST="../../host-go/dist"

[[ -f "$GO_DIST/localtcp-linux-amd64" ]] || { echo "❌ Run host-go/build.sh first."; exit 1; }

mkdir -p dist payload
cp "$GO_DIST/localtcp-linux-amd64" payload/localtcp-amd64
cp "$GO_DIST/localtcp-linux-arm64" payload/localtcp-arm64 2>/dev/null || true
cp uninstall.sh payload/uninstall.sh

# ── The script that runs on the user's machine ───────────────────────────────
cat > payload/setup.sh << 'SETUP_EOF'
#!/bin/bash
set -e
HOST_NAME="com.algoramming.localtcp"
INSTALL_DIR="$HOME/.local/lib/localtcp"
ARCH=$(uname -m)

case "$ARCH" in
  x86_64) BIN="localtcp-amd64" ;;
  aarch64|arm64) BIN="localtcp-arm64" ;;
  *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "🛰️  Installing Local TCP Bridge..."
mkdir -p "$INSTALL_DIR"
cp "$(dirname "$0")/$BIN" "$INSTALL_DIR/localtcp"
chmod +x "$INSTALL_DIR/localtcp"
cp "$(dirname "$0")/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
chmod +x "$INSTALL_DIR/uninstall.sh"

MANIFEST='{
  "name": "'"$HOST_NAME"'",
  "description": "Your browser can finally talk with local TCP.",
  "path": "'"$INSTALL_DIR"'/localtcp",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://ngbakchodnmhndnghhejmocfadjfekkf/"
  ]
}'

# Register for every Chromium-family browser present
for DIR in \
  "$HOME/.config/google-chrome/NativeMessagingHosts" \
  "$HOME/.config/chromium/NativeMessagingHosts" \
  "$HOME/.config/microsoft-edge/NativeMessagingHosts" \
  "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
do
  PARENT=$(dirname "$DIR")
  if [[ -d "$PARENT" ]]; then
    mkdir -p "$DIR"
    echo "$MANIFEST" > "$DIR/$HOST_NAME.json"
    echo "  ✓ Registered: $DIR"
  fi
done

echo ""
echo "✅ Local TCP Bridge installed."
echo "👉 Restart Chrome completely to activate."
SETUP_EOF
chmod +x payload/setup.sh

# ── Self-extracting wrapper ──────────────────────────────────────────────────
cat > dist/localtcp-linux-installer.run << 'WRAP_EOF'
#!/bin/bash
# Local TCP Bridge — self-extracting installer
set -e
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ARCHIVE_LINE=$(awk '/^__ARCHIVE_BELOW__/ {print NR + 1; exit 0}' "$0")
tail -n +$ARCHIVE_LINE "$0" | tar -xz -C "$TMP"
bash "$TMP/setup.sh"
exit 0
__ARCHIVE_BELOW__
WRAP_EOF

tar -czf - -C payload . >> dist/localtcp-linux-installer.run
chmod +x dist/localtcp-linux-installer.run
rm -rf payload

# ── Self-extracting UNINSTALLER (same run-it-and-done UX as the installer) ───
mkdir -p payload-un
cp uninstall.sh payload-un/setup.sh   # wrapper executes setup.sh
chmod +x payload-un/setup.sh

cat > dist/localtcp-linux-uninstaller.run << 'WRAP_EOF'
#!/bin/bash
# Local TCP Bridge — self-extracting uninstaller
set -e
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ARCHIVE_LINE=$(awk '/^__ARCHIVE_BELOW__/ {print NR + 1; exit 0}' "$0")
tail -n +$ARCHIVE_LINE "$0" | tar -xz -C "$TMP"
bash "$TMP/setup.sh"
exit 0
__ARCHIVE_BELOW__
WRAP_EOF

tar -czf - -C payload-un . >> dist/localtcp-linux-uninstaller.run
chmod +x dist/localtcp-linux-uninstaller.run
rm -rf payload-un

echo "✅ Built dist/localtcp-linux-installer.run ($(du -h dist/localtcp-linux-installer.run | cut -f1))"
echo "✅ Built dist/localtcp-linux-uninstaller.run ($(du -h dist/localtcp-linux-uninstaller.run | cut -f1))"
