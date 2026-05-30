#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Token Racing"
BUNDLE_DIR=".build/app/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
OUTPUT="${MACOS_DIR}/TokenRacing"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swiftc \
  -sdk "$SDKROOT" \
  -target "$TARGET" \
  Sources/TokenRacing/*.swift \
  -o "$OUTPUT" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Security

if [ -d "Resources" ]; then
  ditto "Resources" "$RESOURCES_DIR"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TokenRacing</string>
  <key>CFBundleIdentifier</key>
  <string>racing.token.TokenRacing</string>
  <key>CFBundleName</key>
  <string>Token Racing</string>
  <key>CFBundleDisplayName</key>
  <string>Token Racing</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

xattr -cr "$BUNDLE_DIR"
xattr -c "$BUNDLE_DIR" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$BUNDLE_DIR" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$BUNDLE_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$BUNDLE_DIR"

echo "$BUNDLE_DIR"
