# Change Log

All notable changes to the StrictSwift extension will be documented in this file.

## [0.12.1] - 2025-11-25

### Performance Improvements
- **Parallel rule execution**: Rules now run in parallel within each file analysis
- **Parallel file analysis**: Multiple files analyzed concurrently with bounded concurrency
- **Cached RuleEngine**: Rule initialization only happens once per session, not per analysis
- **Faster startup**: Reduced initial analysis time significantly (1200%+ CPU utilization)

## [0.11.0] - 2025-11-XX

### Added
- Initial release of StrictSwift VS Code extension
- Real-time diagnostics for Swift code analysis
- Quick fixes for common issues:
  - Force unwrap (`!`) → optional chaining or nil coalescing
  - Force try (`try!`) → proper error handling
  - Print statements → proper logging
- Hover information showing rule details, severity, and category
- Full LSP integration with the StrictSwift analyzer
- Support for all 15+ StrictSwift rules across categories:
  - Safety rules (force unwrap, force try, implicit optionals)
  - Concurrency rules (actor isolation, sendable)
  - Memory rules (ARC churn, retain cycles)
  - Architectural rules (god types, layer violations)

### Technical Details
- Language Server Protocol (LSP) support
- JSON-RPC 2.0 communication
- Incremental analysis on file changes

## [Unreleased]

### Planned
- Diagnostic severity configuration
- Baseline file support for legacy code
- Additional autofix rules
- Performance optimizations for large projects
