#!/bin/bash

# Script to bump version in Info.plist
# Usage: ./bump_version.sh [major|minor|patch]

set -e

VERSION_TYPE=${1:-patch}

if [[ ! "$VERSION_TYPE" =~ ^(major|minor|patch)$ ]]; then
    echo "Error: Version type must be 'major', 'minor', or 'patch'"
    echo "Usage: $0 [major|minor|patch]"
    exit 1
fi

# Get current version from Info.plist
CURRENT_VERSION=$(plutil -p WinDock/Info.plist | grep CFBundleShortVersionString | awk -F'"' '{print $4}')
echo "Current version: $CURRENT_VERSION"

# Split version into array
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR=${VERSION_PARTS[0]}
MINOR=${VERSION_PARTS[1]:-0}
PATCH=${VERSION_PARTS[2]:-0}

# Bump version based on type
case $VERSION_TYPE in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
echo "New version: $NEW_VERSION"

# Update Info.plist
plutil -replace CFBundleShortVersionString -string "$NEW_VERSION" WinDock/Info.plist
plutil -replace CFBundleVersion -string "$NEW_VERSION" WinDock/Info.plist

echo "✅ Version updated to $NEW_VERSION in WinDock/Info.plist"
echo ""
echo "To commit this change:"
echo "git add WinDock/Info.plist"
echo "git commit -m \"Bump version to $NEW_VERSION\""
