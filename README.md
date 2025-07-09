# Win Dock

A feature-rich macOS SwiftUI application that emulates the Windows taskbar.

## Requirements

-   macOS 14 Sonoma or later
-   Xcode 15 or newer (Swift 5.9)

## Build & Run

```bash
git clone https://github.com/barnuri/win-dock.git
cd win-dock
open WinDock.xcodeproj
```

## Build & Run from Terminal

```bash
./run.sh
```

## Features

### Core Features

-   ✅ Shows running applications as centered icons
-   ✅ Click to activate/launch apps
-   ✅ Always‑on‑top across all Spaces
-   ✅ Position at the bottom of the screen
-   ✅ Pin/unpin favorite applications
-   ✅ Right-click context menus (Show, Hide, Quit, Pin/Unpin)
-   ✅ App hover previews with window count
-   ✅ Running indicator dots
-   ✅ Window count badges
-   ✅ Automatic app monitoring
-   ✅ Settings panel for customization

### Smart App Management

-   Dynamic detection of new apps launching/quitting
-   Persistent pinned applications
-   Proper app state tracking (running, hidden, window count)
-   Smooth animations and hover effects

### System Integration

-   Runs as background accessory app (no dock icon)
-   Proper window level management
-   Multi-monitor support
-   All Spaces support
-   Clean app lifecycle management
