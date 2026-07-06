#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR/Parrocchettami"
DIST_DIR="$SCRIPT_DIR/dist"
VERSION="${1:-1.0.0}"
APP_NAME="Parrocchettami"
WORK_DIR="${TMPDIR:-/tmp}/parrocchettami-package-$VERSION"
APP_BUNDLE="$WORK_DIR/$APP_NAME.app"
STAGING_DIR="$WORK_DIR/dmg-root"
TEMP_DMG="$WORK_DIR/$APP_NAME-$VERSION-Apple-Silicon.dmg"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-Apple-Silicon.dmg"
CLI_SOURCE="$SCRIPT_DIR/bin/parakeet-cli"
ENTITLEMENTS="$PACKAGE_DIR/Parrocchettami.entitlements"
ICON_SOURCE="$SCRIPT_DIR/parrocchettami.icon"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERROR: DMG packaging requires macOS."
    exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "ERROR: This packaging script currently creates the Apple Silicon build."
    exit 1
fi

for required in "$CLI_SOURCE" "$ENTITLEMENTS" "$ICON_SOURCE/icon.json" "$SCRIPT_DIR/dmg/background.tiff" "$SCRIPT_DIR/INSTALLATION.txt" "$SCRIPT_DIR/LICENSE" "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md"; do
    if [[ ! -f "$required" ]]; then
        echo "ERROR: Missing required file: $required"
        exit 1
    fi
done

echo "Building $APP_NAME $VERSION for Apple Silicon..."
BUILD_ARGS=(--package-path "$PACKAGE_DIR" -c release)
if [[ "${PARROCCHETTAMI_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
    BUILD_ARGS+=(--disable-sandbox --scratch-path "${TMPDIR:-/tmp}/parrocchettami-package-build")
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_EXECUTABLE="$BIN_DIR/$APP_NAME"

rm -rf "$WORK_DIR"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$WORK_DIR" "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/bin"

/bin/cp -X "$APP_EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
/bin/cp -X "$CLI_SOURCE" "$APP_BUNDLE/Contents/Resources/bin/parakeet-cli"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME" "$APP_BUNDLE/Contents/Resources/bin/parakeet-cli"

ICON_BUILD_DIR="$WORK_DIR/AppIconAssets"
ICON_PARTIAL_PLIST="$WORK_DIR/AppIconPartial.plist"
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

for generated in "$ICON_BUILD_DIR/Assets.car" "$ICON_BUILD_DIR/parrocchettami.icns"; do
    if [[ ! -f "$generated" ]]; then
        echo "ERROR: Icon asset compilation did not produce: $generated"
        exit 1
    fi
done

/bin/cp -X "$ICON_BUILD_DIR/Assets.car" "$APP_BUNDLE/Contents/Resources/Assets.car"
/bin/cp -X "$ICON_BUILD_DIR/parrocchettami.icns" "$APP_BUNDLE/Contents/Resources/parrocchettami.icns"

/bin/cp -X "$SCRIPT_DIR/LICENSE" "$APP_BUNDLE/Contents/Resources/LICENSE"
/bin/cp -X "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$APP_BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.md"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.parrocchettami.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>parrocchettami</string>
    <key>CFBundleIconName</key>
    <string>parrocchettami</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSArchitecturePriority</key>
    <array><string>arm64</string></array>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Parrocchettami needs microphone access to record audio for local transcription.</string>
</dict>
</plist>
PLIST

plutil -lint "$APP_BUNDLE/Contents/Info.plist"
plutil -lint "$ENTITLEMENTS"
xattr -cr "$APP_BUNDLE"

echo "Signing nested CLI and app with identity: $SIGN_IDENTITY"
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/Resources/bin/parakeet-cli"
codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -d --entitlements :- "$APP_BUNDLE" 2>&1 | grep -q "com.apple.security.device.audio-input"

mkdir -p "$STAGING_DIR"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
{
    /bin/cat "$SCRIPT_DIR/INSTALLATION.txt"
    printf "\n\n"
    printf "License\n=======\n\n"
    /bin/cat "$SCRIPT_DIR/LICENSE"
    printf "\n\n"
    printf "Third Party Notices\n===================\n\n"
    /bin/cat "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md"
} > "$STAGING_DIR/Installation Guide.txt"
mkdir -p "$STAGING_DIR/.background"
/bin/cp -X "$SCRIPT_DIR/dmg/background.tiff" "$STAGING_DIR/.background/background.tiff"
xattr -cr "$STAGING_DIR"
codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/$APP_NAME.app"

echo "Creating writable DMG for Finder layout..."
RW_DMG="$WORK_DIR/$APP_NAME-$VERSION-rw.dmg"
if ! hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$RW_DMG"; then
    echo "Direct writable-image creation unavailable; converting an HFS image."
    HYBRID_DMG="$WORK_DIR/$APP_NAME-$VERSION-hybrid.dmg"
    hdiutil makehybrid \
        -hfs \
        -hfs-volume-name "$APP_NAME" \
        -o "$HYBRID_DMG" \
        "$STAGING_DIR"
    hdiutil convert "$HYBRID_DMG" -format UDRW -o "$RW_DMG"
fi

MOUNT_PATH="/Volumes/$APP_NAME"
DEVICE=""
if [[ "${PARROCCHETTAMI_USE_OPEN_FOR_LAYOUT:-0}" == "1" ]]; then
    open -b com.apple.DiskImageMounter "$RW_DMG"
    for _ in {1..30}; do
        [[ -d "$MOUNT_PATH" ]] && break
        sleep 0.5
    done
else
    ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
    DEVICE="$(echo "$ATTACH_OUTPUT" | awk '/\/Volumes\// { print $1; exit }')"
    MOUNT_PATH="$(echo "$ATTACH_OUTPUT" | sed -n 's|^.*\(/Volumes/.*\)$|\1|p' | head -n 1)"
fi

if [[ ! -d "$MOUNT_PATH" ]]; then
    echo "ERROR: Unable to mount writable DMG."
    exit 1
fi

osascript "$SCRIPT_DIR/scripts/style-dmg.applescript" "$(basename "$MOUNT_PATH")"
sync

if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE"
else
    osascript -e "tell application \"Finder\" to eject disk \"$APP_NAME\""
    for _ in {1..30}; do
        [[ ! -d "$MOUNT_PATH" ]] && break
        sleep 0.5
    done
fi

echo "Compressing final DMG..."
hdiutil convert "$RW_DMG" -format UDZO -o "$TEMP_DMG"
hdiutil verify "$TEMP_DMG"

/bin/cp -X "$TEMP_DMG" "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
rm -rf "$WORK_DIR"

echo ""
echo "Created: $DMG_PATH"
echo "Checksum: $DMG_PATH.sha256"
