# StrictSwift

A strict, production-grade static analysis tool for Swift 6+ codebases that enforces an opt-in subset of Swift aligned with Rust-grade safety guarantees.

## Purpose

StrictSwift provides a purpose-built enforcement layer that catches concurrency, architecture, semantic, and memory risks before code reaches production. It enables "Critical Swift Mode" for modules where failure is unacceptable.

## Vision

StrictSwift bridges Swift's expressiveness with Rust's safety culture, bringing the borrow checker and Clippy experience to Swift modules without abandoning the ecosystem.

## Features

- **47 Rules** across safety, concurrency, memory, architecture, complexity, performance, and security categories
- **Incremental Caching** - 13x faster on repeat runs
- **Cross-file Analysis** - Global symbol graph for dead code detection and coupling metrics
- **Graph-Enhanced Rules** - Opt-in advanced analysis with afferent/efferent coupling metrics
- **AI Agent Mode** - Optimized JSON output for AI coding assistants
- **LSP Server** - Real-time diagnostics in VS Code
- **SwiftPM Plugin** - Integrate into your build process
- **Baseline Support** - Gradually adopt strict rules on existing codebases

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/thomasaiwilcox/StrictSwift.git
cd StrictSwift

# Build the tool
swift build

# Install globally (optional)
swift build -c release
cp .build/release/swift-strict /usr/local/bin/
```

### Usage

```bash
# Analyze Swift files
swift run swift-strict check Sources/

# Enable incremental analysis with caching (13x faster on repeat runs)
swift run swift-strict check Sources/ --cache --cache-stats

# Create baseline for existing code
swift run swift-strict baseline Sources/ --profile critical-core

# Run in CI with JSON output
swift run swift-strict ci Sources/ --format json

# Use different profiles
swift run swift-strict check Sources/ --profile rust-inspired
```

### SwiftPM Plugin

Add StrictSwift as a build tool plugin to your package:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/thomasaiwilcox/StrictSwift.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourTarget",
        plugins: [.plugin(name: "StrictSwiftPlugin", package: "StrictSwift")]
    ),
]
```

## CLI Reference

### check - Analyze Swift files

```bash
swift-strict check <path> [options]

Options:
  --format <format>       Output format: human, json, agent (default: human)
  --profile <profile>     Analysis profile (default: critical-core)
  --cache                 Enable incremental analysis cache
  --cache-stats           Show cache hit/miss statistics
  --enhanced              Enable graph-enhanced rules
  --config <path>         Custom configuration file
  --context-lines <n>     Lines of source context in agent format (default: 0)
  --min-severity <level>  Filter: error, warning, or suggestion
```

### fix - Apply automatic fixes

```bash
swift-strict fix <path> [options]

Options:
  --confidence <level>    Minimum confidence: low, medium, high (default: high)
  --dry-run               Preview fixes without applying
  --agent                 Output structured JSON for AI agents
```

### baseline - Create baseline for existing code

```bash
swift-strict baseline <path> [options]

Options:
  --profile <profile>     Analysis profile
  --output <path>         Output file (default: .strictswift-baseline.json)
```

### ci - CI mode with exit codes

```bash
swift-strict ci <path> [options]

Options:
  --format <format>       Output format: human, json
  --baseline <path>       Compare against baseline file
  --fail-on <severity>    Exit non-zero on: error, warning, or suggestion
```

### explain - Get detailed rule explanation

```bash
swift-strict explain <rule-id>

Examples:
  swift-strict explain force_unwrap
  swift-strict explain data_race
  swift-strict explain god_class
```

## Configuration

Create a `.strictswift.yml` in your project root:

```yaml
profile: critical-core

# Enable graph-enhanced rules for cross-file analysis
useEnhancedRules: true

exclude:
  - "Tests/**"
  - "Generated/**"

rules:
  safety:
    enabled: true
    severity: error
  complexity:
    enabled: true
    severity: warning
    options:
      function_length_threshold: "50"
      cyclomatic_complexity_threshold: "10"
```

## Profiles

