#!/bin/bash
set -euo pipefail

# Build the app
echo "Building Clippy1000..."
cd "$(dirname "$0")/.."
swift build -c release

# Create .app bundle
APP_NAME="Clippy1000"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS}"

# Copy binary
cp ".build/release/${APP_NAME}" "${MACOS}/"

# Copy Info.plist
cp "Resources/Info.plist" "${CONTENTS}/"

echo "Built ${APP_DIR}"
echo ""
echo "To install, run:"
echo "  cp -r ${APP_DIR} /Applications/"
echo ""
echo "Or run directly:"
echo "  open ${APP_DIR}"
