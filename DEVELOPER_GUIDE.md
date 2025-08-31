# WinDock Developer Setup Guide

## Prerequisites

### Required Tools
- **Xcode 15.0+** - Primary development environment
- **macOS 14.0+** - Minimum deployment target
- **Swift 5.9+** - Programming language
- **Git** - Version control

### Optional Tools
- **Homebrew** - Package manager for additional tools
- **SwiftLint** - Code style enforcement
- **Instruments** - Performance profiling
- **Charles Proxy** - Network debugging (if needed)

## Getting Started

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/win-dock.git
cd win-dock
```

### 2. Install Dependencies
WinDock uses Swift Package Manager for dependencies. Dependencies will be automatically resolved when you open the project in Xcode.

### 3. Open in Xcode
```bash
open WinDock.xcodeproj
```

### 4. Build and Run
1. Select the WinDock scheme
2. Choose your target device (Mac)
3. Press Cmd+R to build and run

## Project Structure

```
WinDock/
├── WinDock/                    # Main application code
│   ├── Main.swift             # App entry point
│   ├── AppManager.swift       # Core app management logic
│   ├── DockWindow.swift       # Main dock window
│   ├── DockView.swift         # Dock UI components
│   ├── AppDockItem.swift      # Individual app icons
│   ├── WindowPreviewView.swift # Window preview popover
│   ├── SettingsView.swift     # Settings interface
│   └── Supporting Files/
├── WinDockTests/              # Unit tests
├── WinDockUITests/            # UI tests
├── Resources/                 # Images, icons, etc.
└── Documentation/             # Additional docs
```

## Architecture Overview

### Core Components

#### AppManager
- **Purpose**: Central coordinator for app detection, management, and state
- **Key Features**: 
  - Event-driven app monitoring using NSWorkspace notifications
  - Window detection and management
  - Notification badge handling
  - Icon caching for performance
- **Thread Safety**: Main actor isolated

#### DockWindow  
- **Purpose**: Main window container and positioning
- **Key Features**:
  - Auto-hide functionality
  - Multi-monitor support
  - Positioning and sizing logic
- **Thread Safety**: Main actor isolated

#### WindowPreviewView
- **Purpose**: Windows 11-style window previews
- **Key Features**:
  - Real-time window screenshots
  - Click to focus functionality
  - Middle-click to close
  - Animated close buttons

### Design Patterns Used

1. **MVVM (Model-View-ViewModel)** - SwiftUI views with ObservableObject view models
2. **Observer Pattern** - NSWorkspace notifications for app state changes
3. **Singleton Pattern** - Shared managers (WindowSnapManager)
4. **Delegation** - Custom NSView delegates for mouse tracking
5. **Factory Pattern** - DockApp creation from various sources

## Development Workflow

### 1. Feature Development
1. Create a feature branch: `git checkout -b feature/your-feature-name`
2. Implement the feature following existing patterns
3. Add unit tests for new functionality
4. Update documentation if needed
5. Test on multiple screen configurations
6. Create pull request

### 2. Testing Strategy

#### Unit Tests (`WinDockTests/`)
- Test core business logic
- Mock external dependencies
- Focus on AppManager and utility functions
- Run with: `Cmd+U`

#### UI Tests (`WinDockUITests/`)  
- Test user interactions
- Verify UI state changes
- Test accessibility features
- Run with: `Cmd+U` (select UI test scheme)

#### Manual Testing Checklist
- [ ] App launches without crashes
- [ ] Dock appears and positions correctly
- [ ] App icons show and update properly
- [ ] Window previews work on hover
- [ ] Click to activate apps works
- [ ] Context menus function
- [ ] Settings panel opens and saves
- [ ] Multi-monitor support (if applicable)
- [ ] Performance under load

### 3. Code Style

#### Swift Style Guidelines
- Follow Apple's Swift API Design Guidelines
- Use descriptive variable names
- Prefer value types over reference types when appropriate
- Use `@MainActor` for UI-related classes
- Document public APIs with /// comments

#### File Organization
- One primary type per file
- Group related functionality with `// MARK:` comments
- Order: Properties → Lifecycle → Public Methods → Private Methods
- Keep files under 500 lines when possible

