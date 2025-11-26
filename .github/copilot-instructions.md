# GitHub Copilot Instructions for StrictSwift

This file provides instructions for GitHub Copilot when working on Swift code in this repository and any projects using StrictSwift.

---

## Swift Code Analysis with StrictSwift

When working on Swift code, use StrictSwift for static analysis:

1. **Before committing changes**, run analysis:
   ```bash
   swift-strict check <path> --format agent --context-lines 3
   ```

2. **Interpret results**: Parse the JSON output. Focus on:
   - "E" (error): Must fix before proceeding
   - "W" (warning): Should fix, may indicate bugs
   - "S" (suggestion): Consider fixing for code quality

3. **Apply fixes**: When fixes are available in the `fix.edits` array:
   - Use the range coordinates (sl=startLine, sc=startCol, el=endLine, ec=endCol)
   - Apply the replacement text exactly as provided
   - For multiple edits in one file, apply in reverse order (bottom to top)

4. **For automatic fixes**: Run `swift-strict fix <path> --agent` to get 
   structured diffs. Apply high-confidence fixes automatically, prompt for 
   medium-confidence fixes.

5. **Key rules to understand**:
   - force_unwrap: Use `if let`, `guard let`, or nil coalescing instead
   - data_race: Protect shared mutable state with actors or locks
   - retain_cycle: Add `[weak self]` or `[unowned self]` in closures
   - god_class: Split large classes into smaller, focused components
   - circular_dependency: Use protocols or dependency injection

---

## Swift Safety Guidelines

When writing Swift code, follow these Rust-inspired safety patterns:

### Memory Safety
- NEVER use force unwrap (`!`) except in tests or with compile-time guarantees
- NEVER use `try!` or `try?` silently - handle errors explicitly
- ALWAYS use `[weak self]` in escaping closures that capture self
- AVOID force casting (`as!`) - use conditional casting with `as?`

### Concurrency Safety (Swift 6+)
- Mark types crossing isolation boundaries as `Sendable` or `@unchecked Sendable`
- Use `actor` for shared mutable state instead of locks
- Prefer structured concurrency (`async let`, `TaskGroup`) over `Task { }`
- Never capture non-Sendable types in `@Sendable` closures

### Architecture
- Keep types under 500 lines - split god classes into focused components
- Limit dependencies per type to under 15 - use dependency injection
- Avoid circular dependencies - use protocols to break cycles
- Respect layer boundaries: UI → Domain → Data (never upward)

### Code Quality
- Keep functions under 50 lines - extract helper methods
- Limit nesting depth to 4 levels - use early returns with `guard`
- Keep cyclomatic complexity under 10 - simplify conditionals
- Avoid mutable global state - use dependency injection

### Security
- NEVER hardcode secrets, API keys, or credentials
- Use parameterized queries for database operations
- Prefer CryptoKit over deprecated Security framework APIs
- Sanitize user input before use in commands or queries

### Testing
- Add timeouts to async tests: `await fulfillment(timeout: 5.0)`
- Avoid flaky patterns: random values, timing dependencies, file system state
- Ensure test isolation - don't share mutable state between tests

### What to Avoid
- `print()` in production code - use proper logging
- `fatalError()` except for truly unrecoverable states
- Repeated allocations in loops - preallocate collections
- String concatenation in loops - use `joined()` or `StringBuilder`
- Compiling regex in loops - compile once outside the loop
