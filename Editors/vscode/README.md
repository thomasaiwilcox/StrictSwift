# StrictSwift VS Code Extension

Static analysis for Swift code with real-time diagnostics and auto-fix support.

## Features

- **Real-time Diagnostics**: Get warnings and errors as you type
- **Quick Fixes**: Apply auto-fixes for common issues with one click
- **Code Actions**: Right-click to see available fixes for violations
- **Workspace Analysis**: Analyze your entire Swift project

## Requirements

- Visual Studio Code 1.85.0 or later
- StrictSwift language server (`strictswift-lsp`)

## Installation

### From VS Code Marketplace

1. Open VS Code
2. Go to Extensions (Cmd+Shift+X)
3. Search for "StrictSwift"
4. Click Install

### Building from Source

```bash
cd Editors/vscode
npm install
npm run compile
```

Then load the extension in VS Code by pressing F5 (Run Extension Development Host).

## Installing the Language Server

Build the language server from the StrictSwift repository:

```bash
swift build -c release
# Binary is at .build/release/strictswift-lsp
```

Or install globally:

```bash
cp .build/release/strictswift-lsp /usr/local/bin/
```

## Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| `strictswift.enable` | Enable/disable StrictSwift | `true` |
| `strictswift.serverPath` | Path to `strictswift-lsp` executable | (auto-detect) |
| `strictswift.configPath` | Path to configuration file | `.strictswift.yml` |
| `strictswift.profile` | Analysis profile | `default` |
| `strictswift.trace.server` | Trace level for debugging | `off` |

## Commands

- **StrictSwift: Restart Language Server** - Restart the language server
- **StrictSwift: Analyze Current File** - Trigger analysis of the current file
- **StrictSwift: Analyze Workspace** - Analyze all Swift files in the workspace
- **StrictSwift: Fix All Auto-Fixable Issues** - Apply all available fixes

## Supported Rules

StrictSwift includes rules for:

- **Safety**: Force unwrap, force try, fatalError detection
- **Concurrency**: Data race, actor isolation, Sendable violations
- **Complexity**: Cyclomatic complexity, function length, nesting depth
- **Performance**: Large struct copies, repeated allocations
- **Architecture**: Layered dependencies, circular dependencies, god class detection

## Development

```bash
# Install dependencies
npm install

# Compile TypeScript
npm run compile

# Watch for changes
npm run watch

# Run tests
npm test
```

## License

MIT License - see the LICENSE file in the root repository.
