<!--
Sync Impact Report:
- Version: N/A → 1.0.0
- Initial constitution ratification for WinDock project
- Principles defined: 5 core SwiftUI development principles
- Templates requiring updates:
  ✅ plan-template.md - Updated constitution check section
  ✅ spec-template.md - Aligned with user story priorities and testing approach
  ✅ tasks-template.md - Aligned with phase-based implementation and user story structure
- Follow-up: None - all templates synchronized
- Ratification date: 2025-10-22 (initial adoption)
-->

# WinDock Constitution

## Core Principles

### I. File Structure & Organization

**MUST maintain strict file separation:**

-   Each SwiftUI view MUST be in its own dedicated file
-   UI logic in views, business logic in models/managers - MUST be separated
-   Related functionality MUST be organized into logical folders (Views/, Models/, Managers/, Utilities/)
-   Files SHOULD remain focused and under 300 lines when possible

**Rationale**: Single-file-per-view aligns with SwiftUI best practices, improves maintainability, enables parallel development, and makes the codebase navigable. Separation of concerns prevents view bloat and allows independent testing of business logic.

### II. SwiftUI Architecture & State Management

**MUST follow SwiftUI architectural patterns:**

-   Use `@StateObject` for model objects owned by a view
-   Use `@ObservableObject` + `@Published` for shared state management
-   Use `@EnvironmentObject` for dependency injection across view hierarchies
-   Use `@AppStorage` for simple user preferences
-   Prefer composition over inheritance for view hierarchies
-   Create reusable view components for common UI patterns

**Rationale**: Proper state management prevents subtle bugs, enables SwiftUI's declarative updates, and follows Apple's recommended patterns. Composition enables code reuse and maintainability.

### III. Code Quality & Swift Idioms (NON-NEGOTIABLE)

**MUST write idiomatic Swift code:**

-   Use descriptive, self-documenting names for variables, functions, and types
-   Prefer explicit types over type inference for public APIs
-   Use Swift's value semantics and copy-on-write collections effectively
-   Leverage Swift's error handling with `Result`, `throws`, and `do-catch`
-   Always specify access modifiers explicitly (`private`, `internal`, `public`)
-   Use `private` for implementation details, `internal` for module scope, `public` for external APIs
-   Make properties `private(set)` when only the declaring type should modify them
-   Use `guard` statements for early returns and input validation
-   Prefer `let` over `var` when values don't change
-   Handle optionals safely with `if let`, `guard let`, or nil-coalescing

**Rationale**: Idiomatic Swift code leverages the language's type system for compile-time safety, reduces runtime errors, improves readability, and aligns with Apple's Swift API Design Guidelines and Swift Standard Library conventions.

### IV. UI Performance & Responsiveness (NON-NEGOTIABLE)

**MUST NEVER block the main thread:**

-   Move ALL heavy computations to background queues using `Task.detached(priority: .background)`
-   Use `await withTaskGroup` for concurrent processing of multiple items
-   Implement async versions of expensive operations (window enumeration, app scanning)
-   Always use `@MainActor` for UI updates and mark UI-related methods accordingly
-   Debounce rapid state changes (app launches, window updates, mouse tracking) with 50-100ms delays
-   Use `DispatchWorkItem` to cancel pending updates when new ones arrive
-   Batch multiple notifications into single UI updates to prevent excessive refreshes
-   Cache expensive computed properties and invalidate only when underlying data changes

**SwiftUI view performance requirements:**

-   Use `ForEach(Array(enumerated()), id: \.element.id)` instead of `firstIndex` in loops
-   Implement view memoization for expensive computations with `@State` cached results
-   Minimize the number of `@Published` properties - combine related state into single objects
-   Use `Equatable` conformance on complex data types to prevent unnecessary view updates
-   Cache computed views and styles with `@State` when based on stable data
-   Use `onChange` with proper debouncing instead of frequent property observers
-   Avoid creating new objects in view `body` - extract to `@State` or computed properties
-   Minimize animation complexity and duration (prefer 0.1s over 0.15s+ for dock responsiveness)

**Data operations requirements:**

-   Use concurrent `TaskGroup` for processing collections of apps/windows
-   Implement lazy evaluation for expensive operations (only compute when needed)
-   Cache frequently accessed data (app icons, window info) with proper invalidation
-   Use `async/await` with proper task cancellation for interruptible operations

**SwiftUI anti-patterns to AVOID:**

-   NEVER perform network/file operations directly in view `body`
-   NEVER create `Timer` objects in views - use centralized managers
-   NEVER use `DispatchQueue.main.sync` - it can cause deadlocks
-   Minimize use of `.onReceive` - prefer `@StateObject` with `@Published` properties

