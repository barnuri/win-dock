# Win Dock

A feature-rich macOS SwiftUI application that emulates the Wi## Requirements

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
./build.sh
./run.sh
```

## Releases and Versioning

This project uses automated GitHub Actions for building and releasing. The workflow automatically:

1. **Bumps version** in `Info.plist` (patch, minor, or major)
2. **Builds the app** using Xcode
3. **Creates a git tag** with the new version
4. **Creates a GitHub release** with the built app as a downloadable asset

### Triggering a Release

-   **Automatic**: Push to `master` branch triggers a patch version bump and release
-   **Manual**: Use GitHub Actions workflow dispatch to choose version bump type (patch/minor/major)

### Local Version Management

You can also bump versions locally using the included script:

```bash
# Bump patch version (1.0.0 -> 1.0.1)
./bump_version.sh patch

# Bump minor version (1.0.0 -> 1.1.0)
./bump_version.sh minor

# Bump major version (1.0.0 -> 2.0.0)
./bump_version.sh major
```

## What's New

This is a major improvement over the initial MVP version with the following enhancements:

### Architecture Improvements

-   **Proper Background App**: Runs as an accessory app (no dock icon) with LSUIElement
-   **Clean Window Management**: Custom DockWindow class with proper window level and positioning
-   **Modular Design**: Separated concerns into DockWindow, AppManager, DockContentView, and SettingsView

### Enhanced Features

-   **Smart App Detection**: Dynamic monitoring of app launches/quits with real-time updates
-   **Pinned Applications**: Persistent pinned apps with default favorites (Finder, Safari, Mail, etc.)
-   **Rich Context Menus**: Right-click menus with Show/Hide/Quit/Pin/Unpin options
-   **App Previews**: Hover previews showing app name and window count
-   **Visual Indicators**: Running dots and window count badges
-   **Settings Panel**: Configurable options for dock behavior and appearance

### User Experience

-   **Smooth Animations**: Hover effects and transitions for better visual feedback
-   **Better Positioning**: Proper screen edge positioning that respects safe areas
-   **Multi-monitor Ready**: Foundation for multi-display support
-   **All Spaces Support**: Works across all macOS Spaces

### Technical Improvements

-   **Modern APIs**: Uses latest macOS APIs and avoids deprecated methods
-   **Proper Entitlements**: Configured for dock-like behavior without sandbox restrictions
-   **Error Handling**: Better error handling and edge case management
-   **Performance**: Efficient app monitoring with minimal system impact

This version is now much closer to uBar functionality and provides a solid foundation for future enhancements!askbar, similar to uBar.

## Features

### Core Features

-   ✅ Shows running applications as centered icons
-   ✅ Click to activate/launch apps
-   ✅ Always‑on‑top across all Spaces
-   ✅ Adaptive width on multi‑display setups
-   ✅ Transparent background using `Material.ultraThin`
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
-   Default pinned apps (Finder, Safari, Mail, etc.)
-   Proper app state tracking (running, hidden, window count)
-   Smooth animations and hover effects

### System Integration

-   Runs as background accessory app (no dock icon)
-   Proper window level management
-   Multi-monitor support
-   All Spaces support
-   Clean app lifecycle management

## Roadmap

### Near Term

-   🔄 Drag‑to‑reorder icons
-   🔄 Resizable dock
-   🔄 Auto-hide functionality
-   🔄 Window thumbnails on hover
-   🔄 Badge counts for unread notifications

### Future

-   🔄 Per‑display taskbars
-   🔄 Advanced window management
-   🔄 Themes and customization
-   🔄 Gestures support
-   🔄 Mission Control integrationl macOS SwiftUI experiment that emulates the Windows 11 centered taskbar.

## Features (MVP)

-   Shows running applications as centered icons
-   Click to activate apps
-   Always‑on‑top across all Spaces
-   Adaptive width on multi‑display setups
-   Transparent background using `Material.ultraThin`
-   Position at the bottom of the screen (can modify in settings)

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
