# Homebrew Tap for WinDock

This is the official Homebrew tap for WinDock, a Windows 11-style taskbar for macOS.

## Installation

First, add this tap to your Homebrew:

```bash
brew tap barnuri/brew
```

Then install WinDock:

```bash
brew install barnuri/brew/windock --no-quarantine
```

## Usage

After installation, you can run WinDock from the Applications folder or use:

```bash
open "$(brew --prefix)/WinDock.app"
```

To add WinDock to your Applications folder:

```bash
ln -sf "$(brew --prefix)/WinDock.app" /Applications/WinDock.app
```

## Updating

To update WinDock to the latest version:

```bash
brew update
brew upgrade windock
```

## Uninstalling

To remove WinDock:

```bash
brew uninstall windock
```

To remove the tap completely:

```bash
brew untap barnuri/windock
```

## Requirements

-   macOS Sonoma (14.0) or later

## About WinDock

WinDock is a Windows 11-style taskbar for macOS that provides:

-   Windows-style taskbar with app icons
-   Start menu functionality
-   System tray with system information
-   Window preview on hover
-   Customizable settings
-   Auto-hide functionality

For more information, visit the [WinDock repository](https://github.com/barnuri/win-dock).
