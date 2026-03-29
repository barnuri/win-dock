
# Developer Guide

```
gem install xcpretty

! sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
! xcode-select -p
./build.sh
```

## Xcode Signing Setup (required for Accessibility permissions)

macOS tracks accessibility approvals by code signature. Without a stable signature, each rebuild is treated as a new app and the permission is lost.

1. Open `WinDock.xcodeproj` in Xcode
2. Select the **WinDock** target → **Signing & Capabilities**
3. Enable **Automatically manage signing**
4. Set **Team** to your Apple Developer account (login)

Once configured, `build.sh` uses Xcode's signing automatically and accessibility approvals persist across rebuilds.
