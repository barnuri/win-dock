#!/bin/bash

set -e

build_and_run() {
    ./build.sh

    # Close any existing WinDock instances
    pkill -f "WinDock.app" 2>/dev/null || true

    # Wait a moment for the process to fully terminate
    sleep 3

    # run with logs ./build/Build/Products/Release/WinDock.app
    # ./build/Build/Products/Release/WinDock.app/Contents/MacOS/WinDock
    open build/Build/Products/Release/WinDock.app 
    # tail with follow ./logs/app.log
    tail -f ./logs/app.log
}

# Function to run in background and listen for keypresses
run_with_reloader() {
    echo "Starting WinDock with hot reload..."
    echo "Press 'R' + Enter to rebuild and restart, 'Q' + Enter to quit"
    
    # Run the app in background
    build_and_run &
    APP_PID=$!
    
    # Listen for keypresses
    while true; do
        read -n 1 key
        case $key in
            [Rr])
                echo "Rebuilding and restarting WinDock..."
                build_and_run &
                APP_PID=$!
                ;;
            [Qq])
                echo "Quitting..."
                kill $APP_PID 2>/dev/null || true
                pkill -f "WinDock.app" 2>/dev/null || true
                exit 0
                ;;
        esac
    done
}

run_with_reloader