# Contributing to StrictSwift

Thank you for your interest in contributing to StrictSwift! This document provides guidelines and information for contributors.

## Development Setup

### Prerequisites

- Swift 6.0 or later
- Xcode 15.0+ (on macOS) or Swift 6.0+ toolchain
- Git

### Getting Started

1. Fork the repository
2. Clone your fork locally
   ```bash
   git clone https://github.com/your-username/StrictSwift.git
   cd StrictSwift
   ```

3. Create a feature branch
   ```bash
   git checkout -b feature/your-feature-name
   ```

4. Build the project
   ```bash
   swift build
   ```

5. Run tests to ensure everything works
   ```bash
   swift test
   ```

## Project Structure

```
StrictSwift/
├── Sources/
│   ├── StrictSwiftCLI/          # Command-line interface
│   └── StrictSwiftCore/        # Core analysis engine
│       ├── AST/                 # SwiftSyntax abstractions
│       ├── Configuration/        # Configuration management
│       ├── Reporting/          # Output formatting
│       └── Rules/               # Analysis rules
├── Tests/
│   ├── Fixtures/               # Test files for analysis
│   └── StrictSwiftTests/       # Test suite
└── .github/                    # GitHub workflows and templates
```

## Adding New Rules

1. Create a new rule class in `Sources/StrictSwiftCore/Rules/`
2. Implement the `Rule` protocol
3. Add the rule to `RuleEngine.swift`
4. Write comprehensive tests in `Tests/StrictSwiftTests/IntegrationTests/`
5. Update documentation

### Rule Template

```swift
import Foundation
import SwiftSyntax

/// Description of what this rule detects
public final class YourRule: Rule {
    public var id: String { "your_rule_id" }
    public var name: String { "Your Rule Name" }
    public var description: String { "Detailed description" }
    public var category: RuleCategory { .safety }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = YourRuleVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

private final class YourRuleVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        // Your rule logic here
        return .visitChildren
    }
}
```

## Running Tests

### Run All Tests
```bash
swift test
```

### Run Specific Test Suite
```bash
swift test --filter YourRuleTests
```

### Run Tests with Verbose Output
```bash
swift test --verbose
```

## Code Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Add documentation comments for public APIs
- Keep lines under 120 characters
- Use trailing closures where appropriate

## Submitting Changes

1. Ensure all tests pass
2. Follow the commit message format (see below)
3. Create a pull request with a clear description
4. Link any relevant issues

## Commit Message Format

```
type(scope): description

[optional body]

Closes #issue
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Code style
- `refactor`: Code refactoring
- `test`: Tests
- `chore`: Build process or auxiliary tool changes

Examples:
- `feat(rules): add rule for detecting force unwraps`
- `fix(cli): resolve crash when analyzing empty files`
- `docs(readme): update installation instructions`

## Release Process

Releases are handled automatically through GitHub Actions when a tag is pushed:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Getting Help

- Check existing [Issues](https://github.com/thomasaiwilcox/StrictSwift/issues)
- Read the [Documentation](https://github.com/thomasaiwilcox/StrictSwift)
- Join discussions in [Discussions](https://github.com/thomasaiwilcox/StrictSwift/discussions)

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.