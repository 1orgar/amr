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

echo "🔄 Syncing Web/* assets with embedded WebUIContent*.swift..."
python3 - "$MAC_DIR" << 'PYEOF'
import os, re, sys
base = sys.argv[1]
for name, sw, prop in [("app.js", "WebUIContent+JS.swift", "appJS"), ("style.css", "WebUIContent+CSS.swift", "styleCSS"), ("index.html", "WebUIContent+HTML.swift", "indexHTML")]:
    web_path = os.path.join(base, "Web", name)
    sw_path = os.path.join(base, "Sources", "AppleMusicRemoteMac", "Server", sw)
    if os.path.isfile(web_path) and os.path.isfile(sw_path):
        with open(web_path, "r", encoding="utf-8") as f:
            web_s = f.read().rstrip("\n")
        out = f"//\n//  {sw}\n//  AppleMusicRemoteMac\n//\n\nimport Foundation\n\nextension WebUIContent {{\n    public static let {prop}: String = #\"\"\"\n{web_s}\n\"\"\"#\n}}\n"
        with open(sw_path, "r", encoding="utf-8") as f:
            cur_s = f.read()
        if cur_s != out:
            with open(sw_path, "w", encoding="utf-8") as f:
                f.write(out)

core_sw_path = os.path.join(base, "Sources", "AppleMusicRemoteMac", "Server", "WebUIContent.swift")
if os.path.isfile(core_sw_path):
    with open(core_sw_path, "r", encoding="utf-8") as f:
        core_s = f.read()
    orig_core_s = core_s
    for name, props in [("manifest.json", ("manifestJSON",)), ("sw.js", ("serviceWorkerJS", "swJS")), ("apple-touch-icon.svg", ("appleTouchIconSVG",))]:
        web_path = os.path.join(base, "Web", name)
        if os.path.isfile(web_path):
            with open(web_path, "r", encoding="utf-8") as f:
                web_s = f.read().rstrip("\n")
            for prop in props:
                pattern = rf'(public\s+static\s+let\s+{prop}\s*:\s*String\s*=\s*)(?:#"""|""")\n.*?\n\s*(?:"""#|""")'
                core_s = re.sub(pattern, lambda m: f'{m.group(1)}#"""\n{web_s}\n"""#', core_s, flags=re.DOTALL)
    if core_s != orig_core_s:
        with open(core_sw_path, "w", encoding="utf-8") as f:
            f.write(core_s)
PYEOF

SWIFT_SOURCES=()
while IFS= read -r -d '' file; do
    SWIFT_SOURCES+=("$file")
done < <(find "$MAC_DIR/Sources/AppleMusicRemoteMac" -name "*.swift" -print0)


FRAMEWORKS=(
    -framework Cocoa
    -framework Network
    -framework ScriptingBridge
    -framework CoreImage
    -framework CoreAudio
    -framework Accelerate
    -framework NaturalLanguage
    -framework PDFKit
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
    echo "ℹ️ AuthKey_MJHWRCSZHH.p8 not found on build host; building DMG without pre-signed dev token"
fi

GIT_COMMIT_SHORT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "7278dab")"
GIT_COMMIT_DATE="$(git -C "$ROOT_DIR" log -1 --format="%cs" 2>/dev/null || echo "2026-11-04")"

cat << PLIST > "$CONTENTS_DIR/Info.plist"
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
    <string>2.5.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.5.0</string>
    <key>AMRGitCommit</key>
    <string>$GIT_COMMIT_SHORT</string>
    <key>AMRGitCommitDate</key>
    <string>$GIT_COMMIT_DATE</string>
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
    <key>NSAppleMusicUsageDescription</key>
    <string>Apple Music Remote needs access to Apple Music to control playback and view your library.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Apple Music Remote requires AppleEvents permission to control Music.app playback.</string>
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
PLIST

SIGN_IDENTITY="${APPLE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}' || true)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "🔏 Signing with identity: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE" 2>/dev/null || codesign --force --deep --sign - "$APP_BUNDLE"
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
