#!/bin/sh
# Builds Ork.app and the release zip: scripts/package.sh [output-dir]
# The version comes from OrkVersion.current in Sources/Ork/UpdateService.swift.
set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/Ork/UpdateService.swift)
[ -n "$VERSION" ] || { echo "could not read OrkVersion.current" >&2; exit 1; }
OUT="${1:-dist}"
APP="$OUT/Ork.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Ork "$APP/Contents/MacOS/"
cp .build/release/ork-mcp "$APP/Contents/MacOS/"
cp -R .build/release/*.bundle "$APP/Contents/Resources/"

# Finder icon from the brand logo.
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512; do
  sips -z "$size" "$size" Assets/logo.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" Assets/logo.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>Ork</string>
	<key>CFBundleIdentifier</key><string>com.rodrigooler.ork</string>
	<key>CFBundleName</key><string>ork</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
ditto -c -k --keepParent "$APP" "$OUT/ork-$VERSION-macos-arm64.zip"
echo "→ $OUT/ork-$VERSION-macos-arm64.zip"