| Profile | Description |
|---------|-------------|
| **critical-core** | Errors for concurrency, architecture, and safety rules |
| **server-default** | Balanced productivity and safety |
| **library-strict** | API stability focus |
| **app-relaxed** | Light checks for UI code |
| **rust-inspired** | Maximum strictness with Rust-inspired safety patterns |

## Rule Categories

| Category | Rules | Description |
|----------|-------|-------------|
| **Safety** | 8 | Force unwraps, force tries, fatal errors, swallowed errors, print statements |
| **Concurrency** | 7 | Data races, actor isolation, non-Sendable captures, unstructured tasks |
| **Memory** | 4 | Retain cycles, escaping references, exclusive access, resource leaks |
| **Architecture** | 10 | God classes, circular dependencies, coupling metrics, layered dependencies |
| **Complexity** | 5 | Function length, nesting depth, cyclomatic complexity, assertion coverage |
| **Performance** | 6 | ARC churn, large struct copies, regex in loops, string concatenation |
| **Security** | 4 | Hardcoded secrets, SQL injection, insecure crypto, sensitive logging |
| **Testing** | 3 | Async timeouts, flaky patterns, test isolation |

### Graph-Enhanced Rules (opt-in)

Enable with `useEnhancedRules: true` or `--enhanced` for cross-file analysis:

- **god_class_enhanced** - Detects god classes using afferent/efferent coupling metrics
- **coupling_metrics** - Reports instability metrics and coupling violations
- **circular_dependency_graph** - DFS-based cycle detection in type graph
- **non_sendable_capture_graph** - Sendable conformance checking via symbol graph
- **dead_code** - Detects unused functions, types, and variables across files
- **layered_dependencies** - Validates architectural layer boundaries

## VS Code Extension

Install the StrictSwift VS Code extension for real-time diagnostics:

1. Build and install the LSP server:
   ```bash
   swift build -c release --product strictswift-lsp
   cp .build/release/strictswift-lsp /usr/local/bin/
   ```

2. Install the extension from `Editors/vscode/`

See [Editors/vscode/README.md](Editors/vscode/README.md) for detailed instructions.

## Development

```bash
# Run tests (496 tests)
swift test

# Run with coverage
swift test --enable-code-coverage

# Dogfood on itself
.build/debug/swift-strict check Sources/
```

## AI Agent Integration

StrictSwift includes a specialized output format for AI coding assistants (GitHub Copilot, Cursor, Claude, etc.) that provides structured, actionable analysis results.

### Agent Mode Usage

```bash
# Compact JSON output for AI agents
swift-strict check Sources/ --format agent

# Include source context for better understanding
swift-strict check Sources/ --format agent --context-lines 3

# Filter to only high-severity issues
swift-strict check Sources/ --format agent --min-severity warning

# Apply fixes with structured JSON diff output
swift-strict fix Sources/ --agent
```

### Agent Output Format

The `--format agent` output is optimized for AI consumption:

```json
{
  "version": "1.0",
  "status": "violations_found",
  "summary": {"error": 2, "warning": 5, "suggestion": 12},
  "violations": [
    {
      "id": "force_unwrap",
      "sev": "E",
      "file": "Sources/App/Service.swift",
      "line": 42,
      "col": 15,
      "msg": "Force unwrap of optional value",
      "ctx": ["    let user = getUser()", "    let name = user!.name  // <- violation", "    print(name)"],
      "fix": {
        "desc": "Use optional binding",
        "edits": [{"range": {"sl": 42, "sc": 15, "el": 42, "ec": 20}, "text": "user?.name ?? \"\""}]
      }
    }
  ]
}
```

### Recommended System Prompt for AI Agents Using StrictSwift

Add this to your agent's system prompt when working on Swift projects:

```
## Swift Code Analysis with StrictSwift

When working on Swift code, use StrictSwift for static analysis:

1. **Before committing changes**, run analysis:
   swift-strict check <path> --format agent --context-lines 3

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
```

### Recommended System Prompt for Writing Swift Code (Without the Tool)

Use this system prompt to help AI agents write Swift code that avoids common issues StrictSwift catches:

```
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
```

## Documentation

See the [Implementation Plan](PHASE_0_IMPLEMENTATION.md) for detailed development phases.

## License

MIT