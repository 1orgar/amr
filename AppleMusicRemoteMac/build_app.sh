#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$DIR/.." && pwd )"
APP_NAME="AppleMusicRemoteMac"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="$ROOT_DIR/build/ModuleCache"

echo "🍎 Building 100% Pure Swift macOS Server: $APP_NAME.app..."

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULE_CACHE"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDK_PATH="$(xcrun --show-sdk-path)"

echo "⚡ Compiling Swift sources with swiftc..."
SWIFT_SOURCES=()
while IFS= read -r -d '' file; do
    SWIFT_SOURCES+=("$file")
done < <(find "$DIR/Sources/AppleMusicRemoteMac" -name "*.swift" -print0)

swiftc -parse-as-library \
    -O \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -target arm64-apple-macosx14.0 \
    -framework Cocoa \
    -framework Network \
    -framework ScriptingBridge \
    -framework CoreImage \
    -framework CoreAudio \
    -framework CryptoKit \
    -framework ServiceManagement \
    "${SWIFT_SOURCES[@]}" \
    -o "$MACOS_DIR/$APP_NAME"

# Copy Web UI Assets into App Bundle
if [ -d "$DIR/Web" ]; then
    echo "📦 Packaging Web UI assets into Resources/Web..."
    mkdir -p "$RESOURCES_DIR/Web"
    cp -R "$DIR/Web/"* "$RESOURCES_DIR/Web/"
fi

# Copy Icon & MusicKit Auth Key
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
    echo "ℹ️ AuthKey_MJHWRCSZHH.p8 not found; building without embedded key"
fi

# Create Info.plist
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
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
    <string>2.3.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.3.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>AppleMusicRemoteMac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleMusicUsageDescription</key>
    <string>Apple Music Remote needs access to Apple Music to control playback and view your library.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Apple Music Remote needs permission to control the Music app.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_applemusicremote._tcp</string>
        <string>_musc._tcp</string>
    </array>
</dict>
</plist>
EOF

chmod +x "$MACOS_DIR/$APP_NAME"

# Check for Apple Development certificate
DEV_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}')
if [ -n "$DEV_IDENTITY" ]; then
    echo "🔏 Signing macOS App with Apple Developer identity: $DEV_IDENTITY"
    codesign -s "$DEV_IDENTITY" --force --deep "$APP_BUNDLE" 2>/dev/null || codesign -s - --force --deep "$APP_BUNDLE"
else
    echo "🔏 Signing macOS App ad-hoc..."
    codesign -s - --force --deep "$APP_BUNDLE"
fi

echo "✅ Pure Swift macOS App built successfully at:"
echo "👉 $APP_BUNDLE"
