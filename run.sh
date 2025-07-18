#!/bin/bash

set -e

bash build.sh

# Close any existing WinDock instances
pkill -f "WinDock.app" 2>/dev/null || true

# Wait a moment for the process to fully terminate
sleep 1

# Launch the new instance
open ./build/Build/Products/Release/WinDock.app