#!/bin/bash
set -euo pipefail

# ==============================================================================
# Apple Music Remote (AMR) - Universal DMG Builder (Intel x86_64 + Apple Silicon arm64)
# ==============================================================================

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MAC_DIR="$ROOT_DIR/AppleMusicRemoteMac"
BUILD_DIR="$MAC_DIR/build"
APP_NAME="AppleMusicRemoteMac"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
DMG_STAGING="$BUILD_DIR/dmg_staging"
DMG_NAME="AppleMusicRemoteMac-Universal.dmg"
DMG_OUTPUT="$ROOT_DIR/$DMG_NAME"

echo "=========================================================="
echo "🚀 Building Universal macOS Application & DMG for AMR"
echo "   Architectures: arm64 (Apple Silicon) + x86_64 (Intel)"
echo "=========================================================="

rm -rf "$BUILD_DIR" "$DMG_OUTPUT"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULE_CACHE"
mkdir -p "$DMG_STAGING"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
SDK_PATH="$(xcrun --show-sdk-path)"

SWIFT_SOURCES=(
    "$MAC_DIR/Sources/AppleMusicRemoteMac/System/LaunchAtLoginManager.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Models/Models.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/CoreAudio/CoreAudioDeviceManager.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/CoreAudio/BitPerfectLogMonitor.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/UPnP/SSDPService.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/UPnP/UPnPMediaRendererServer.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/Protocols/MusicScriptingBridge.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/Execution/AppleScriptExecutor.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/Audio/AudioQualityDetector.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/Audio/AudioDuckingController.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/Artwork/ArtworkService.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/State/PlaybackStateStore.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/Transport/PlaybackTransportController.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/Status/PlayerStatusEngine.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/Queue/QueueManager.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/Routing/PlaybackRouter.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/Library/LibraryService.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Bridge/MusicBridge.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Cloud/MusicKitManager.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Cloud/CloudCatalogService.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Server/BonjourAdvertiser.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Server/WebSocketServer.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/Server/WebUIContent.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/UI/QRCodeWindow.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/UI/SettingsWindow.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/UI/MenuManager.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/AppDelegate.swift"
    "$MAC_DIR/Sources/AppleMusicRemoteMac/App.swift"
)

FRAMEWORKS=(
    -framework Cocoa
    -framework Network
    -framework ScriptingBridge
    -framework CoreImage
    -framework CoreAudio
    -framework CryptoKit
    -framework ServiceManagement
)

echo "🔨 Compiling for arm64 (Apple Silicon)..."
swiftc -parse-as-library \
    -O \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -target arm64-apple-macosx14.0 \
    "${FRAMEWORKS[@]}" \
    "${SWIFT_SOURCES[@]}" \
    -o "$BUILD_DIR/${APP_NAME}-arm64"

echo "🔨 Compiling for x86_64 (Intel)..."
swiftc -parse-as-library \
    -O \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -target x86_64-apple-macosx14.0 \
    "${FRAMEWORKS[@]}" \
    "${SWIFT_SOURCES[@]}" \
    -o "$BUILD_DIR/${APP_NAME}-x86_64"

echo "🧬 Merging with lipo into Universal 2 binary..."
lipo -create \
    "$BUILD_DIR/${APP_NAME}-arm64" \
    "$BUILD_DIR/${APP_NAME}-x86_64" \
    -output "$MACOS_DIR/$APP_NAME"

lipo -info "$MACOS_DIR/$APP_NAME"

echo "📦 Packaging bundle resources..."
if [ -d "$MAC_DIR/Web" ]; then
    mkdir -p "$RESOURCES_DIR/Web"
    cp -R "$MAC_DIR/Web/"* "$RESOURCES_DIR/Web/"
fi

if [ -f "$ROOT_DIR/SharedAssets/Icons/macOS/AppIcon.icns" ]; then
    cp "$ROOT_DIR/SharedAssets/Icons/macOS/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$ROOT_DIR/SharedAssets/Icons/macOS/icon_256x256.png" ]; then
    cp "$ROOT_DIR/SharedAssets/Icons/macOS/icon_256x256.png" "$RESOURCES_DIR/icon.png"
fi
if [ -f "$ROOT_DIR/AuthKey_MJHWRCSZHH.p8" ]; then
    echo "🔑 Bundling MusicKit AuthKey_MJHWRCSZHH.p8 into Resources..."
    cp "$ROOT_DIR/AuthKey_MJHWRCSZHH.p8" "$RESOURCES_DIR/AuthKey_MJHWRCSZHH.p8"
else
    echo "ℹ️ AuthKey_MJHWRCSZHH.p8 not found; building DMG without embedded key"
fi

cat << 'PLIST' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Apple Music Remote</string>
    <key>CFBundleDisplayName</key>
    <string>Apple Music Remote Server</string>
    <key>CFBundleIdentifier</key>
    <string>org.ksholokhov.amr.mac</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleExecutable</key>
    <string>AppleMusicRemoteMac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Apple Music Remote requires AppleEvents permission to control Music.app playback.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Apple Music Remote uses the local network for Web UI, UPnP/DLNA, and mobile remote control.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_amr._tcp</string>
    </array>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${APPLE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}' || true)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "🔏 Signing with identity: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "🔏 Ad-hoc codesigning Universal binary..."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "📦 Staging DMG layout..."
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "💿 Creating compressed UDZO disk image ($DMG_OUTPUT)..."
hdiutil create \
    -volname "Apple Music Remote" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

rm -rf "$DMG_STAGING"

echo ""
echo "=========================================================="
echo "✅ Universal DMG Created Successfully!"
echo "   Output: $DMG_OUTPUT"
echo "   Size:   $(du -h "$DMG_OUTPUT" | cut -f1)"
echo "   SHA256: $(shasum -a 256 "$DMG_OUTPUT" | cut -d' ' -f1)"
echo "=========================================================="
