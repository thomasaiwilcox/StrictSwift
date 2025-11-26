# StrictSwift

A strict, production-grade static analysis tool for Swift 6+ codebases that enforces an opt-in subset of Swift aligned with Rust-grade safety guarantees.

## Purpose

StrictSwift provides a purpose-built enforcement layer that catches concurrency, architecture, semantic, and memory risks before code reaches production. It enables "Critical Swift Mode" for modules where failure is unacceptable.

## Vision

StrictSwift bridges Swift's expressiveness with Rust's safety culture, bringing the borrow checker and Clippy experience to Swift modules without abandoning the ecosystem.

## Features

- **43+ Rules** across safety, concurrency, memory, architecture, complexity, and performance categories
- **Incremental Caching** - 13x faster on repeat runs
- **Cross-file Analysis** - Global symbol graph for dead code detection and coupling metrics
- **Graph-Enhanced Rules** - Opt-in advanced analysis with afferent/efferent coupling metrics
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
| **Safety** | 8 | Force unwraps, force tries, fatal errors, print statements |
| **Concurrency** | 6 | Data races, actor isolation, non-Sendable captures |
| **Memory** | 4 | Retain cycles, escaping references, exclusive access |
| **Architecture** | 10 | God classes, circular dependencies, coupling metrics |
| **Complexity** | 5 | Function length, nesting depth, cyclomatic complexity |
| **Performance** | 6 | ARC churn, large struct copies, hot path validation |
| **Security** | 4 | Hardcoded secrets, SQL injection, insecure crypto |

### Graph-Enhanced Rules (opt-in)

Enable with `useEnhancedRules: true` for cross-file analysis:

- **god_class_enhanced** - Detects god classes using afferent/efferent coupling metrics
- **coupling_metrics** - Reports instability metrics and coupling violations
- **circular_dependency_graph** - DFS-based cycle detection in type graph
- **non_sendable_capture_graph** - Sendable conformance checking via symbol graph
- **dead_code** - Detects unused functions, types, and variables across files

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
# Run tests (478 tests)
swift test

# Run with coverage
swift test --enable-code-coverage

# Dogfood on itself
.build/debug/swift-strict check Sources/
```

## Documentation

See the [Implementation Plan](PHASE_0_IMPLEMENTATION.md) for detailed development phases.

## License

MIT