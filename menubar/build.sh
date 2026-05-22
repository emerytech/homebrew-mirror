#!/bin/bash
# Compile the menu bar toggle into Mirror.app (with a generated app icon).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/Mirror.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

# Generate the app icon (rounded-rect gradient + mirror).
swiftc -O "$HERE/makeicon.swift" -o "$HERE/makeicon" 2>/dev/null
"$HERE/makeicon"
rm -f "$HERE/makeicon"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

swiftc -O "$HERE/main.swift" -o "$MACOS/Mirror"
cp "$HERE/AppIcon.icns" "$RES/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Mirror</string>
    <key>CFBundleDisplayName</key><string>Mirror</string>
    <key>CFBundleIdentifier</key><string>com.temery.mirror.menubar</string>
    <key>CFBundleVersion</key><string>1.2.0</string>
    <key>CFBundleShortVersionString</key><string>1.2.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Mirror</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>NSCameraUsageDescription</key><string>Mirror records video for your security camera.</string>
    <key>NSMicrophoneUsageDescription</key><string>Mirror records audio for your security camera.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so TCC remembers the camera/mic grant across launches.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built: $APP"
echo "Launch it with:  open \"$APP\""
