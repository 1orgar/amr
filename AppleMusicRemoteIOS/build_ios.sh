#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$DIR/.." && pwd )"
APP_NAME="AppleMusicRemoteIOS"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MODULE_CACHE="$ROOT_DIR/build/ModuleCache"

echo "📱 Building 100% Pure Swift iOS Client: $APP_NAME.app (iPhone Simulator)..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE"
mkdir -p "$MODULE_CACHE"

IOS_SDK_PATH="$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk iphonesimulator --show-sdk-path)"

echo "⚡ Compiling Swift iOS sources with swiftc..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun -sdk iphonesimulator swiftc \
    -parse-as-library \
    -O \
    -sdk "$IOS_SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -target arm64-apple-ios17.0-simulator \
    -framework SwiftUI \
    -framework UIKit \
    -framework Network \
    -framework Foundation \
    -framework Combine \
    "$DIR/Sources/Models/Models.swift" \
    "$DIR/Sources/Design/DesignTokens.swift" \
    "$DIR/Sources/Network/BonjourBrowser.swift" \
    "$DIR/Sources/Network/WebSocketClient.swift" \
    "$DIR/Sources/State/PlayerStore.swift" \
    "$DIR/Sources/Views/Components/RemoteImageView.swift" \
    "$DIR/Sources/Views/Components/TrackRowView.swift" \
    "$DIR/Sources/Views/Components/TrackActionSheet.swift" \
    "$DIR/Sources/Views/Components/MiniPlayerView.swift" \
    "$DIR/Sources/Views/Components/ServerDiscoverySheet.swift" \
    "$DIR/Sources/Views/NowPlaying/NowPlayingView.swift" \
    "$DIR/Sources/Views/Stations/StationsView.swift" \
    "$DIR/Sources/Views/Library/PlaylistDetailView.swift" \
    "$DIR/Sources/Views/Library/LibraryView.swift" \
    "$DIR/Sources/Views/Search/UnifiedSearchView.swift" \
    "$DIR/Sources/Views/Queue/QueueView.swift" \
    "$DIR/Sources/Views/App/MainTabView.swift" \
    "$DIR/Sources/App/AppleMusicRemoteApp.swift" \
    -o "$APP_BUNDLE/$APP_NAME"

# Copy Info.plist
cat << 'EOF' > "$APP_BUNDLE/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Apple Music Remote</string>
    <key>CFBundleDisplayName</key>
    <string>Music Remote</string>
    <key>CFBundleIdentifier</key>
    <string>org.ksholokhov.amr</string>
    <key>CFBundleVersion</key>
    <string>2.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>AppleMusicRemoteIOS</string>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSAppleMusicUsageDescription</key>
    <string>Apple Music Remote needs access to Apple Music to search the catalog and control playback.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Apple Music Remote needs access to your local network to discover and connect to your Mac.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_applemusicremote._tcp</string>
    </array>
</dict>
</plist>
EOF

# Create Entitlements
cat << 'EOF' > "$DIR/Entitlements.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.music-kit</key>
    <true/>
</dict>
</plist>
EOF

chmod +x "$APP_BUNDLE/$APP_NAME"

# Code signing (ad-hoc required for iOS Simulator)
echo "🔏 Signing with ad-hoc signature for iOS Simulator..."
codesign -s - --force "$APP_BUNDLE"

echo "✅ Pure Swift iOS App built successfully at:"
echo "👉 $APP_BUNDLE"
