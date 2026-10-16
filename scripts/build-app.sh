#!/bin/bash
# Wraps the release binary in build/MacToCast.app and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MacToCast"

APP=build/MacToCast.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MacToCast"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MacToCast</string>
    <key>CFBundleIdentifier</key><string>com.biancacchino.MacToCast</string>
    <key>CFBundleName</key><string>Mac to Cast</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Mac to Cast finds Chromecasts on your network and streams a window to them.</string>
    <key>NSBonjourServices</key>
    <array><string>_googlecast._tcp</string></array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
