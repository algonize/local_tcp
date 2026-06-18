#!/bin/bash
# Local TCP Bridge — macOS UNINSTALLER .pkg Builder (auto sign + notarize)
# ------------------------------------------------------------
# Produces a double-clickable .pkg that REMOVES Local TCP Bridge. It carries no
# payload — all the work is done by a postinstall script that runs as root
# (the macOS Installer asks for the admin password itself), so the user just
# double-clicks and clicks through.
#
#   bash build_uninstall_pkg.sh
#
# Output: dist/localtcp-mac-uninstaller.pkg
#
# Signing + notarization mirror build_pkg.sh: AUTOMATIC when the Developer ID
# certs are present, otherwise an UNSIGNED pkg is produced with a warning.
#
# Overridable via env vars (same as build_pkg.sh):
#   APP_ID, INST_ID, NOTARY_PROFILE, NOTARY_KEY/KEY_ID/ISSUER, SKIP_NOTARIZE=1

set -e
cd "$(dirname "$0")"

VERSION="$(grep -m1 '"version"' ../../manifest.json | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
IDENTIFIER="com.algoramming.localtcp.uninstaller.pkg"

INST_ID="${INST_ID:-Developer ID Installer: Algoramming Systems Ltd. (JL9DB72PWR)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PROFILE}"
PKG="dist/localtcp-mac-uninstaller.pkg"

# Detect whether the installer-signing identity is available.
have_inst_id=false
if security find-identity -v 2>/dev/null | grep -qF "$INST_ID"; then have_inst_id=true; fi

# 1. Build a postinstall script that reverses everything the installer did.
SCRIPTS="$(mktemp -d)/scripts"
mkdir -p "$SCRIPTS"
cat > "$SCRIPTS/postinstall" << 'POST_EOF'
#!/bin/bash
# Runs as root (the Installer elevates). Remove every trace of the bridge.
rm -rf "/Library/Application Support/LocalTCP"
rm -f  "/Library/Google/Chrome/NativeMessagingHosts/com.algoramming.localtcp.json"
rm -f  "/Library/Microsoft/Edge/NativeMessagingHosts/com.algoramming.localtcp.json"
rm -rf "/Applications/Uninstall Local TCP.app"
pkgutil --forget com.algoramming.localtcp.bridge        >/dev/null 2>&1 || true
pkgutil --forget com.algoramming.localtcp.uninstaller.pkg >/dev/null 2>&1 || true
exit 0
POST_EOF
chmod 755 "$SCRIPTS/postinstall"

# 2. Build the payload-free package.
mkdir -p dist
pkgbuild \
  --nopayload \
  --scripts "$SCRIPTS" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  "$PKG"

# 3. Sign the pkg with the Developer ID Installer cert.
if $have_inst_id; then
  echo "→ Signing pkg with: $INST_ID"
  productsign --sign "$INST_ID" "$PKG" "${PKG%.pkg}-signed.pkg"
  mv -f "${PKG%.pkg}-signed.pkg" "$PKG"
else
  echo "⚠️  '$INST_ID' not found in keychain — pkg left UNSIGNED."
fi

# 4. Notarize + staple (only meaningful for a signed pkg).
if $have_inst_id && [[ "$SKIP_NOTARIZE" != "1" ]]; then
  if [[ -n "$NOTARY_KEY" ]]; then
    NOTARY_AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  elif [[ -n "$AC_APP_PASSWORD" ]]; then
    NOTARY_AUTH=(--apple-id "$AC_APPLE_ID" --team-id "$AC_TEAM_ID" --password "$AC_APP_PASSWORD")
  else
    NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
  fi
  echo "→ Submitting uninstaller to Apple notary service (this can take a few minutes)..."
  if xcrun notarytool submit "$PKG" "${NOTARY_AUTH[@]}" --wait; then
    xcrun stapler staple "$PKG"
    echo "✅ Signed, notarized & stapled: $PKG"
  else
    echo "⚠️  Notarization failed. The pkg is SIGNED but NOT notarized (Gatekeeper will still warn)."
  fi
else
  echo ""
  echo "✅ Built $PKG"
  $have_inst_id || echo "👉 Install the Developer ID certs to sign; see build_pkg.sh header for notarization."
fi
