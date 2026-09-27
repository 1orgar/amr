#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "========================================================"
echo "🚀 Building Apple Music Remote 100% Pure Swift Ecosystem"
echo "========================================================"

echo ""
echo "1️⃣ Building macOS Server (AppleMusicRemoteMac)..."
"$DIR/AppleMusicRemoteMac/build_app.sh"

echo ""
echo "2️⃣ Building iOS iPhone App (AppleMusicRemoteIOS)..."
"$DIR/AppleMusicRemoteIOS/build_ios.sh"

echo ""
echo "========================================================"
echo "🎉 Build Completed Successfully!"
echo "🍏 macOS Server: $DIR/AppleMusicRemoteMac/build/AppleMusicRemoteMac.app"
echo "📱 iOS Client:   $DIR/AppleMusicRemoteIOS/build/AppleMusicRemoteIOS.app"
echo "========================================================"
