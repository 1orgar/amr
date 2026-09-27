#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( dirname "$SCRIPT_DIR" )"
APP_NAME="AppleMusicRemote"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME.app with AppIcon..."

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/server"
mkdir -p "$APP_BUNDLE/Contents/Resources/web"

# 1. Compile Native Binary
echo "⚡ Compiling native executable with clang..."
clang -fobjc-arc -O2 \
  -framework Cocoa \
  "$SCRIPT_DIR/main.m" \
  -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 2. Generate Info.plist with AppIcon & LSUIElement
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.applemusic.remote.sidecar</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleMusicUsageDescription</key>
    <string>Управление воспроизведением Apple Music</string>
</dict>
</plist>
EOF

# 3. Copy AppIcon.icns
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
  cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 4. Copy Server and Web Resources
echo "📦 Copying server and web assets..."
cp -R "$PROJECT_DIR/server/"* "$APP_BUNDLE/Contents/Resources/server/"
cp -R "$PROJECT_DIR/web/"* "$APP_BUNDLE/Contents/Resources/web/"

echo "✅ App bundle created successfully with icon at:"
echo "👉 $APP_BUNDLE"
