#!/bin/bash

set -e
rm -rf build/Build/Products/Release || true # Clean previous build artifacts

# Only show errors from xcodebuild (no grep, use xcodebuild options)
xcodebuild -project WinDock.xcodeproj -scheme WinDock -configuration Release -derivedDataPath build -quiet -showBuildTimingSummary -hideShellScriptEnvironment | xcpretty