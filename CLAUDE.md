# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WinDock is a macOS SwiftUI application that provides a Windows 11-style taskbar for macOS. It runs as an accessory app with a system tray menu and provides app management, window previews, and desktop customization.

## Build and Run Commands

### Quick Development
```bash
./run.sh              # Build, run, and tail logs with hot reload support
./build.sh            # Build release version only
./open.sh             # Open built app from build directory
```

### Xcode Development
```bash
open WinDock.xcodeproj  # Open in Xcode
# Press ⌘R to build and run
# Press ⌘U to run tests
```

### Testing
```bash
# Run unit tests
xcodebuild test -scheme WinDock -destination 'platform=macOS'

# Run specific test
xcodebuild test -scheme WinDock -destination 'platform=macOS' -only-testing:WinDockTests/AppManagerTests/testSpecificTest
```

### Logs
```bash
tail -f ./logs/app.log                           # Follow application logs
open /Users/$USER/Library/Logs/WinDock           # Open logs directory in Finder
```

### Release
```bash
./release.py          # Automated release process (version bump, build, package)
```

## Architecture

### Performance-Critical Design

The app uses a modern, performance-optimized architecture to prevent UI blocking:

1. **Background Task Coordination** (`BackgroundTaskCoordinator.swift`)
   - Centralizes all dock update scheduling with intelligent debouncing
   - Prevents "update storms" by batching notifications (max 3 before forcing update)
   - Adaptive delays based on update frequency (0.5s min interval between updates)
   - All updates flow through `scheduleUpdate(reason:)` method

2. **Async Window Enumeration** (`WindowEnumerationService.swift`)
   - Thread-safe `actor` that performs expensive AX API calls off the main thread
   - 1-second caching layer to avoid redundant window queries
   - Structured concurrency with `withTaskGroup` for parallel window processing
   - All window enumeration happens in background via `Task.detached`

3. **Event-Driven Updates** (`AppManager.swift`)
   - Uses NSWorkspace notifications instead of polling (no timers!)
   - Notifications trigger `coordinator.scheduleUpdate()` which debounces automatically
   - Concurrent app processing using `withTaskGroup` in `computeDockApps()`
   - Heavy computation happens in `Task.detached` to avoid blocking `@MainActor`

**Key Pattern**: Never block the main thread. All expensive operations (AX API, window enumeration, app processing) use `Task.detached` or `actor` isolation.

### Core Component Interactions

```
NSWorkspace Notifications → BackgroundTaskCoordinator (debounce) → AppManager.updateDockApps()
                                                                         ↓
                                                                   Task.detached
                                                                         ↓
                                                            WindowEnumerationService (actor)
                                                                         ↓
                                                                  AX API Calls
                                                                         ↓
                                                                  Back to MainActor
                                                                         ↓
                                                              DockView (SwiftUI)
```

### Main Components

- **Main.swift**: App entry point with `AppDelegate` for lifecycle management
  - Sets up status bar menu and dock windows for all screens
  - Handles dock positioning and multi-monitor support
  - Manages permission requests (AppleScript automation)

- **AppManager.swift**: Central app state coordinator (`@MainActor`)
  - Manages `dockApps` array (published for SwiftUI binding)
  - Handles app activation, hiding, quitting, window management
  - Pin/unpin apps, drag-and-drop reordering with persistence
  - Uses `BackgroundTaskCoordinator` for all update scheduling
  - Uses `WindowEnumerationService` for non-blocking window queries

- **DockView.swift**: Main UI component
  - Renders taskbar with Windows 11 styling (glass materials, gradients)
  - Start menu, task view, search button, system tray
  - Drag-and-drop reordering with `DockDropDelegate`
  - Material caching to prevent race conditions

- **DockWindow.swift**: Custom `NSWindow` for the taskbar
  - Positioned per screen with auto-hide support
  - Uses `NSWindow.Level` and collection behaviors for "always on top" behavior
  - Multi-monitor aware with per-screen instances

- **AppDockItem.swift**: Individual app icon in the taskbar
  - Shows running indicators, window counts, notification badges
  - Hover for window previews, click to activate, right-click context menu
  - Drag source for reordering

- **WindowPreviewView.swift**: Windows 11-style window preview popover
  - Real-time window screenshots using Core Graphics
  - Click to focus, middle-click to close windows

### App State Management

