#!/bin/sh
# Installs the latest ork release into /Applications:
#   curl -fsSL https://raw.githubusercontent.com/rodrigooler/ork/main/install.sh | sh
set -eu

API="https://api.github.com/repos/rodrigooler/ork/releases/latest"
ZIP_URL=$(curl -fsSL "$API" | grep -o '"browser_download_url": *"[^"]*macos-arm64\.zip"' | head -1 | grep -o 'https://[^"]*')
[ -n "$ZIP_URL" ] || { echo "could not find the latest release zip" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $ZIP_URL"
curl -fsSL "$ZIP_URL" -o "$TMP/ork.zip"
ditto -x -k "$TMP/ork.zip" "$TMP/unpacked"

APP=$(find "$TMP/unpacked" -maxdepth 2 -name "*.app" | head -1)
[ -n "$APP" ] || { echo "this release has no .app inside (pre-0.8.0?); unpack the zip manually" >&2; exit 1; }

rm -rf /Applications/Ork.app
ditto "$APP" /Applications/Ork.app
xattr -dr com.apple.quarantine /Applications/Ork.app 2>/dev/null || true

echo "Installed /Applications/Ork.app"
echo "If ork was already running, quit it first, then launch the new one from Applications."
