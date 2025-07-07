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
git clone https://github.com/<your‑github‑username>/win-dock.git
open win-dock/WinDockApp/WinDockApp.xcodeproj   # or .xcworkspace
# hit ⌘R in Xcode
```

## Build & Run as Xcode Project

If you prefer to work with an Xcode project instead of the Swift Package Manager workspace, you can generate an `.xcodeproj` file:

```bash
swift package generate-xcodeproj
open win-dock/WinDockApp/WinDockApp.xcodeproj
# hit ⌘R in Xcode
```

This will create a classic `.xcodeproj` file that you can open and run in Xcode. Note that keeping only the SwiftPM manifest avoids merge conflicts, so committing the generated `.xcodeproj` is optional.

## Contributing

Pull requests are welcome! Please open an issue first to discuss major changes.

## License

See [LICENSE](LICENSE).

### Open in Xcode (no .xcodeproj needed)

With Xcode 15 or newer you can simply:

```bash
open -a Xcode .
```

Xcode detects the **Package.swift** manifest, generates a workspace, and you can hit **⌘R** to run the Mac app.  
If you really need a classic `.xcodeproj`, run:

```bash
swift package generate-xcodeproj
```

(The generated project can then be committed, but keeping only the SwiftPM manifest avoids merge conflicts.)
