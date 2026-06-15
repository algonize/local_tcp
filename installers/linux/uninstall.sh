#!/bin/bash
# Local TCP Bridge — Linux Uninstaller
#
# Run:  bash uninstall.sh
# (No sudo needed — everything is installed per-user.)

HOST_NAME="com.algoramming.localtcp"

echo "🗑️  Uninstalling Local TCP Bridge..."

rm -rf "$HOME/.local/lib/localtcp" 2>/dev/null

# Unregister from all Chromium-family browsers
for DIR in \
  "$HOME/.config/google-chrome/NativeMessagingHosts" \
  "$HOME/.config/chromium/NativeMessagingHosts" \
  "$HOME/.config/microsoft-edge/NativeMessagingHosts" \
  "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
do
  if [[ -f "$DIR/$HOST_NAME.json" ]]; then
    rm -f "$DIR/$HOST_NAME.json"
    echo "  ✓ Unregistered: $DIR"
  fi
done

echo "✅ Local TCP Bridge removed."
echo "👉 Restart Chrome. You can also remove the extension from chrome://extensions."
