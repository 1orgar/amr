#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$DIR/../.." && pwd )"
OUTPUT_DIR="$ROOT_DIR/build"
OUTPUT_BIN="$OUTPUT_DIR/MockDLNARenderer"

mkdir -p "$OUTPUT_DIR"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDK_PATH="$(xcrun --show-sdk-path)"

echo "⚡ Compiling standalone MockDLNARenderer..."
swiftc -O \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx14.0 \
    -framework Foundation \
    -framework Network \
    "$DIR/MockDLNARendererServer.swift" \
    "$DIR/main.swift" \
    -o "$OUTPUT_BIN"

echo "✅ Built successfully: $OUTPUT_BIN"
