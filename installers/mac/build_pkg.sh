#!/bin/bash
# Local TCP Bridge — macOS .pkg Builder (auto sign + notarize)
# ------------------------------------------------------------
# Run this ON A MAC (pkgbuild/productsign are macOS-only) after
# running host-go/build.sh to produce the darwin binaries.
#
#   bash build_pkg.sh
#
# Output: dist/LocalTCP-Setup-Mac.pkg
#
# Signing + notarization are AUTOMATIC when the Developer ID certificates are
# present in the keychain. If they're absent (e.g. CI without secrets, or a
# Linux box), the script still builds an UNSIGNED pkg and tells you so.
#
# To produce a pkg that installs with NO Gatekeeper warning you need, once:
#   1. A "Developer ID Application" + "Developer ID Installer" cert in your keychain
#      (Xcode → Settings → Accounts → Manage Certificates → +).
#   2. Notarization credentials stored once:
#        xcrun notarytool store-credentials AC_PROFILE \
#          --apple-id "you@company.com" --team-id JL9DB72PWR --password "app-specific-pw"
#   Then just:  bash build_pkg.sh
#
# Overridable via env vars:
#   APP_ID, INST_ID      — exact signing identity strings (defaults below)
#   NOTARY_PROFILE       — notarytool keychain profile name (default: AC_PROFILE)
#   NOTARY_KEY/KEY_ID/ISSUER — App Store Connect API key (for CI; used if NOTARY_KEY set)
#   SKIP_NOTARIZE=1      — sign but don't notarize

set -e
cd "$(dirname "$0")"

HOST_NAME="com.algoramming.localtcp"
VERSION="$(grep -m1 '"version"' ../../manifest.json | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
IDENTIFIER="com.algoramming.localtcp.bridge"
GO_DIST="../../host-go/dist"

APP_ID="${APP_ID:-Developer ID Application: Algoramming Systems Ltd. (JL9DB72PWR)}"
INST_ID="${INST_ID:-Developer ID Installer: Algoramming Systems Ltd. (JL9DB72PWR)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PROFILE}"
PKG="dist/LocalTCP-Setup-Mac.pkg"

# Detect which identities are actually available in the keychain.
have_app_id=false; have_inst_id=false
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$APP_ID"; then have_app_id=true; fi
if security find-identity -v 2>/dev/null | grep -qF "$INST_ID"; then have_inst_id=true; fi

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

# 1c. Code-sign the executables BEFORE packaging (required for notarization).
#     Hardened runtime (--options runtime) + secure timestamp are mandatory.
if $have_app_id; then
  echo "→ Signing binary + uninstaller app with: $APP_ID"
  codesign --force --options runtime --timestamp --sign "$APP_ID" \
    "$ROOT/$APP_DIR/localtcp"
  codesign --force --options runtime --timestamp --sign "$APP_ID" \
    "$ROOT/Applications/Uninstall Local TCP.app"
else
  echo "⚠️  '$APP_ID' not found in keychain — building UNSIGNED (will trigger Gatekeeper)."
fi

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

# 3. Build the component package
mkdir -p dist
pkgbuild \
  --root "$ROOT" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG"

# 4. Sign the pkg with the Developer ID Installer cert
if $have_inst_id; then
  echo "→ Signing pkg with: $INST_ID"
  productsign --sign "$INST_ID" "$PKG" "${PKG%.pkg}-signed.pkg"
  mv -f "${PKG%.pkg}-signed.pkg" "$PKG"
else
  echo "⚠️  '$INST_ID' not found in keychain — pkg left UNSIGNED."
fi

# 5. Notarize + staple (only meaningful for a signed pkg)
if $have_inst_id && [[ "$SKIP_NOTARIZE" != "1" ]]; then
  if [[ -n "$NOTARY_KEY" ]]; then
    NOTARY_AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  elif [[ -n "$AC_APP_PASSWORD" ]]; then
    # CI path: notarize directly with an app-specific password (no stored profile)
    NOTARY_AUTH=(--apple-id "$AC_APPLE_ID" --team-id "$AC_TEAM_ID" --password "$AC_APP_PASSWORD")
  else
    NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
  fi
  echo "→ Submitting to Apple notary service (this can take a few minutes)..."
  if xcrun notarytool submit "$PKG" "${NOTARY_AUTH[@]}" --wait; then
    xcrun stapler staple "$PKG"
    echo "✅ Signed, notarized & stapled: $PKG"
  else
    echo "⚠️  Notarization failed. The pkg is SIGNED but NOT notarized (Gatekeeper will still warn)."
    echo "    Set up creds once: xcrun notarytool store-credentials $NOTARY_PROFILE \\"
    echo "      --apple-id <you> --team-id JL9DB72PWR --password <app-specific-pw>"
  fi
else
  echo ""
  echo "✅ Built $PKG"
  $have_inst_id || echo "👉 Install the Developer ID certs to sign; see header for notarization."
fi
