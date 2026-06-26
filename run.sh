#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/Parrocchettami"
APP_BUNDLE="$APP_DIR/.build/Parrocchettami.app"

export PARROCCHETTAMI_HOME="$SCRIPT_DIR"

echo "Building Parrocchettami..."
cd "$APP_DIR"
swift build -c release 2>&1

BIN_SRC="$(swift build -c release --show-bin-path)/Parrocchettami"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_SRC" "$APP_BUNDLE/Contents/MacOS/Parrocchettami"
cp "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.md"

# --- App Icon ---
ICON_SOURCE="$SCRIPT_DIR/parrocchettami.icon"
ICON_KEY=""
if [ -f "$ICON_SOURCE/icon.json" ]; then
    echo "Generating app icon..."
    ICON_BUILD_DIR="$APP_DIR/.build/AppIconAssets"
    ICON_PARTIAL_PLIST="$APP_DIR/.build/AppIconPartial.plist"
    rm -rf "$ICON_BUILD_DIR"
    mkdir -p "$ICON_BUILD_DIR"
    xcrun actool \
        --compile "$ICON_BUILD_DIR" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon parrocchettami \
        --output-partial-info-plist "$ICON_PARTIAL_PLIST" \
        --warnings \
        --errors \
        --notices \
        "$ICON_SOURCE"
    cp "$ICON_BUILD_DIR/Assets.car" "$APP_BUNDLE/Contents/Resources/Assets.car"
    cp "$ICON_BUILD_DIR/parrocchettami.icns" "$APP_BUNDLE/Contents/Resources/parrocchettami.icns"
    ICON_KEY="    <key>CFBundleIconFile</key>
    <string>parrocchettami</string>
    <key>CFBundleIconName</key>
    <string>parrocchettami</string>"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Parrocchettami</string>
    <key>CFBundleIdentifier</key>
    <string>com.parrocchettami.app</string>
    <key>CFBundleName</key>
    <string>Parrocchettami</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Parrocchettami needs microphone access to record audio for transcription.</string>
$ICON_KEY
    <key>LSEnvironment</key>
    <dict>
        <key>PARROCCHETTAMI_HOME</key>
        <string>$SCRIPT_DIR</string>
    </dict>
</dict>
</plist>
PLIST

echo "Launching Parrocchettami..."
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true
pkill -f Parrocchettami 2>/dev/null || true
sleep 1
open "$APP_BUNDLE"
