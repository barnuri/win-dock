# WinDock Homebrew Cask

This directory contains the Homebrew cask formula for WinDock, enabling easy installation via Homebrew package manager.

## Quick Install

```bash
brew install --cask windock
```

## Development Setup

For local development and testing, use the provided setup script:

```bash
./setup_homebrew.sh
```

This script provides options to:

1. Install locally for testing
2. Create a custom tap
3. Show instructions for submitting to main Homebrew repository

## Cask Details

-   **Name**: windock
-   **Bundle ID**: barnuri.WinDock
-   **Minimum macOS**: Sonoma (14.0)
-   **Auto-updates**: Yes
-   **Uninstall**: Gracefully quits the app before removal

## File Locations

The cask manages these application files:

-   App Bundle: `/Applications/WinDock.app`
-   Preferences: `~/Library/Preferences/barnuri.WinDock.plist`
-   Application Support: `~/Library/Application Support/WinDock`
-   Caches: `~/Library/Caches/barnuri.WinDock`

## Uninstallation

```bash
# Remove the app
brew uninstall --cask windock

# Remove all associated files (optional)
brew uninstall --cask --zap windock
```

## Contributing to Homebrew

To submit this cask to the main Homebrew repository:

1. The app must be signed and notarized by Apple
2. Replace `:no_check` with actual SHA256 checksums
3. Ensure stable release versioning
4. Follow [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)

## Testing

Before submitting, always test the cask:

```bash
# Validate syntax
brew style homebrew-cask/windock.rb --cask

# Audit for issues
brew audit --cask homebrew-cask/windock.rb

# Test installation
brew install --cask homebrew-cask/windock.rb
```

## Support

For issues related to:

-   **App functionality**: [WinDock Issues](https://github.com/barnuri/win-dock/issues)
-   **Homebrew installation**: [WinDock Issues](https://github.com/barnuri/win-dock/issues) (tag with `homebrew`)
-   **Homebrew itself**: [Homebrew Discussions](https://github.com/Homebrew/discussions/discussions)
