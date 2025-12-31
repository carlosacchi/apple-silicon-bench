#!/bin/bash
set -e

# Build the macOS .app bundle with custom icon
# Usage: ./scripts/build-app.sh [release|debug]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

CONFIG="${1:-release}"
APP_NAME="AppleSiliconBench"
BUNDLE_NAME="$APP_NAME.app"

echo "Building osx-bench ($CONFIG)..."
cd "$ROOT_DIR"
swift build -c "$CONFIG"

# Get version from Package.swift
VERSION=$(grep 'let version = ' Package.swift | sed 's/.*"\(.*\)".*/\1/')
echo "Version: $VERSION"

# Create app bundle structure
echo "Creating app bundle..."
rm -rf "dist/$BUNDLE_NAME"
mkdir -p "dist/$BUNDLE_NAME/Contents/MacOS"
mkdir -p "dist/$BUNDLE_NAME/Contents/Resources"

# Copy binary
cp ".build/$CONFIG/osx-bench" "dist/$BUNDLE_NAME/Contents/MacOS/"

# Strip symbols in release mode
if [ "$CONFIG" = "release" ]; then
    strip "dist/$BUNDLE_NAME/Contents/MacOS/osx-bench"
fi

# Create Info.plist
cat > "dist/$BUNDLE_NAME/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>osx-bench</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.carlosacchi.osx-bench</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Apple Silicon Bench</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2024 Carlos Acchi. MIT License.</string>
</dict>
</plist>
EOF

# Copy icon
cp Resources/AppIcon.icns "dist/$BUNDLE_NAME/Contents/Resources/"

# Ad-hoc code sign
echo "Code signing..."
codesign --force --sign - "dist/$BUNDLE_NAME"

echo "Built: dist/$BUNDLE_NAME"

# Also create standalone CLI binary
echo ""
echo "Creating standalone CLI binary..."
cp ".build/$CONFIG/osx-bench" "dist/osx-bench"
if [ "$CONFIG" = "release" ]; then
    strip "dist/osx-bench"
fi
codesign --force --sign - "dist/osx-bench"
echo "Built: dist/osx-bench"

# Create DMG
echo ""
echo "Creating DMG..."
DMG_NAME="AppleSiliconBench-$VERSION.dmg"
rm -f "dist/$DMG_NAME"

# Create temporary DMG directory
DMG_DIR="dist/dmg_temp"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copy app to DMG directory
cp -R "dist/$BUNDLE_NAME" "$DMG_DIR/"

# Create DMG
hdiutil create -volname "Apple Silicon Bench" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "dist/$DMG_NAME"

# Set DMG icon
if [ -f "Resources/AppIcon.icns" ]; then
    # Mount DMG to set icon
    MOUNT_DIR=$(hdiutil attach "dist/$DMG_NAME" -nobrowse -quiet | tail -1 | awk '{print $3}')
    if [ -n "$MOUNT_DIR" ]; then
        # Set volume icon
        cp "Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
        SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
        hdiutil detach "$MOUNT_DIR" -quiet
    fi
fi

# Clean up
rm -rf "$DMG_DIR"

echo "Built: dist/$DMG_NAME"
ls -la dist/
