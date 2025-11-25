# StrictSwift for VS Code

**StrictSwift** is a powerful static analysis tool for Swift that enforces memory safety, concurrency correctness, and architectural best practices. This VS Code extension provides real-time diagnostics and quick fixes as you code.

## Features

### 🔴 Real-time Diagnostics
Get instant feedback on potential issues in your Swift code:
- **Memory Safety**: Force unwraps, force tries, retain cycles
- **Concurrency**: Data races, non-Sendable captures, actor isolation
- **Architecture**: Circular dependencies, god classes, layer violations
- **Code Quality**: Function length, nesting depth, complexity

### 💡 Quick Fixes
One-click fixes for common issues:
- Convert force unwrap `x!` to optional binding `if let`
- Replace `try!` with proper error handling
- Remove debug print statements
- And more...

### 📊 Rich Hover Information
Hover over any diagnostic to see:
- Rule explanation
- Severity and category
- Available fixes
- Related context

## Requirements

- **VS Code** 1.85.0 or later
- **Swift** 5.9 or later (for the LSP server)
- **StrictSwift LSP Server** - See installation instructions below

## Installation

### From VS Code Marketplace
1. Open VS Code
2. Go to Extensions (⇧⌘X)
3. Search for "StrictSwift"
4. Click Install

### Install the LSP Server

The extension requires the StrictSwift LSP server to be installed:

```bash
# Clone the repository
git clone https://github.com/thomasaiwilcox/StrictSwift.git
cd StrictSwift

# Build the LSP server
swift build -c release --product strictswift-lsp

# Copy to a location in your PATH (optional)
cp .build/release/strictswift-lsp /usr/local/bin/
```

### Configure the Extension

If the LSP server is not in your PATH, configure its location:

1. Open Settings (⌘,)
2. Search for "StrictSwift"
3. Set `strictswift.serverPath` to the full path of the `strictswift-lsp` executable

## Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| `strictswift.enable` | Enable/disable StrictSwift | `true` |
| `strictswift.serverPath` | Path to LSP server executable | `""` (searches PATH) |
| `strictswift.configPath` | Path to `.strictswift.yml` | `""` (auto-detect) |
| `strictswift.profile` | Analysis profile (criticalCore, serverDefault, appRelaxed, libraryStrict, rustInspired) | `"criticalCore"` |
| `strictswift.trace.server` | LSP trace level | `"off"` |

## Commands

- **StrictSwift: Restart Language Server** - Restart the LSP server
- **StrictSwift: Analyze Current File** - Run analysis on the current file
- **StrictSwift: Analyze Workspace** - Run analysis on all Swift files
- **StrictSwift: Fix All Auto-Fixable Issues** - Apply all available fixes

## Rules

StrictSwift includes 25+ rules across multiple categories:

### Safety
- `force_unwrap` - Avoid force unwrapping optionals
- `force_try` - Avoid force try expressions
- `fatal_error` - Avoid fatal error in production
- `print_in_production` - Remove debug print statements

### Concurrency
- `actor_isolation` - Proper actor isolation
- `data_race` - Potential data race detection
- `non_sendable_capture` - Non-Sendable types in concurrent contexts

### Architecture
- `circular_dependency` - Detect circular module dependencies
- `god_class` - Detect overly large classes
- `layered_dependencies` - Enforce architectural layers

### Memory
- `retain_cycle` - Detect potential retain cycles
- `escaping_reference` - Unsafe escaping references

## Contributing

Contributions are welcome! Please see our [Contributing Guide](https://github.com/thomasaiwilcox/StrictSwift/blob/main/CONTRIBUTING.md).

## License

MIT License - see [LICENSE](https://github.com/thomasaiwilcox/StrictSwift/blob/main/LICENSE)

## Links

- [GitHub Repository](https://github.com/thomasaiwilcox/StrictSwift)
- [Issue Tracker](https://github.com/thomasaiwilcox/StrictSwift/issues)
- [Changelog](https://github.com/thomasaiwilcox/StrictSwift/blob/main/Editors/vscode/CHANGELOG.md)
