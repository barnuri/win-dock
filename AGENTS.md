# GitHub Copilot Agent Configuration

This document describes the GitHub Copilot agent configuration for the WinDock project.

## Configuration Location

Agent instructions are defined in `.github/copilot-instructions.md`

## Project Context

**WinDock** is a Swift-based macOS dock application inspired by uBar and Windows 11 Taskbar, built with SwiftUI.

## Core Principles

### 1. File Structure & Organization 📁

-   **One view per file**: Each SwiftUI view must be in its own dedicated file
-   **Separation of concerns**: UI logic in views, business logic in models/managers
-   **Logical grouping**: Related functionality organized into folders (Views/, Models/, Managers/, Utilities/)
-   **File size limit**: Keep files focused and under 300 lines when possible

### 2. SwiftUI Architecture 🏗️

-   **State management**:
    -   `@StateObject` for model objects owned by a view
    -   `@ObservableObject` + `@Published` for shared state management
    -   `@EnvironmentObject` for dependency injection
    -   `@AppStorage` for simple user preferences
-   **View composition**: Prefer composition over inheritance
-   **Reusability**: Create reusable view components for common UI patterns

## Code Quality Standards

### 3. Swift Idioms ✅

-   Descriptive, self-documenting names
-   Explicit types for public APIs
-   Value semantics and copy-on-write collections
-   Proper error handling with `Result`, `throws`, and `do-catch`

### 4. Access Control 🔒

-   **Always explicit**: Specify `private`, `internal`, or `public` on every declaration
-   **Per-declaration**: Access levels not inherited from extensions
-   **Principle of least privilege**:
    -   `private` for implementation details
    -   `internal` for module scope
    -   `public` for external APIs
    -   `private(set)` for read-only external access

### 5. Performance & Safety 🎯

-   `guard` statements for early returns and validation
-   Prefer `let` over `var`
-   Lazy properties and computed properties where appropriate
-   Safe optional handling: `if let`, `guard let`, nil-coalescing

### 6. Documentation 🧠

-   Documentation comments (`///`) for **public APIs only**
-   Comments for complex algorithms or non-obvious business logic
-   **NO comments** for obvious code or implementation details
-   Follow Swift documentation comment format

## SwiftUI Best Practices

### 7. View Structure 🎨

-   Simple view bodies; extract complex logic to computed properties
-   Use `ViewBuilder` for conditional view construction
-   Prefer `HStack`, `VStack`, `ZStack` over manual positioning
-   Use `containerRelativeFrame` and built-in layout modifiers

### 8. State Management 📊

-   `@State` for local view state only
-   `@StateObject` for creating observable objects
-   `@ObservedObject` when passed from parent views
-   `@EnvironmentObject` for cross-hierarchy dependencies

## Error Handling & Safety

### 9. Defensive Programming 🛡️

-   Handle all edge cases and invalid inputs
-   Use Swift's type system to prevent runtime errors
-   Compile-time safety over runtime checks
-   Assertions for development-time checks only

### 10. Control Flow 🔄

-   Maximum 2-3 levels of nesting
-   Early returns with `guard` statements
-   Always use braces `{}` (even for single-line conditionals)
-   Prefer `switch` over long `if-else` chains

## Project-Specific Rules

### 11. Code Reuse & Consistency 🔄

-   **Search first**: Always look for existing patterns before creating new ones
-   Adapt existing utilities and managers instead of duplicating
-   Follow established naming conventions and architectural patterns
-   Reference existing views for consistent styling

### 12. Scope Limitations 🚫

**Agent WILL**:

-   Generate Swift code and Xcode project files
-   Work within iOS/macOS app development ecosystem

**Agent will NOT**:

-   Generate README.md, documentation, or marketing materials
-   Create unnecessary configuration files or scripts
-   Work outside the app development scope

## Performance Optimization

### 13. macOS Performance ⚡

-   Lazy loading for heavy resources (images, data)
-   Proper cleanup in `deinit` when necessary
-   Avoid excessive observers or timers
-   Use `@MainActor` for UI updates with concurrency

