#!/bin/zsh
# Assembles a plain (unsigned, un-notarized) MiranNotes.app from the release binary,
# for personal daily use from the Dock. Output: build/MiranNotes.app
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP_DIR="build/MiranNotes.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp .build/release/MiranNotes "$APP_DIR/Contents/MacOS/MiranNotes"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Miran Notes</string>
    <key>CFBundleDisplayName</key><string>Miran Notes</string>
    <key>CFBundleIdentifier</key><string>app.miran.notes</string>
    <key>CFBundleExecutable</key><string>MiranNotes</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "Built $APP_DIR"
