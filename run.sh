#!/bin/bash

set -e

LOG_FILE="$HOME/Library/Logs/WinDock/app.log"
mkdir -p "$HOME/Library/Logs/WinDock"
touch "$LOG_FILE"
echo "Logs will be written to $LOG_FILE"
ln -sf "$LOG_FILE" ./logs/app.log

build_and_run() {
    ./build.sh

    # Close any existing WinDock instances
    pkill -f "WinDock.app" 2>/dev/null || true

    # Wait a moment for the process to fully terminate
    sleep 3

    ./open.sh
    tail -f "$LOG_FILE"
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