**Rationale**: WinDock is a dock application that must remain responsive at all times. Main thread blocking causes freezing, stacking, and poor user experience. Proper async/await usage, debouncing, and SwiftUI optimization patterns ensure smooth 60fps performance and instant responsiveness.

### V. Testing, Documentation & Code Reuse

**Testing approach:**

-   Unit tests SHOULD be added for new business logic functionality
-   Integration tests SHOULD cover system integration points (Accessibility, window management)
-   Manual testing MUST verify multi-monitor support and performance under load
-   Tests follow existing patterns in `WinDockTests/` and `WinDockUITests/`

**Documentation standards:**

-   Documentation comments (`///`) for public APIs only
-   Comments for complex algorithms or non-obvious business logic
-   NO comments for obvious code or implementation details
-   Follow Swift's documentation comment format

**Code reuse (MANDATORY):**

-   MUST search for and reuse existing patterns before creating new ones
-   MUST adapt existing utilities and managers instead of duplicating
-   MUST follow established naming conventions and architectural patterns
-   MUST reference existing views and components for consistent styling

**Rationale**: Testing ensures reliability. Strategic documentation improves API usability without cluttering code. Code reuse prevents duplication, maintains consistency, and reduces maintenance burden.

## Technology Stack & Constraints

**Language & Framework:**

-   Swift 5.9+ (minimum)
-   SwiftUI for all UI components
-   AppKit for system integration where SwiftUI is insufficient
-   Combine for reactive programming patterns
-   async/await for modern concurrency

**Platform & Requirements:**

-   macOS 14 Sonoma or later
-   Xcode 15 or newer
-   Target: macOS desktop application (not iOS/watchOS/tvOS)

**Performance Goals:**

-   60fps UI rendering at all times
-   <100ms response to user interactions
-   <200MB memory footprint under normal usage
-   Smooth animations (prefer 0.1s duration for dock responsiveness)

**System Integration:**

-   Accessibility API access (required for window management)
-   Screen Recording permission (optional, for window previews)
-   Runs as background accessory app
-   Multi-monitor support mandatory
-   All Spaces support mandatory

**Constraints:**

-   No network dependencies for core functionality
-   Minimal external dependencies (prefer Swift Package Manager)
-   Private APIs used with fallback mechanisms (see DEVELOPER_GUIDE.md)
-   Must remain responsive even under high system load

## Development Workflow & Quality Gates

**Feature Development Process:**

1. Create feature branch: `feature/your-feature-name`
2. Implement feature following existing architectural patterns
3. Add unit tests for new business logic
4. Test on multiple screen configurations
5. Update documentation if public APIs changed
6. Create pull request with testing evidence

**Code Review Checklist:**

-   Code follows SwiftUI architectural patterns (Principle II)
-   Access modifiers explicitly specified (Principle III)
-   No main thread blocking (Principle IV verified)
-   Performance impact considered and documented
-   Code reuses existing patterns (Principle V)
-   Unit tests added for new business logic
-   Multi-monitor support tested (if applicable)
-   Documentation updated for public API changes

**Quality Gates (MUST pass before merge):**

-   All unit tests pass (`Cmd+U` in Xcode)
-   No compiler warnings (treat warnings as errors)
-   Manual testing checklist completed (see DEVELOPER_GUIDE.md)
-   Constitution compliance verified (all 5 principles)
-   Performance profiling completed for UI-intensive changes

**Build & Release:**

-   Use `./build.sh` for automated builds
-   Code signing configured for distribution builds
-   Homebrew tap maintained for distribution (`barnuri/brew`)
-   Release notes document user-facing changes

## Governance

**Authority:**
This Constitution supersedes all other development practices and guidelines. In case of conflict between this Constitution and other documentation, this Constitution takes precedence.

**Amendments:**

-   Amendments MUST be documented with rationale
-   Version MUST be incremented following semantic versioning:
    -   MAJOR: Backward incompatible governance/principle removals or redefinitions
    -   MINOR: New principle/section added or materially expanded guidance
    -   PATCH: Clarifications, wording, typo fixes, non-semantic refinements
-   All dependent templates MUST be updated to maintain consistency
-   `LAST_AMENDED_DATE` MUST be updated to the date of change

**Compliance:**

-   All pull requests MUST verify compliance with Core Principles I-V
-   Complexity that violates principles MUST be justified in implementation plan
-   GitHub Copilot agent instructions in `.github/copilot-instructions.md` provide runtime development guidance aligned with this Constitution

**Template Synchronization:**

-   `.specify/templates/plan-template.md` - Constitution Check section MUST reflect current principles
-   `.specify/templates/spec-template.md` - User story structure MUST align with testing approach (Principle V)
-   `.specify/templates/tasks-template.md` - Task organization MUST support SwiftUI file-per-view structure (Principle I)

**Version**: 1.0.0 | **Ratified**: 2025-10-22 | **Last Amended**: 2025-10-22
