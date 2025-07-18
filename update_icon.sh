#!/bin/bash

# Exit on error
set -e

# Source icon
SOURCE_ICON="icon.png"

# Check if source icon exists
if [ ! -f "$SOURCE_ICON" ]; then
  echo "Error: $SOURCE_ICON does not exist"
  exit 1
fi

# Target directory
TARGET_DIR="WinDock/Assets.xcassets/AppIcon.appiconset"

# Resize and save icon in different sizes
echo "Creating different sizes of the icon..."

# Create icon sizes
SIZES=(16 32 128 256 512)

for size in "${SIZES[@]}"; do
  # 1x version
  echo "Creating $size x $size icon..."
  sips -z $size $size "$SOURCE_ICON" --out "$TARGET_DIR/icon_${size}x${size}.png"
  
  # 2x version (double size)
  double_size=$((size * 2))
  echo "Creating $size x $size @2x icon ($double_size x $double_size)..."
  sips -z $double_size $double_size "$SOURCE_ICON" --out "$TARGET_DIR/icon_${size}x${size}@2x.png"
done

echo "Icon update complete!"
echo "Please build the app to see the changes."
