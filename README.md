# Win Dock

A minimal macOS SwiftUI experiment that emulates the Windows 11 centered taskbar.

## Features (MVP)

-   Shows running applications as centered icons
-   Click to activate apps
-   Always‑on‑top across all Spaces
-   Adaptive width on multi‑display setups
-   Transparent background using `Material.ultraThin`

## Roadmap

-   Pin favourite apps
-   Drag‑to‑reorder and resize icons
-   Badge counts for unread notifications
-   Per‑display taskbars
-   Context menus & settings UI

## Requirements

-   macOS 14 Sonoma or later
-   Xcode 15 or newer (Swift 5.9)

## Build & Run

```bash
git clone https://github.com/barnuri/win-dock.git
cd win-dock
open WinDock.xcodeproj
```

## Build & Run from Terminal

```bash
./build.sh
./run.sh
```
