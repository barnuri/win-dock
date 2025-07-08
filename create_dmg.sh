#!/bin/bash

# Script to create a DMG file for WinDock
# Usage: ./create_dmg.sh [version]

VERSION=${1:-"1.0.0"}
APP_PATH="build/Build/Products/Release/WinDock.app"
DMG_NAME="WinDock-${VERSION}.dmg"

echo "Creating DMG for WinDock version $VERSION..."

# Check if the app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: WinDock.app not found at $APP_PATH"
    echo "Please build the app first by running ./build.sh"
    exit 1
fi

# Create temporary directory for DMG contents
echo "Creating temporary DMG directory..."
mkdir -p dmg_temp
cp -R "$APP_PATH" dmg_temp/

# Create a symbolic link to Applications for easy installation
echo "Creating Applications symlink..."
ln -sf /Applications dmg_temp/Applications

# Create the DMG
echo "Creating DMG file: $DMG_NAME"
hdiutil create -volname "WinDock $VERSION" \
    -srcfolder dmg_temp \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_NAME"

# Clean up
echo "Cleaning up temporary files..."
rm -rf dmg_temp

if [ -f "$DMG_NAME" ]; then
    echo "✅ Successfully created: $DMG_NAME"
    echo "📏 File size: $(du -h "$DMG_NAME" | cut -f1)"
    echo ""
    echo "To test the DMG:"
    echo "  1. Double-click $DMG_NAME to mount it"
    echo "  2. Drag WinDock.app to Applications"
    echo "  3. Run the app from Applications"
else
    echo "❌ Failed to create DMG file"
    exit 1
fi
