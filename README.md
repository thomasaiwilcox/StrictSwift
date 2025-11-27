# StrictSwift

A strict, production-grade static analysis tool for Swift 6+ codebases that enforces an opt-in subset of Swift aligned with Rust-grade safety guarantees.

> ⚠️ **BETA WARNING**
> 
> StrictSwift is currently in **beta**. While we've tested it extensively, it may still contain bugs that could potentially corrupt or destroy your codebase, especially when using the \`fix\` command.
>
> **Before using StrictSwift on any project:**
> 1. **Back up your code** - Use git, Time Machine, or another backup method
> 2. **Do NOT run on production code** without a backup
> 3. **Test on a branch first** - Create a feature branch before running fixes
> 4. **Review all changes** - Always review diffs before committing
>
> The \`fix\` command creates automatic backups in \`.strictswift-backup/\`, but we strongly recommend your own backup strategy as well.

## Purpose

StrictSwift provides a purpose-built enforcement layer that catches concurrency, architecture, semantic, and memory risks before code reaches production. It enables "Critical Swift Mode" for modules where failure is unacceptable.

## Vision

StrictSwift bridges Swift's expressiveness with Rust's safety culture, bringing the borrow checker and Clippy experience to Swift modules without abandoning the ecosystem.

## Features

- **47 Rules** across safety, concurrency, memory, architecture, complexity, performance, and security categories
- **Incremental Caching** - 13x faster on repeat runs (enabled by default)
- **Semantic Analysis** - SourceKit-powered type resolution for accurate detection
- **Cross-file Analysis** - Global symbol graph for dead code detection and coupling metrics
- **Graph-Enhanced Rules** - Opt-in advanced analysis with afferent/efferent coupling metrics
- **Learning System** - Improves accuracy based on feedback over time
- **AI Agent Mode** - Optimized JSON output for AI coding assistants
- **LSP Server** - Real-time diagnostics in VS Code
- **SwiftPM Plugin** - Integrate into your build process
- **Baseline Support** - Gradually adopt strict rules on existing codebases
- **Automatic Fixes** - Apply safe fixes with backup and undo support

## Quick Start

### Installation

\`\`\`bash
# Clone the repository
git clone https://github.com/thomasaiwilcox/StrictSwift.git
cd StrictSwift

# Build the tool
swift build

# Install globally (optional)
swift build -c release
sudo cp .build/release/swift-strict /usr/local/bin/
\`\`\`

### Basic Usage

\`\`\`bash
# Analyze Swift files (uses default Sources/ path)
swift-strict check

# Analyze specific path
swift-strict check Sources/MyModule/

# Enable learning system for improved accuracy
swift-strict check Sources/ --learning

# Apply automatic fixes (creates backup first)
swift-strict fix Sources/ --dry-run  # Preview first
swift-strict fix Sources/            # Apply fixes

# Undo fixes if something goes wrong
swift-strict fix --undo
\`\`\`

### SwiftPM Plugin

Add StrictSwift as a build tool plugin to your package:

\`\`\`swift
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
\`\`\`

## CLI Reference

### check - Analyze Swift files

\`\`\`bash
swift-strict check <path> [options]

Options:
  --format <format>       Output format: human, json, agent (default: human)
  --profile <profile>     Analysis profile (default: critical-core)
  --config <path>         Custom configuration file
  --baseline <path>       Path to baseline file
  --fail-on-error         Exit with error code on violations (default: true)
  
  # Caching (enabled by default)
  --no-cache              Disable incremental analysis caching
  --clear-cache           Clear the cache before running
  --cache-stats           Show cache hit/miss statistics
  
  # Agent mode options
  --context-lines <n>     Lines of source context in agent format (default: 0)
  --min-severity <level>  Filter: error, warning, info, hint
  
  # Semantic analysis
  --semantic <mode>       Semantic mode: off, hybrid, full, auto (default: auto)
  --semantic-strict       Fail if requested semantic mode is unavailable
  
  # Learning system
  --learning              Enable learning system for improved accuracy
  --no-violation-cache    Disable violation cache for privacy
  
  # Debug
  --verbose               Enable verbose logging with SourceKit debug info
\`\`\`

### fix - Apply automatic fixes

\`\`\`bash
swift-strict fix <path> [options]

Options:
  --confidence <level>    Minimum confidence: safe, suggested, experimental (default: suggested)
  --safe-only             Only apply safe fixes (same as --confidence safe)
  --rules <rules>         Only fix specific rules (comma-separated)
  --dry-run               Preview fixes without applying
  --diff                  Show diff of changes
  --yes                   Apply without confirmation prompt
  --agent                 Output structured JSON for AI agents
  
  # Backup & Undo
  --undo                  Restore files from last backup
  --no-backup             Skip creating backup (not recommended)
  
  # Semantic analysis
  --semantic <mode>       Semantic mode: off, hybrid, full, auto (default: auto)
  --semantic-strict       Fail if requested semantic mode is unavailable
\`\`\`

**Backup & Undo**: By default, \`fix\` creates a backup in \`.strictswift-backup/\` before modifying files. If fixes cause problems, run \`swift-strict fix --undo\` to restore the original files.

### feedback - Record feedback to improve accuracy

The learning system improves StrictSwift's accuracy over time by learning from your feedback on violations.

\`\`\`bash
swift-strict feedback <violation-id> <feedback-type> [options]

Feedback Types:
  used           Violation was helpful/correct
  unused         Violation was a false positive
  fix-applied    The suggested fix was applied
  fix-rejected   The suggested fix was rejected

Options:
  --note <note>           Explain why (helps improve future analysis)
  --source <source>       Feedback source: user, agent, ci (default: user)
  --stats                 Show feedback statistics
  --list                  List recent feedback entries
  --limit <n>             Number of entries to show (default: 20)
  --rule <rule-id>        Filter by rule ID
  --clear                 Clear all feedback data
  --prune-older-than <n>  Prune feedback older than N days

Examples:
  # Mark a violation as a false positive
  swift-strict feedback abc123 unused --note "intentional design"
  
  # Mark a fix as applied
  swift-strict feedback def456 fix-applied
  
  # View feedback statistics
  swift-strict feedback --stats
  
  # List recent feedback for a specific rule
  swift-strict feedback --list --rule force_unwrap
\`\`\`

### baseline - Create baseline for existing code

\`\`\`bash
swift-strict baseline <path> [options]

Options:
  --profile <profile>     Analysis profile
  --output <path>         Output file (default: .strictswift-baseline.json)
\`\`\`

### ci - CI mode with exit codes

\`\`\`bash
swift-strict ci <path> [options]

Options:
  --format <format>       Output format: human, json
  --baseline <path>       Compare against baseline file
  --fail-on <severity>    Exit non-zero on: error, warning, or suggestion
\`\`\`

### explain - Get detailed rule explanation

\`\`\`bash
swift-strict explain <rule-id>

Examples:
  swift-strict explain force_unwrap
  swift-strict explain data_race
  swift-strict explain god_class
\`\`\`

## Configuration

Create a \`.strictswift.yml\` in your project root:

\`\`\`yaml
profile: critical-core

# Enable graph-enhanced rules for cross-file analysis
useEnhancedRules: true

# Semantic analysis mode (off, hybrid, full, auto)
semanticMode: auto

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
\`\`\`

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

Enable with \`useEnhancedRules: true\` or \`--enhanced\` for cross-file analysis:

- **god_class_enhanced** - Detects god classes using afferent/efferent coupling metrics
- **coupling_metrics** - Reports instability metrics and coupling violations
- **circular_dependency_graph** - DFS-based cycle detection in type graph
- **non_sendable_capture_graph** - Sendable conformance checking via symbol graph
- **dead_code** - Detects unused functions, types, and variables across files (see caveats below)
- **layered_dependencies** - Validates architectural layer boundaries

#### Dead Code Detection Caveats

The \`dead_code\` rule uses static analysis and may produce false positives for:
- Properties accessed via \`self.propertyName\` in complex expressions
- Functions called across module boundaries
- Code used via reflection, dynamic dispatch, or string-based APIs
- Protocol witnesses and synthesized members

**Recommendation**: Always manually verify dead code suggestions before deletion.
Use \`--min-severity warning\` to filter to higher-confidence results only.

## Learning System

StrictSwift includes a learning system that improves accuracy over time based on your feedback.

### How It Works

1. **Run analysis with learning enabled**:
   \`\`\`bash
   swift-strict check Sources/ --learning
   \`\`\`

2. **Provide feedback on violations**:
   \`\`\`bash
   # Mark false positives
   swift-strict feedback abc123 unused --note "intentional design"
   
   # Confirm true positives
   swift-strict feedback def456 used
   \`\`\`

3. **StrictSwift learns**:
   - Patterns marked as false positives are suppressed in future runs
   - Rule confidence is adjusted based on accuracy
   - Low-accuracy patterns are automatically suppressed

### Feedback Statistics

View how the learning system is performing:

\`\`\`bash
swift-strict feedback --stats
\`\`\`

Output:
\`\`\`
📚 Learning Statistics:
   Total feedback entries: 42
   Rules with feedback: 8
   Overall accuracy: 87.3%
   Suppressed patterns: 5
\`\`\`

### Privacy Considerations

By default, StrictSwift stores violation data in \`.strictswift-last-run.json\` for feedback lookup. This file contains file paths and violation messages.

To disable this for privacy:
\`\`\`bash
swift-strict check Sources/ --no-violation-cache
\`\`\`

## VS Code Extension

Install the StrictSwift VS Code extension for real-time diagnostics:

1. Build and install the LSP server:
   \`\`\`bash
   swift build -c release --product strictswift-lsp
   sudo cp .build/release/strictswift-lsp /usr/local/bin/
   \`\`\`

2. Install the extension from \`Editors/vscode/\`

See [Editors/vscode/README.md](Editors/vscode/README.md) for detailed instructions.

## Development

\`\`\`bash
# Run tests (590 tests)
swift test

# Run with coverage
swift test --enable-code-coverage

# Dogfood on itself
.build/debug/swift-strict check Sources/
\`\`\`

## AI Agent Integration

StrictSwift includes a specialized output format for AI coding assistants (GitHub Copilot, Cursor, Claude, etc.) that provides structured, actionable analysis results.

### Agent Mode Usage

\`\`\`bash
# Compact JSON output for AI agents
swift-strict check Sources/ --format agent

# Include source context for better understanding
swift-strict check Sources/ --format agent --context-lines 3

# Filter to only high-severity issues
swift-strict check Sources/ --format agent --min-severity warning

# Enable learning to improve accuracy over time
swift-strict check Sources/ --format agent --learning

# Apply fixes with structured JSON diff output
swift-strict fix Sources/ --agent
\`\`\`

### Agent Output Format

The \`--format agent\` output is optimized for AI consumption:

\`\`\`json
{
  "version": 1,
  "format": "agent",
  "summary": {
    "total": 3,
    "fixable": 2,
    "errors": 1,
    "warnings": 2,
    "info": 0
  },
  "violations": [
    {
      "id": "a1b2c3d4e5f6g7h8",
      "rule": "force_unwrap",
      "category": "safety",
      "severity": "error",
      "message": "Force unwrap of optional value",
      "file": "Sources/App/Service.swift",
      "line": 42,
      "column": 15,
      "context": ["    let user = getUser()", "    let name = user!.name", "    print(name)"],
      "fixes": [{
        "title": "Use optional binding",
        "kind": "insert_if_let",
        "confidence": "suggested",
        "isPreferred": true,
        "edits": [{"file": "...", "startLine": 42, "startColumn": 15, "endLine": 42, "endColumn": 20, "newText": "user?.name ?? \"\""}]
      }]
    }
  ]
}
\`\`\`

### Recommended System Prompt for AI Agents Using StrictSwift

Add this to your agent's system prompt when working on Swift projects:

\`\`\`markdown
## Swift Code Analysis with StrictSwift

When working on Swift code, use StrictSwift for static analysis:

1. **Before committing changes**, run analysis:
   \`\`\`bash
   swift-strict check <path> --format agent --context-lines 3
   \`\`\`

2. **Interpret results**: Parse the JSON output. Focus on:
   - "error" severity: Must fix before proceeding
   - "warning" severity: Should fix, may indicate bugs
   - "info" severity: Consider fixing for code quality

3. **Apply fixes**: When fixes are available in the \`fixes\` array:
   - Use the edit coordinates (startLine, startColumn, endLine, endColumn)
   - Apply the replacement text exactly as provided
   - For multiple edits in one file, apply in reverse order (bottom to top)

4. **For automatic fixes**: Run \`swift-strict fix <path> --agent\` to get 
   structured diffs. Apply high-confidence fixes automatically, prompt for 
   medium-confidence fixes.

5. **CRITICAL - Placeholder defaults**: Some fixes use \`<#default#>\` placeholders
   that require manual replacement. These are intentional to force context-aware
   defaults. If you apply fixes with placeholders, you MUST replace them with
   appropriate values before the code can compile.

6. **Undo capability**: If fixes break the build, run \`swift-strict fix --undo\`
   to restore files from backup. Backups are created automatically before
   applying fixes.

7. **Provide feedback to improve accuracy**:
   - For false positives: \`swift-strict feedback <id> unused --note "reason"\`
   - For true positives: \`swift-strict feedback <id> used\`
   - For applied fixes: \`swift-strict feedback <id> fix-applied\`
   This feedback improves future analysis accuracy.

8. **Key rules to understand**:
   - force_unwrap: Use \`if let\`, \`guard let\`, or nil coalescing instead
   - data_race: Protect shared mutable state with actors or locks
   - retain_cycle: Add \`[weak self]\` or \`[unowned self]\` in closures
   - god_class: Split large classes into smaller, focused components
   - circular_dependency: Use protocols or dependency injection

9. **Dead code detection caveats**: The \`dead-code\` rule uses static analysis and
   may produce false positives, especially for:
   - Properties accessed via \`self.propertyName\` in complex expressions
   - Functions called across module boundaries
   - Code used via reflection, dynamic dispatch, or string-based APIs
   - Protocol witnesses and synthesized members
   
   **Always manually verify dead code suggestions before deletion.**
   Use \`--min-severity warning\` to filter to higher-confidence results.
\`\`\`

### Recommended System Prompt for Writing Swift Code (Without the Tool)

Use this system prompt to help AI agents write Swift code that avoids common issues StrictSwift catches:

\`\`\`markdown
## Swift Safety Guidelines

When writing Swift code, follow these Rust-inspired safety patterns:

### Memory Safety
- NEVER use force unwrap (\`!\`) except in tests or with compile-time guarantees
- NEVER use \`try!\` or \`try?\` silently - handle errors explicitly
- ALWAYS use \`[weak self]\` in escaping closures that capture self
- AVOID force casting (\`as!\`) - use conditional casting with \`as?\`

### Concurrency Safety (Swift 6+)
- Mark types crossing isolation boundaries as \`Sendable\` or \`@unchecked Sendable\`
- Use \`actor\` for shared mutable state instead of locks
- Prefer structured concurrency (\`async let\`, \`TaskGroup\`) over \`Task { }\`
- Never capture non-Sendable types in \`@Sendable\` closures

### Architecture
- Keep types under 500 lines - split god classes into focused components
- Limit dependencies per type to under 15 - use dependency injection
- Avoid circular dependencies - use protocols to break cycles
- Respect layer boundaries: UI → Domain → Data (never upward)

### Code Quality
- Keep functions under 50 lines - extract helper methods
- Limit nesting depth to 4 levels - use early returns with \`guard\`
- Keep cyclomatic complexity under 10 - simplify conditionals
- Avoid mutable global state - use dependency injection

### Security
- NEVER hardcode secrets, API keys, or credentials
- Use parameterized queries for database operations
- Prefer CryptoKit over deprecated Security framework APIs
- Sanitize user input before use in commands or queries

### Testing
- Add timeouts to async tests: \`await fulfillment(timeout: 5.0)\`
- Avoid flaky patterns: random values, timing dependencies, file system state
- Ensure test isolation - don't share mutable state between tests

### What to Avoid
- \`print()\` in production code - use proper logging
- \`fatalError()\` except for truly unrecoverable states
- Repeated allocations in loops - preallocate collections
- String concatenation in loops - use \`joined()\` or \`StringBuilder\`
- Compiling regex in loops - compile once outside the loop
\`\`\`

## Files Generated by StrictSwift

StrictSwift creates the following files in your project directory:

| File | Purpose | Gitignore? |
|------|---------|------------|
| \`.strictswift-cache/\` | Incremental analysis cache | Yes |
| \`.strictswift-backup/\` | Backup before fix operations | Yes |
| \`.strictswift-last-run.json\` | Violation cache for feedback lookup | Yes |
| \`.strictswift-baseline.json\` | Baseline of known violations | No (commit this) |
| \`.strictswift-learned.json\` | Learning system data | Optional |
| \`.strictswift.yml\` | Configuration file | No (commit this) |

Add to your \`.gitignore\`:
\`\`\`gitignore
.strictswift-cache/
.strictswift-backup/
.strictswift-last-run.json
\`\`\`

## Troubleshooting

### Semantic analysis not working

If you see "Semantic mode unavailable" warnings:

1. Ensure you have Xcode installed with command line tools
2. Try running \`xcode-select --install\`
3. Use \`--verbose\` to see SourceKit debug output
4. Fall back to \`--semantic off\` for syntactic-only analysis

### Cache issues

If you suspect stale cache data:

\`\`\`bash
swift-strict check Sources/ --clear-cache
\`\`\`

### Fix command destroyed my code

1. Run \`swift-strict fix --undo\` to restore from backup
2. If no backup exists, use \`git checkout .\` to restore from git
3. Report the issue on GitHub with the problematic code pattern

## Documentation

See the [Implementation Plan](PHASE_0_IMPLEMENTATION.md) for detailed development phases.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT
