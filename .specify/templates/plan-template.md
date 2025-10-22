# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]
**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: [e.g., Python 3.11, Swift 5.9, Rust 1.75 or NEEDS CLARIFICATION]  
**Primary Dependencies**: [e.g., FastAPI, UIKit, LLVM or NEEDS CLARIFICATION]  
**Storage**: [if applicable, e.g., PostgreSQL, CoreData, files or N/A]  
**Testing**: [e.g., pytest, XCTest, cargo test or NEEDS CLARIFICATION]  
**Target Platform**: [e.g., Linux server, iOS 15+, WASM or NEEDS CLARIFICATION]
**Project Type**: [single/web/mobile - determines source structure]  
**Performance Goals**: [domain-specific, e.g., 1000 req/s, 10k lines/sec, 60 fps or NEEDS CLARIFICATION]  
**Constraints**: [domain-specific, e.g., <200ms p95, <100MB memory, offline-capable or NEEDS CLARIFICATION]  
**Scale/Scope**: [domain-specific, e.g., 10k users, 1M LOC, 50 screens or NEEDS CLARIFICATION]

## Constitution Check

_GATE: Must pass before Phase 0 research. Re-check after Phase 1 design._

**Principle I - File Structure & Organization:**

-   [ ] Each SwiftUI view in its own file?
-   [ ] UI logic separated from business logic (Views vs Models/Managers)?
-   [ ] Related functionality grouped logically (Views/, Models/, Managers/, Utilities/)?
-   [ ] Files under 300 lines when possible?

**Principle II - SwiftUI Architecture & State Management:**

-   [ ] Correct use of `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@AppStorage`?
-   [ ] Composition preferred over inheritance?
-   [ ] Reusable view components identified and planned?

**Principle III - Code Quality & Swift Idioms:**

-   [ ] Descriptive, self-documenting names planned?
-   [ ] Explicit types for public APIs?
-   [ ] Proper error handling approach (`Result`, `throws`, `do-catch`)?
-   [ ] Access modifiers strategy defined (`private`, `internal`, `public`)?
-   [ ] `guard` statements for early returns planned?
-   [ ] Optional handling strategy defined?

**Principle IV - UI Performance & Responsiveness:**

-   [ ] Heavy computations moved to background queues (`Task.detached`)?
-   [ ] Async versions of expensive operations planned (window enumeration, app scanning)?
-   [ ] `@MainActor` for UI updates identified?
-   [ ] Debouncing strategy for rapid state changes (50-100ms)?
-   [ ] Caching strategy for expensive computed properties?
-   [ ] SwiftUI view performance optimizations planned (`ForEach` enumeration, memoization)?
-   [ ] No main thread blocking operations?
-   [ ] No forbidden patterns (network/file in view `body`, `Timer` in views, `DispatchQueue.main.sync`)?

**Principle V - Testing, Documentation & Code Reuse:**

-   [ ] Unit tests planned for business logic?
-   [ ] Integration tests planned for system integration points?
-   [ ] Manual testing checklist identified (multi-monitor, performance under load)?
-   [ ] Documentation approach defined (public APIs only)?
-   [ ] Existing patterns researched and identified for reuse?
-   [ ] Existing utilities/managers identified for adaptation?

**Technology Stack Compliance:**

-   [ ] Swift 5.9+ / SwiftUI / AppKit where needed?
-   [ ] macOS 14+ target confirmed?
-   [ ] Performance goals understood (60fps, <100ms response, <200MB memory)?
-   [ ] System permissions identified (Accessibility, Screen Recording if needed)?
-   [ ] Multi-monitor and All Spaces support considered?

**Any violations requiring justification?** (If yes, document in Complexity Tracking section)

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
# [REMOVE IF UNUSED] Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
├── cli/
└── lib/

tests/
├── contract/
├── integration/
└── unit/

# [REMOVE IF UNUSED] Option 2: Web application (when "frontend" + "backend" detected)
backend/
├── src/
│   ├── models/
│   ├── services/
│   └── api/
└── tests/

frontend/
├── src/
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# [REMOVE IF UNUSED] Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure: feature modules, UI flows, platform tests]
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation                  | Why Needed         | Simpler Alternative Rejected Because |
| -------------------------- | ------------------ | ------------------------------------ |
| [e.g., 4th project]        | [current need]     | [why 3 projects insufficient]        |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient]  |
