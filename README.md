# StrictSwift

A comprehensive static analysis tool for Swift 6+ that enforces safety, architecture, and code quality rules. Originally inspired by Rust's safety-first approach, StrictSwift has evolved into a full-featured Swift linter with semantic analysis, cross-file dependency tracking, and AI agent integration.

> ⚠️ **BETA (v0.1.0)**
> 
> StrictSwift is in beta. While extensively tested (590+ tests), it may contain bugs. The `fix` command modifies your source files.
>
> **Before using:**
> 1. **Use version control** - Always have uncommitted changes backed up
> 2. **Test on a branch first** - Create a feature branch before running fixes
> 3. **Review all changes** - Use `--dry-run` before applying fixes
>
> Backups are created automatically in `.strictswift-backup/` before fixes.

## What It Does

StrictSwift analyzes your Swift code for:

- **Safety Issues** - Force unwraps, force casts, swallowed errors, fatal errors
- **Concurrency Problems** - Data races, actor isolation violations, non-Sendable captures
- **Memory Risks** - Retain cycles, escaping references, resource leaks
- **Architecture Smells** - God classes, circular dependencies, layer violations
- **Complexity** - Long functions, deep nesting, high cyclomatic complexity
- **Performance** - Allocations in loops, large struct copies, regex compilation in loops
- **Security** - Hardcoded secrets, SQL injection patterns, insecure crypto

## Key Features

- **43 Rules** across 7 categories
- **Semantic Analysis** - SourceKit-powered type resolution (macOS, optional on Linux)
- **Cross-file Analysis** - Global symbol graph for dependency and dead code detection
- **Incremental Caching** - Only re-analyzes changed files (enabled by default)
- **AI Agent Mode** - Structured JSON output for Copilot, Cursor, Claude, etc.
- **Automatic Fixes** - Safe fixes with backup and undo support
- **Comment Suppressions** - `// strictswift:ignore <rule>` to suppress specific violations
- **Learning System** - Improves accuracy based on your feedback over time
- **Baseline Support** - Adopt gradually on existing codebases

## Quick Start

```bash
# Clone and build
git clone https://github.com/thomasaiwilcox/StrictSwift.git
cd StrictSwift
swift build -c release

# Install (optional)
sudo cp .build/release/strictswift /usr/local/bin/

# Analyze your code
strictswift check Sources/

# Preview fixes
strictswift fix Sources/ --dry-run

# Apply fixes
strictswift fix Sources/
```

## Configuration

Create `.strictswift.yml` in your project root:

```yaml
# Profile: critical-core, server-default, library-strict, app-relaxed
profile: server-default

# Exclude paths
exclude:
  - "Tests/**"
  - "Generated/**"

# Enable cross-file analysis (requires more memory)
useEnhancedRules: false

# Rule category settings
rules:
  safety:
    enabled: true
    severity: error
  complexity:
    enabled: true
    severity: warning

# Fine-tune thresholds
advanced:
  thresholds:
    maxCyclomaticComplexity: 10
    maxMethodLength: 50
    maxNestingDepth: 4
```

## Suppressing Violations

Use comments to suppress specific violations:

```swift
// Suppress on next line
// strictswift:ignore force_unwrap
let value = optional!

// Suppress multiple rules
// strictswift:ignore force_unwrap, print_in_production

// Suppress with reason
// strictswift:ignore force_unwrap -- Guaranteed non-nil by API contract

// Suppress a block
// strictswift:ignore-start force_unwrap
let a = x!
let b = y!
// strictswift:ignore-end

// Suppress entire file
// strictswift:ignore-file dead-code
```

## CLI Commands

### check - Analyze files

```bash
strictswift check <path> [options]

Options:
  --format <format>       human, json, agent (default: human)
  --profile <profile>     Analysis profile
  --config <path>         Configuration file path
  --no-cache              Disable incremental caching
  --min-severity <level>  Filter: error, warning, info, hint
  --learning              Enable learning system
  --verbose               Show debug output
```

### fix - Apply automatic fixes

```bash
strictswift fix <path> [options]

Options:
  --dry-run               Preview without applying
  --safe-only             Only apply high-confidence fixes
  --diff                  Show unified diff
  --undo                  Restore from backup
```