### 14. Apple Framework Conventions 🔧

-   `Combine` for reactive programming
-   `async/await` for modern concurrency
-   `Result` types for error propagation
-   `UserDefaults` with `@AppStorage` for simple persistence

## Critical: UI Performance & Responsiveness

### 15. Main Thread Protection 🚫

**NEVER block the main thread** to prevent dock freezing/stacking:

-   Move ALL heavy computations to background queues: `Task.detached(priority: .background)`
-   Use `await withTaskGroup` for concurrent processing
-   Async versions of expensive operations (window enumeration, app scanning)
-   Always `@MainActor` for UI updates

### 16. Debouncing ⏱️

-   Debounce rapid state changes (50-100ms delays)
-   Use `DispatchWorkItem` to cancel pending updates
-   Batch multiple notifications into single UI updates
-   Cache expensive computed properties

### 17. View Performance 🎯

-   Use `ForEach(Array(enumerated()), id: \.element.id)` instead of `firstIndex` in loops
-   View memoization with `@State` cached results
-   Minimize `@Published` properties - combine related state
-   `Equatable` conformance to prevent unnecessary updates

### 18. UI Recomposition Prevention 🔄

-   Cache computed views/styles with `@State`
-   Use `onChange` with debouncing instead of frequent observers
-   Avoid creating new objects in view `body`
-   Minimize animation complexity (prefer 0.1s over 0.15s+)

### 19. Data Operations 📊

-   Concurrent `TaskGroup` for processing collections
-   Lazy evaluation for expensive operations
-   Cache frequently accessed data (app icons, window info)
-   `async/await` with proper task cancellation

### 20. SwiftUI Anti-Patterns 🎨

**AVOID**:

-   Network/file operations directly in view `body`
-   Creating `Timer` objects in views (use centralized managers)
-   `DispatchQueue.main.sync` (causes deadlocks)
-   Excessive `.onReceive` (prefer `@StateObject` + `@Published`)

## Code Examples

### ✅ Good: Access Control & Early Returns

```swift
public struct DockItem {
    public let identifier: String
    private let application: NSRunningApplication

    public init?(application: NSRunningApplication) {
        guard let bundleId = application.bundleIdentifier else { return nil }
        self.identifier = bundleId
        self.application = application
    }

    public var isActive: Bool {
        return application.isActive
    }
}
```

### ✅ Good: SwiftUI View Organization

```swift
public struct DockItemView: View {
    @ObservedObject private var item: DockItem
    @State private var isHovered = false

    public init(item: DockItem) {
        self.item = item
    }

    public var body: some View {
        itemContent
            .background(backgroundStyle)
            .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var itemContent: some View {
        // View implementation
    }

    private var backgroundStyle: some View {
        // Background implementation
    }
}
```

### ❌ Bad: Nested Conditions

```swift
func validate(user: User?) -> Bool {
    if let user = user {
        if user.age > 18 {
            if user.isActive {
                return true
            }
        }
    }
    return false
}
```

### ✅ Good: Guard Statements

```swift
func validate(user: User?) -> Bool {
    guard let user = user else { return false }
    guard user.age > 18 else { return false }
    guard user.isActive else { return false }
    return true
}
```

### ❌ Bad: Blocking Main Thread

```swift
func updateApps() {
    let apps = getExpensiveAppList() // Blocks main thread
    self.dockApps = apps
}
```

### ✅ Good: Async with Proper Threading

```swift
func updateApps() {
    Task { @MainActor in
        let apps = await withTaskGroup(of: [DockApp].self) { group in
            group.addTask {
                await self.computeExpensiveAppList() // Background thread
            }
            // ... process results
        }
        self.dockApps = apps // UI update on main thread
    }
}
```

## Alignment with Standards

These guidelines align with:

-   [Apple's Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
-   [Swift Standard Library Programmer's Manual](https://github.com/apple/swift/blob/main/docs/StandardLibraryProgrammersManual.md)

---

_Last updated: October 22, 2025_
