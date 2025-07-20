#!/bin/bash

set -e
rm -rf build/Build/Products/Release || true # Clean previous build artifacts

# Only show errors from xcodebuild (no grep, use xcodebuild options)
xcodebuild -scheme WinDock -configuration Release -derivedDataPath build -quiet -showBuildTimingSummary -hideShellScriptEnvironment | xcpretty && exit ${PIPESTATUS[0]}

# Copy icon.png to the app's resources directory
if [ -f "icon.png" ]; then
    APP_PATH=$(find build/Build/Products -name "*.app" | head -n 1)
    if [ -n "$APP_PATH" ]; then
        RESOURCES_PATH="$APP_PATH/Contents/Resources"
        echo "Copying icon.png to $RESOURCES_PATH..."
        cp icon.png "$RESOURCES_PATH/"
        echo "Icon successfully copied to app bundle."
    else
        echo "Warning: Could not find the built app bundle. Icon not copied."
    fi
else
    echo "Warning: icon.png not found. Icon not copied to app bundle."
fi