#### SwiftUI Best Practices
- Prefer `@StateObject` for owned objects, `@ObservedObject` for passed objects
- Extract complex views into separate structures
- Use `@AppStorage` for simple user defaults
- Minimize view body complexity with computed properties

## System Integration

### Required Permissions
WinDock requires several system permissions to function:

1. **Accessibility Access** - To detect and manipulate windows
2. **Screen Recording** - To capture window previews (optional)
3. **Full Disk Access** - To scan applications (optional)

### Private APIs Used
⚠️ **Warning**: These APIs are not guaranteed to remain stable

- `CGSGetWindowLevel` - Get window level for filtering
- `_AXUIElementGetWindow` - Convert AX elements to window IDs
- `CGSHWCaptureWindowList` - Capture window screenshots

### Alternatives to Private APIs
- Use `CGWindowListCopyWindowInfo` for window enumeration
- Use `NSAccessibility` APIs where possible
- Implement fallback mechanisms for critical features

## Performance Optimization

### Key Performance Areas

1. **App Detection**: Use event-driven monitoring instead of polling
2. **Icon Loading**: Implement caching to avoid repeated icon loading
3. **Window Screenshots**: Cache and throttle window captures
4. **UI Updates**: Use debouncing for rapid state changes

### Memory Management
- Use weak references in closures to prevent retain cycles
- Cancel long-running operations in deinit
- Properly manage NSWorkspace notification observers
- Clear caches periodically to prevent unbounded growth

### Debugging Performance
- Use Instruments to profile memory usage
- Monitor main thread blocking
- Check for excessive allocations
- Profile startup time

## Building and Distribution

### Debug Builds
```bash
# Build for development
xcodebuild -scheme WinDock -configuration Debug
```

### Release Builds
```bash
# Build for distribution
xcodebuild -scheme WinDock -configuration Release -derivedDataPath build

# The built app will be in:
# build/Build/Products/Release/WinDock.app
```

### Code Signing
- Development builds use automatic signing
- Distribution builds require a Developer ID certificate
- Update signing settings in Xcode project settings

### Automated Builds
The `build.sh` script provides a convenient build process:
```bash
./build.sh
```

## Troubleshooting

### Common Issues

#### Build Errors
- **Missing Dependencies**: Delete derived data and clean build folder
- **Signing Issues**: Check Apple Developer account and certificates
- **API Deprecations**: Update to newer APIs as needed

#### Runtime Issues
- **Permissions Denied**: Check System Preferences > Security & Privacy
- **Window Detection Fails**: Verify Accessibility permissions
- **Performance Issues**: Profile with Instruments

#### Development Environment
- **Xcode Crashes**: Restart Xcode, clear derived data
- **Simulator Issues**: Reset simulator content and settings
- **Git Issues**: Use `git status` to check repository state

### Debugging Tips

1. **Console Logging**: Use `AppLogger.shared.info()` for structured logging
2. **Breakpoints**: Set breakpoints in critical code paths
3. **View Debugging**: Use Xcode's view debugger for UI issues
4. **Instruments**: Profile performance and memory usage
5. **System Console**: Check Console.app for system-level errors

## Contributing

### Code Review Checklist
- [ ] Code follows style guidelines
- [ ] Unit tests added for new functionality
- [ ] Documentation updated
- [ ] Performance impact considered
- [ ] Accessibility tested
- [ ] Multi-monitor support tested (if applicable)

### Pull Request Template
1. **Description**: What does this PR do?
2. **Testing**: How was this tested?
3. **Performance**: Any performance implications?
4. **Breaking Changes**: Are there any breaking changes?
5. **Screenshots**: Include screenshots for UI changes

## Resources

### Apple Documentation
- [macOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/macos)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [AppKit Documentation](https://developer.apple.com/documentation/appkit)

### Third-Party Resources
- [Alt-Tab-macOS](https://github.com/lwouis/alt-tab-macos) - Similar project for reference
- [SwiftUI Lab](https://swiftui-lab.com/) - Advanced SwiftUI techniques
- [Point-Free](https://www.pointfree.co/) - Architecture patterns

### Community
- [Swift Forums](https://forums.swift.org/)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/swift)
- [r/macOSBeta](https://www.reddit.com/r/macOSBeta/) - For OS-specific issues

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.