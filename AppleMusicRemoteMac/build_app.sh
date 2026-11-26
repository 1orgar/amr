#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DIR="$SCRIPT_DIR"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
APP_NAME="AppleMusicRemoteMac"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="$ROOT_DIR/build/ModuleCache"
ENTITLEMENTS_PLIST="$SCRIPT_DIR/Entitlements.plist"

echo "🍎 Building 100% Pure Swift macOS Server: $APP_NAME.app..."

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULE_CACHE"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDK_PATH="$(xcrun --show-sdk-path)"

echo "🔄 Assembling Web/* assets..."
if [ -f "$SCRIPT_DIR/Tools/sync_web_ui.py" ]; then
    python3 "$SCRIPT_DIR/Tools/sync_web_ui.py"
elif [ -f "$ROOT_DIR/Tools/sync_web_ui.py" ]; then
    python3 "$ROOT_DIR/Tools/sync_web_ui.py"
fi

echo "⚡ Compiling Swift sources with swiftc..."
SWIFT_SOURCES=()
while IFS= read -r -d '' file; do
    SWIFT_SOURCES+=("$file")
done < <(find "$SCRIPT_DIR/Sources/AppleMusicRemoteMac" -name "*.swift" -print0)

swiftc -parse-as-library \
    -O -whole-module-optimization \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -target arm64-apple-macosx14.0 \
    -I "$SCRIPT_DIR/Sources/CAtomicPrimitives/include" \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework Network \
    -framework ScriptingBridge \
    -framework iTunesLibrary \
    -framework CoreImage \
    -framework CoreAudio \
    -framework AudioToolbox \
    -framework Metal \
    -framework Accelerate \
    -framework NaturalLanguage \
    -framework PDFKit \
    -framework CryptoKit \
    -framework ServiceManagement \
    "${SWIFT_SOURCES[@]}" \
    -o "$MACOS_DIR/$APP_NAME"

# Copy Web UI Assets into App Bundle
if [ -d "$SCRIPT_DIR/Web" ]; then
    echo "📦 Packaging Web UI assets into Resources/Web..."
    mkdir -p "$RESOURCES_DIR/Web"
    cp -R "$SCRIPT_DIR/Web/"* "$RESOURCES_DIR/Web/"
    rm -rf "$RESOURCES_DIR/Web/src"
fi

# Copy Icon & MusicKit Auth Key
if [ -f "$ROOT_DIR/SharedAssets/Icons/macOS/AppIcon.icns" ]; then
    cp "$ROOT_DIR/SharedAssets/Icons/macOS/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$ROOT_DIR/SharedAssets/Icons/macOS/icon_256x256.png" ]; then
    cp "$ROOT_DIR/SharedAssets/Icons/macOS/icon_256x256.png" "$RESOURCES_DIR/icon.png"
fi
# Ensure private key is NEVER bundled inside the .app Resources or copied to Application Support
rm -f "$RESOURCES_DIR"/AuthKey_*.p8
rm -f "$HOME/Library/Application Support/AppleMusicRemoteMac/AuthKey_MJHWRCSZHH.p8"
if [ -f "$ROOT_DIR/AuthKey_MJHWRCSZHH.p8" ]; then
    echo "🎟️ Minting pre-signed public MusicKit Developer JWT into Resources/musickit_dev_token.jwt..."
    xcrun swift -module-cache-path "$MODULE_CACHE" - "$ROOT_DIR/AuthKey_MJHWRCSZHH.p8" "$RESOURCES_DIR/musickit_dev_token.jwt" << 'SWIFTEOF'
import Foundation
import CryptoKit