### Other commands

```bash
strictswift baseline <path>     # Create baseline for existing violations
strictswift explain <rule-id>   # Get detailed rule explanation
strictswift feedback <id> used  # Report a true positive (improves accuracy)
strictswift feedback <id> unused # Report a false positive
```

## Rule Categories

| Category | Count | Examples |
|----------|-------|----------|
| Safety | 8 | `force_unwrap`, `force_try`, `swallowed_error`, `fatal_error` |
| Concurrency | 7 | `data_race`, `actor_isolation`, `non_sendable_capture` |
| Memory | 4 | `retain_cycle`, `escaping_reference`, `resource_leak` |
| Architecture | 10 | `god_class`, `circular_dependency`, `layered_dependencies` |
| Complexity | 5 | `function_length`, `cyclomatic_complexity`, `nesting_depth` |
| Performance | 6 | `arc_churn`, `large_struct_copy`, `string_concatenation_loop` |
| Security | 4 | `hardcoded_secrets`, `sql_injection_pattern`, `insecure_crypto` |

Use `strictswift explain <rule-id>` for details on any rule.

## Cross-File Analysis

Enable with `useEnhancedRules: true` for:

- **Dead code detection** - Finds unused functions, types, and variables across files
- **Circular dependency detection** - DFS-based cycle detection in type graph
- **Coupling metrics** - Afferent/efferent coupling and instability analysis
- **Layered dependencies** - Validates architectural boundaries

**Note**: Dead code detection uses static analysis and may have false positives for:
- Code used via reflection or dynamic dispatch
- Protocol witnesses and synthesized members
- Functions called across module boundaries

Always verify suggestions before deleting code.

## AI Agent Integration

StrictSwift outputs structured JSON for AI coding assistants:

```bash
strictswift check Sources/ --format agent --context-lines 3
```

Output includes file paths, line numbers, fix suggestions with edit coordinates, and source context - everything an AI needs to understand and fix issues.

See [`.github/copilot-instructions.md`](.github/copilot-instructions.md) for recommended system prompts.

## VS Code Extension

Real-time diagnostics via LSP:

```bash
swift build -c release --product strictswift-lsp
sudo cp .build/release/strictswift-lsp /usr/local/bin/
```

Then install the extension from [`Editors/vscode`](Editors/vscode).

## SwiftPM Plugin

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/thomasaiwilcox/StrictSwift.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTarget",
        plugins: [.plugin(name: "StrictSwiftPlugin", package: "StrictSwift")]
    ),
]
```

## Profiles

| Profile | Description |
|---------|-------------|
| **critical-core** | Errors for concurrency, architecture, and safety rules |
| **server-default** | Balanced productivity and safety |
| **library-strict** | API stability focus |
| **app-relaxed** | Light checks for UI code |

## Limitations

- **Semantic analysis requires SourceKit** - On macOS, requires Xcode. On Linux, requires Swift toolchain with SourceKit.
- **Cross-file analysis uses memory** - Large codebases may need more RAM with `useEnhancedRules: true`.
- **Some rules have false positives** - Use the learning system or comment suppressions to handle them.
- **Fix command is conservative** - Not all violations have automatic fixes.

## Troubleshooting

**Semantic analysis not working:**
```bash
strictswift check Sources/ --verbose  # Check SourceKit status
xcode-select --install                 # Ensure Xcode CLI tools
```

**Cache issues:**
```bash
strictswift check Sources/ --clear-cache
```

**Fix broke something:**
```bash
strictswift fix --undo  # Restore from backup
git checkout .           # Or restore from git
```

## Files Created

| File | Purpose | Commit? |
|------|---------|---------|
| `.strictswift.yml` | Configuration | Yes |
| `.strictswift-baseline.json` | Known violations baseline | Yes |
| `.strictswift-cache/` | Analysis cache | No |
| `.strictswift-backup/` | Pre-fix backups | No |
| `.strictswift-learned.json` | Learning system data | Optional |

Add to `.gitignore`:
```gitignore
.strictswift-cache/
.strictswift-backup/
.strictswift-last-run.json
```

## Development

```bash
swift test                              # Run tests (590+)
swift build -c release                  # Release build
.build/debug/strictswift check Sources/ # Dogfood
```

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT
