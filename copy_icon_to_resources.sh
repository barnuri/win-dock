#!/bin/bash

# Exit on error
set -e

# Check if the icon.png file exists
if [ ! -f "icon.png" ]; then
  echo "Error: icon.png not found in the current directory"
  exit 1
fi

# Copy icon.png to the bundle's Resources directory
echo "Copying icon.png to the app bundle's resources..."

# First, find the built app bundle (should be in build/Build/Products/Debug)
APP_PATH=$(find build/Build/Products -name "*.app" | head -n 1)

if [ -z "$APP_PATH" ]; then
  echo "Error: Could not find the built app bundle."
  echo "Please run ./build.sh first to build the app."
  exit 1
fi

# Copy the icon to the Resources directory
RESOURCES_PATH="$APP_PATH/Contents/Resources"

echo "Copying icon.png to $RESOURCES_PATH..."
cp icon.png "$RESOURCES_PATH/"

echo "Icon successfully copied to app bundle."
echo "Please run the app again to see the changes."