- **Persistence**: UserDefaults for pinned apps, dock order, and settings
- **Reactive Updates**: Combine publishers trigger UI updates
- **Thread Safety**: `@MainActor` isolation for UI-related classes, `actor` for background services

### System Integration

**Private APIs Used** (may break on macOS updates):
- `CGSGetWindowLevel`: Get window z-order level
- `_AXUIElementGetWindow`: Convert AX elements to window IDs
- `_AXUIElementCreateWithRemoteToken`: Brute-force window detection for windows on other spaces

**Permissions Required**:
- Accessibility Access: For window detection and manipulation
- AppleScript/Automation: For app control (activate, hide, quit)

**Fallback Strategy**:
- Use public `CGWindowListCopyWindowInfo` for basic window enumeration
- Gracefully degrade features if private APIs fail

## Key Development Patterns

### Adding a New Feature to AppManager

When adding app-related functionality:

1. Use `coordinator.scheduleUpdate(reason: "your_feature")` instead of calling `updateDockApps()` directly
2. Perform heavy work in `Task.detached` or via `WindowEnumerationService`
3. Return to `@MainActor` only for final UI updates
4. Log operations with `AppLogger.shared.info/debug/error`

Example:
```swift
func newFeature() {
    // Schedule update through coordinator (auto-debounced)
    coordinator.scheduleUpdate(reason: "new_feature_trigger")
}

private func computeDockApps() async -> [DockApp] {
    // Already runs in Task.detached - safe to do heavy work here
    return await Task.detached(priority: .userInitiated) {
        // Heavy computation off main thread
        // ...
    }.value
}
```

### Window Filtering Logic

WinDock replicates AltTab's sophisticated window filtering from `alt-tab-macos` project:
- Standard windows: Normal level, proper subroles (AXStandardWindow, AXDialog)
- Special app cases: Books, Keynote, IINA, Adobe apps, Steam, JetBrains IDEs
- Size constraints: Minimum 100x50 pixels
- Level filtering: Normal and floating windows only (specific apps)

When adding app-specific logic, add to `isSpecialApp()` or `isValidStandardWindow()` in `WindowEnumerationService.swift`.

### Multi-Monitor Support

Each screen gets its own `DockWindow` instance:
- Created in `setupDockWindowsForAllScreens()`
- Positioned based on `dockPosition` (@AppStorage property)
- Recreated on screen configuration changes via `NSApplication.didChangeScreenParametersNotification`

### Material Caching Pattern

`DockView` uses immutable `MaterialCache` struct to prevent race conditions:
```swift
struct MaterialCache: Equatable {
    let transparency: Double
    let material: AnyShapeStyle
}
```
Compute materials synchronously, cache atomically. No async material computation.

## Common Pitfalls

1. **Don't poll for updates**: Use NSWorkspace notifications, not timers
2. **Don't block @MainActor**: Use `Task.detached` for expensive operations
3. **Don't call AX APIs on main thread**: Use `WindowEnumerationService` actor
4. **Don't bypass the coordinator**: Always use `coordinator.scheduleUpdate()` for dock updates
5. **Don't create materials async**: Compute materials synchronously in view body

## Testing Notes

- `AppManagerTests.swift`: Tests core app management logic
- Mock `NSRunningApplication` when testing app detection
- Use XCTest expectations for async operations
- Window enumeration tests require Accessibility permissions in test environment

## Dependencies

- **SettingsAccess** (2.1.0+): SwiftUI settings window integration via Swift Package Manager
- Standard macOS frameworks: AppKit, SwiftUI, Combine, ApplicationServices

## Deployment

- Minimum target: macOS 15.0 (Sonoma)
- Swift 5.0+, Xcode 16.4+
- Distribution: Homebrew tap (`barnuri/brew/windock`)
- Bundle ID: `barnuri.WinDock`

## Debugging Tips

1. **Enable debug logging**: Check `AppLogger.swift` for log levels
2. **Monitor dock updates**: Log messages show debouncing behavior and reasons
3. **Window enumeration issues**: Check Accessibility permissions first
4. **Performance profiling**: Use Instruments to profile main thread blocking
5. **AppleScript errors**: Error -1743 means automation permission needed

## Related Documentation

- See `DEVELOPER_GUIDE.md` for detailed development workflow
- See `ROADMAP.md` for planned features
- See `UI_PERFORMANCE_FIX_PLAN.md` and `UI_PERFORMANCE_QUICK_REFERENCE.md` for recent performance optimization details
