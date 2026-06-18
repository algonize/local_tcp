#!/bin/bash
# Local TCP Bridge — Cross-platform build script
# Produces static binaries for every supported OS/arch into ./dist
# Requirements: Go 1.21+ (https://go.dev/dl/)

set -e
cd "$(dirname "$0")"
mkdir -p dist

# Single source of truth: read the version straight from the extension manifest.
VERSION="$(grep -m1 '"version"' ../manifest.json | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
[[ -z "$VERSION" ]] && { echo "❌ Could not read version from ../manifest.json"; exit 1; }
LDFLAGS="-s -w -X main.version=$VERSION"

build() {
  local GOOS=$1 GOARCH=$2 OUT=$3
  echo "→ Building $GOOS/$GOARCH ..."
  CGO_ENABLED=0 GOOS=$GOOS GOARCH=$GOARCH go build -ldflags="$LDFLAGS" -o "dist/$OUT" .
}

build windows amd64  localtcp-windows-amd64.exe
build windows arm64  localtcp-windows-arm64.exe
build darwin  amd64  localtcp-darwin-amd64
build darwin  arm64  localtcp-darwin-arm64
build linux   amd64  localtcp-linux-amd64
build linux   arm64  localtcp-linux-arm64

# On macOS, also produce a Universal binary (works on Intel + Apple Silicon)
if [[ "$(uname)" == "Darwin" ]] && command -v lipo &> /dev/null; then
  echo "→ Creating macOS Universal binary ..."
  lipo -create -output dist/localtcp-darwin-universal \
    dist/localtcp-darwin-amd64 dist/localtcp-darwin-arm64
fi

echo ""
echo "✅ Build complete (v$VERSION):"
ls -lh dist/
