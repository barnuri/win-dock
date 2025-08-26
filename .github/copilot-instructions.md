---


GitHub Copilot Coding Guidelines for WinDock (Swift Dock App, like uBar/Windows 11 Taskbar):

**File Structure & Separation**

1. 📁 **Always place each SwiftUI view in its own file.**
    - Do not define multiple views in a single file unless they are trivial private helpers.
    - Split UI and business logic into separate files: keep view code (UI) and logic/model code (state, data, actions) apart.
    - Prefer small, focused code files over large, monolithic files.

2. ✅ Write clean, human-readable Swift code.


    - Use descriptive variable, property, and function names.
    - Structure logic clearly; avoid clever shortcuts that reduce readability.

3. 🧠 Add comments **only if absolutely necessary** (e.g., complex algorithms or non-obvious UI logic).
    - Do NOT add comments for obvious or self-explanatory code.

4. 🛑 Never generate README.md, Markdown documentation, or non-code support files.
    - Focus only on the Swift codebase and project files.

5. 🔁 Always search for and reuse **existing code in the same repository**.
    - Adapt patterns, classes, or utilities already defined in WinDock.
    - Avoid duplicating logic if similar functionality already exists.

6. 🐞 Always check for **potential bugs** and prefer to write robust, safe Swift code.
    - Validate inputs, handle edge cases, and use guard/if let/try/catch as appropriate.
    - Fix any anti-patterns or fragile constructs in legacy code where found.

7. 🚀 Use the full expressive power of Swift and macOS frameworks.
    - Leverage built-in features, Swift idioms, and Apple APIs when beneficial.
    - Write concise and efficient logic where it does not compromise clarity.

8. 🔄 Avoid deep nesting in conditionals (max 1–2 levels).
    - Use early `return` or guard clauses (`if ... { return }` or `guard ... else { return }`) to simplify control flow.
    - Prefer flat and readable method bodies over deeply indented logic.
    - Always use `{` and `}` even for single-line if/guard/else blocks.

Example of Preferred Style:

❌ Bad: nested and verbose

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

✅ Good: early returns and clear logic

```swift
func validate(user: User?) -> Bool {
    guard let user = user else { return false }
    if user.age <= 18 { return false }
    if !user.isActive { return false }
    return true
}
```

---