let args = CommandLine.arguments
guard args.count >= 3 else { exit(1) }
let pem = try String(contentsOfFile: args[1], encoding: .utf8)
let cleaned = pem
    .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
    .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
    .replacingOccurrences(of: "\n", with: "")
    .replacingOccurrences(of: "\r", with: "")
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard let der = Data(base64Encoded: cleaned) else { exit(1) }
let key = try P256.Signing.PrivateKey(derRepresentation: der)
func b64url(_ d: Data) -> String {
    d.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
let now = Int(Date().timeIntervalSince1970)
let exp = now + 86400 * 180
let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": "MJHWRCSZHH"])
let payload = try JSONSerialization.data(withJSONObject: ["iss": "886CSW93R8", "iat": now, "exp": exp])
let signingInput = "\(b64url(header)).\(b64url(payload))"
let sig = try key.signature(for: Data(signingInput.utf8))
let jwt = "\(signingInput).\(b64url(sig.rawRepresentation))"
try jwt.write(toFile: args[2], atomically: true, encoding: .utf8)
SWIFTEOF
else
    echo "ℹ️ AuthKey_MJHWRCSZHH.p8 not found on build host; building without pre-signed dev token"
fi

# Resolve latest Git Commit for Info.plist
GIT_COMMIT_SHORT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "7278dab")"
GIT_COMMIT_DATE="$(git -C "$ROOT_DIR" log -1 --format="%cs" 2>/dev/null || echo "2026-11-04")"

# Create Info.plist
cat << EOF > "$CONTENTS_DIR/Info.plist"
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
    <string>3.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>3.0.0</string>
    <key>AMRGitCommit</key>
    <string>$GIT_COMMIT_SHORT</string>
    <key>AMRGitCommitDate</key>
    <string>$GIT_COMMIT_DATE</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
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
    <key>NSAppleMusicUsageDescription</key>
    <string>Apple Music Remote needs access to Apple Music to control playback and view your library.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Apple Music Remote needs permission to control the Music app.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Apple Music Remote needs audio capture access to perform real-time spectral quality verification and stream lossless PCM audio.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Apple Music Remote needs audio access to perform real-time spectral quality verification.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Apple Music Remote uses the local network for Web UI, UPnP/DLNA, and mobile remote control.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_applemusicremote._tcp</string>
        <string>_amr._tcp</string>
        <string>_musc._tcp</string>
    </array>
</dict>
</plist>
EOF

chmod +x "$MACOS_DIR/$APP_NAME"

# Strip Finder .DS_Store and extended attributes so strict codesign / notarization never fails
find "$APP_BUNDLE" -name ".DS_Store" -delete 2>/dev/null || true
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# Prefer Developer ID Application if installed, otherwise Apple Development, otherwise ad-hoc
DEV_ID_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -n 1 | awk -F'"' '{print $2}')
DEV_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}')
if [ -n "$DEV_ID_IDENTITY" ]; then
    echo "🔏 Signing macOS App with Developer ID Application: $DEV_ID_IDENTITY"
    codesign --force --deep --options runtime --timestamp --entitlements "$ENTITLEMENTS_PLIST" -s "$DEV_ID_IDENTITY" "$APP_BUNDLE" 2>/dev/null \
        || codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS_PLIST" -s "$DEV_ID_IDENTITY" "$APP_BUNDLE" 2>/dev/null \
        || codesign --force --options runtime --entitlements "$ENTITLEMENTS_PLIST" -s - "$APP_BUNDLE"
elif [ -n "$DEV_IDENTITY" ]; then
    echo "🔏 Signing macOS App with Apple Developer identity: $DEV_IDENTITY"
    codesign --force --options runtime --entitlements "$ENTITLEMENTS_PLIST" -s "$DEV_IDENTITY" "$APP_BUNDLE" 2>/dev/null \
        || codesign --force --options runtime --entitlements "$ENTITLEMENTS_PLIST" -s - "$APP_BUNDLE"
else
    echo "🔏 Signing macOS App ad-hoc with hardened runtime & entitlements..."
    codesign --force --options runtime --entitlements "$ENTITLEMENTS_PLIST" -s - "$APP_BUNDLE"
fi

echo "✅ Pure Swift macOS App built successfully at:"
echo "👉 $APP_BUNDLE"
