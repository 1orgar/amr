#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="AppleMusicRemote"
BUILD_DIR="$DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Building 100% Pure Native AppleMusicRemote.app (No Python)..."

# 1. Clean and create structure
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$BUILD_DIR/ModuleCache"

SDK_PATH="$(xcrun --show-sdk-path)"

echo "⚡ Compiling Swift components..."
swiftc -parse-as-library -c "$DIR/macos_native/MusicKitBridge.swift" \
    -emit-objc-header-path "$DIR/macos_native/MusicKitBridge-Swift.h" \
    -o "$BUILD_DIR/MusicKitBridge.o" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    -target arm64-apple-macosx14.0

echo "⚡ Compiling native Cocoa binary with clang..."
clang -fobjc-arc -O2 -isysroot "$SDK_PATH" -c "$DIR/macos_native/main.m" -o "$BUILD_DIR/main.o"
clang -fobjc-arc -O2 -isysroot "$SDK_PATH" -c "$DIR/macos_native/AppDelegate.m" -o "$BUILD_DIR/AppDelegate.o"
clang -fobjc-arc -O2 -isysroot "$SDK_PATH" -c "$DIR/macos_native/NativeHTTPServer.m" -o "$BUILD_DIR/NativeHTTPServer.o"
clang -fobjc-arc -O2 -isysroot "$SDK_PATH" -c "$DIR/macos_native/AppleMusicBridge.m" -o "$BUILD_DIR/AppleMusicBridge.o"
clang -fobjc-arc -O2 -isysroot "$SDK_PATH" -c "$DIR/macos_native/CloudService.m" -o "$BUILD_DIR/CloudService.o"
clang -fobjc-arc -O2 -isysroot "$SDK_PATH" -c "$DIR/macos_native/QRCodeNative.m" -o "$BUILD_DIR/QRCodeNative.o"
clang -fobjc-arc -O2 -isysroot "$SDK_PATH" -c "$DIR/macos_native/AppConfig.m" -o "$BUILD_DIR/AppConfig.o"

echo "🔗 Linking executable with swiftc..."
swiftc -target arm64-apple-macosx14.0 \
    -sdk "$SDK_PATH" \
    -module-cache-path "$BUILD_DIR/ModuleCache" \
    "$BUILD_DIR/MusicKitBridge.o" \
    "$BUILD_DIR/main.o" \
    "$BUILD_DIR/AppDelegate.o" \
    "$BUILD_DIR/NativeHTTPServer.o" \
    "$BUILD_DIR/AppleMusicBridge.o" \
    "$BUILD_DIR/CloudService.o" \
    "$BUILD_DIR/QRCodeNative.o" \
    "$BUILD_DIR/AppConfig.o" \
    -Xlinker -framework -Xlinker Cocoa \
    -Xlinker -framework -Xlinker CoreImage \
    -Xlinker -framework -Xlinker ScriptingBridge \
    -Xlinker -framework -Xlinker AVFoundation \
    -Xlinker -framework -Xlinker CoreMedia \
    -o "$MACOS_DIR/$APP_NAME"

# 3. Copy web assets to Resources
echo "📦 Copying web assets..."
cp -R "$DIR/web" "$RESOURCES_DIR/"

# 4. Copy App Icon
if [ -f "$DIR/macos_app/AppIcon.icns" ]; then
    cp "$DIR/macos_app/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# 5. Create Info.plist (LSUIElement = 1 for background status item)
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Apple Music Remote</string>
    <key>CFBundleDisplayName</key>
    <string>Apple Music Remote</string>
    <key>CFBundleIdentifier</key>
    <string>org.ksholokhov.amr</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>AppleMusicRemote</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleMusicUsageDescription</key>
    <string>Apple Music Remote needs access to Apple Music to control playback and view your library.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Apple Music Remote needs to control Music app.</string>
</dict>
</plist>
EOF

chmod +x "$MACOS_DIR/$APP_NAME"

echo "✅ 100% Native App created successfully at:"
echo "👉 $APP_DIR"
