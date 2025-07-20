#!/bin/bash

set -e

./build.sh

# Close any existing WinDock instances
pkill -f "WinDock.app" 2>/dev/null || true

# Wait a moment for the process to fully terminate
sleep 1

# run with logs ./build/Build/Products/Release/WinDock.app
./build/Build/Products/Release/WinDock.app/Contents/MacOS/WinDock