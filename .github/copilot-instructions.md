---
GitHub Copilot Coding Guidelines:

1. ✅ Write clean, human-readable code.
   - Use descriptive variable and function names.
   - Structure logic clearly, avoid clever shortcuts that reduce readability.

2. 🧠 Add comments **only if absolutely necessary** (e.g., complex algorithms).
   - Do NOT add comments for obvious or self-explanatory code.

3. 🛑 Never generate README.md or any Markdown documentation.
   - Focus only on the codebase, not external or support files.

4. 🔁 Always search for and reuse **existing code in the same repository**.
   - Adapt patterns, modules, or utilities already defined.
   - Avoid duplicating logic if similar functionality already exists.

5. 🐞 Always check for **potential bugs** and prefer to write robust, safe code.
   - Validate inputs, handle edge cases, and use try/catch if appropriate.
   - Fix any anti-patterns or fragile constructs in legacy code where found.

6. 🚀 Use the full expressive power of the programming language.
   - Leverage built-in features, libraries, and language idioms when beneficial.
   - Write concise and efficient logic where it does not compromise clarity.

7. 🔄 Avoid deep nesting in conditionals (max 1–2 levels).
   - Use early `return` or guard clauses (`if (x) return`) to simplify control flow.
   - Prefer flat and readable method bodies over deeply indented logic.
   - always use { and } when have one line code under if

Example of Preferred Style:

❌ Bad: nested and verbose
```
function validate(user) {
  if (user) {
    if (user.age > 18) {
      if (user.active) {
        return true;
      }
    }
  }
  return false;
}
```

✅ Good: early returns and clear logic
```
function validate(user) {
  if (!user) { return false; }
  if (user.age <= 18) { return false; }
  if (!user.active) { return false; }
  return true;
}
```

---