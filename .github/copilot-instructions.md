---

GitHub Copilot Coding Guidelines for WinDock (Swift Dock App, like uBar/Windows 11 Taskbar):

**File Structure & Organization**

1. 📁 **Maintain strict file separation and organization:**
    - Each SwiftUI view must be in its own file (aligned with SwiftUI best practices)
    - Split UI and business logic: views handle UI, models/managers handle state and data
    - Group related functionality into logical folders (Views/, Models/, Managers/, Utilities/)
    - Keep files focused and under 300 lines when possible

2. 🏗️ **Follow SwiftUI architectural patterns:**
    - Use `@StateObject` for model objects owned by a view
    - Use `@ObservableObject` and `@Published` for shared state management
    - Prefer composition over inheritance for view hierarchies
    - Create reusable view components for common UI patterns

**Code Style & Quality**

3. ✅ **Write idiomatic Swift code following official guidelines:**
    - Use descriptive, self-documenting names for variables, functions, and types
    - Prefer explicit types over type inference for public APIs
    - Use Swift's value semantics and copy-on-write collections effectively
    - Leverage Swift's error handling with `Result`, `throws`, and `do-catch`

4. 🔒 **Apply proper access control:**
    - Always specify access modifiers explicitly (`private`, `internal`, `public`)
    - Place access level on each declaration, not inherited from extensions
    - Use `private` for implementation details, `internal` for module scope
    - Make properties `private(set)` when only the declaring type should modify them

5. 🎯 **Optimize for performance and safety:**
    - Use `guard` statements for early returns and input validation
    - Prefer `let` over `var` when values don't change
    - Use lazy properties and computed properties appropriately
    - Handle optionals safely with `if let`, `guard let`, or nil-coalescing

6. 🧠 **Comment strategically (following Swift stdlib practices):**
    - Add documentation comments (`///`) for public APIs only
    - Include comments for complex algorithms or non-obvious business logic
    - Do NOT comment obvious code or implementation details
    - Use Swift's documentation comment format for consistency

**SwiftUI-Specific Guidelines**

7. 🎨 **Structure SwiftUI views effectively:**
    - Keep view bodies simple; extract complex logic into computed properties or methods
    - Use `ViewBuilder` for conditional view construction
    - Prefer `HStack`, `VStack`, `ZStack` over manual positioning when possible
    - Use `containerRelativeFrame` and built-in layout modifiers over custom positioning

8. 📊 **Handle data and state properly:**
    - Use `@State` for local view state only
    - Use `@StateObject` for creating observable objects in views
    - Use `@ObservedObject` when passed from parent views
    - Use `@EnvironmentObject` for dependency injection across view hierarchies
    - Consider `@AppStorage` for simple user preferences

**Error Handling & Code Safety**

9. 🛡️ **Write defensive, robust code:**
    - Always handle edge cases and invalid inputs
    - Use Swift's type system to prevent runtime errors
    - Prefer compile-time safety over runtime checks
    - Use assertions for development-time checks, not production validation

10. 🔄 **Control flow best practices:**
    - Avoid deep nesting (maximum 2-3 levels)
    - Use early returns with `guard` statements for cleaner flow
    - Always use braces `{}` even for single-line conditionals
    - Prefer `switch` over long `if-else` chains when appropriate

**Project-Specific Guidelines**

11. 🔄 **Code reuse and consistency:**
    - Always search for and reuse existing patterns in the WinDock codebase
    - Adapt existing utilities and managers instead of creating duplicates
    - Follow established naming conventions and architectural patterns
    - Reference existing views and components for consistent styling

12. 🚫 **Scope limitations:**
    - Focus exclusively on Swift code and Xcode project files
    - Do not generate README.md, documentation, or marketing materials
    - Avoid creating unnecessary configuration files or scripts
    - Stay within the bounds of the iOS/macOS app development ecosystem

**Code Examples**

✅ **Good: Proper access control and early returns**
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

✅ **Good: SwiftUI view organization**
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

❌ **Bad: Nested conditions and unclear access**
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

✅ **Good: Guard statements and clear flow**
```swift
func validate(user: User?) -> Bool {
    guard let user = user else { return false }
    guard user.age > 18 else { return false }
    guard user.isActive else { return false }
    return true
}
```

**Performance & Memory Management**

13. ⚡ **Optimize for macOS desktop performance:**
    - Use lazy loading for heavy resources (images, data)
    - Implement proper cleanup in `deinit` when necessary
    - Avoid creating excessive observers or timers
    - Use `@MainActor` for UI updates when working with concurrency

14. 🔧 **Follow Apple's framework conventions:**
    - Use `Combine` for reactive programming patterns
    - Leverage `async/await` for modern concurrency
    - Implement proper error propagation with `Result` types
    - Use `UserDefaults` with `@AppStorage` for simple persistence

**UI Performance & Responsiveness (Critical for Dock Stability)**

15. 🚫 **NEVER block the main thread - prevent dock freezing/stacking:**
    - Move ALL heavy computations to background queues using `Task.detached(priority: .background)`
    - Use `await withTaskGroup` for concurrent processing of multiple items
    - Implement async versions of expensive operations (window enumeration, app scanning)
    - Always use `@MainActor` for UI updates and mark UI-related methods accordingly

16. ⏱️ **Implement debouncing for frequent updates:**
    - Debounce rapid state changes (app launches, window updates, mouse tracking) with 50-100ms delays
    - Use `DispatchWorkItem` to cancel pending updates when new ones arrive
    - Batch multiple notifications into single UI updates to prevent excessive refreshes
    - Cache expensive computed properties and invalidate only when underlying data changes

17. 🎯 **Optimize SwiftUI view performance:**
    - Use `ForEach(Array(enumerated()), id: \.element.id)` instead of `firstIndex` in loops
    - Implement view memoization for expensive computations with `@State` cached results
    - Minimize the number of `@Published` properties - combine related state into single objects
    - Use `equatable` conformance on complex data types to prevent unnecessary view updates

18. 🔄 **Prevent excessive UI recomposition:**
    - Cache computed views and styles with `@State` when based on stable data
    - Use `onChange` with proper debouncing instead of frequent property observers
    - Avoid creating new objects in view `body` - extract to `@State` or computed properties
    - Minimize animation complexity and duration (prefer 0.1s over 0.15s+ for dock responsiveness)

19. 📊 **Optimize data operations:**
    - Use concurrent `TaskGroup` for processing collections of apps/windows
    - Implement lazy evaluation for expensive operations (only compute when needed)
    - Cache frequently accessed data (app icons, window info) with proper invalidation
    - Use `async/await` with proper task cancellation for interruptible operations

20. 🎨 **SwiftUI-specific anti-patterns to avoid:**
    - Never perform network/file operations directly in view `body`
    - Avoid creating `Timer` objects in views - use centralized managers
    - Don't use `DispatchQueue.main.sync` - it can cause deadlocks
    - Minimize use of `.onReceive` - prefer `@StateObject` with `@Published` properties

**Example: Converting blocking operation to async**
```swift
// ❌ BAD: Blocks UI thread
func updateApps() {
    let apps = getExpensiveAppList() // Blocks main thread
    self.dockApps = apps
}

// ✅ GOOD: Async with proper threading
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

---

_These guidelines align with Apple's Swift API Design Guidelines and the Swift Standard Library Programmer's Manual._
