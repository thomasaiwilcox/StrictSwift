# Phase 0: Foundation & Infrastructure - Detailed Implementation Plan

**Duration: 2 Weeks (10 working days)**
**Team: 2-3 Swift Engineers**
**Objective**: Establish core infrastructure to enable rapid development of analysis features

---

## Executive Summary

Phase 0 builds the technical foundation for StrictSwift, including project setup, AST processing infrastructure, configuration management, testing framework, and CI/CD pipeline. This phase enables the team to move quickly in subsequent phases by providing robust, performant building blocks for rule development and analysis.

---

## Week 1: Core Infrastructure Setup

### Day 1-2: Project Structure & Package Configuration

#### Task 1.1: Initialize Swift Package (4 hours)

**Acceptance Criteria:**
- [ ] Swift package compiles successfully on macOS and Linux
- [ ] All dependencies resolve without conflicts
- [ ] Swift 6 strict concurrency mode enabled
- [ ] Executable target runs and shows help

**Implementation Details:**

Create `Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StrictSwift",
    platforms: [.macOS(.v13), .iOS(.v16), .linux(.ubuntu(.v22))],
    products: [
        .executable(name: "swift-strict", targets: ["StrictSwiftCLI"]),
        .library(name: "StrictSwiftCore", targets: ["StrictSwiftCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "50700.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "StrictSwiftCLI",
            dependencies: [
                "StrictSwiftCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "StrictSwiftCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxParser", package: "swift-syntax"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "StrictSwiftTests",
            dependencies: ["StrictSwiftCore"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
```

#### Task 1.2: Directory Structure (2 hours)

**Acceptance Criteria:**
- [ ] All directories created with proper README files
- [ ] Empty Swift files for each module
- [ ] Documentation placeholders created

**Directory Layout:**
```
StrictSwift/
├── Package.swift
├── README.md
├── Sources/
│   ├── StrictSwiftCore/
│   │   ├── StrictSwiftCore.swift
│   │   ├── AST/
│   │   │   ├── SourceFile.swift
│   │   │   ├── SymbolCollector.swift
│   │   │   ├── ImportTracker.swift
│   │   │   └── Location.swift
│   │   ├── Configuration/
│   │   │   ├── Configuration.swift
│   │   │   ├── Profile.swift
│   │   │   ├── RuleConfiguration.swift
│   │   │   └── BaselineConfiguration.swift
│   │   ├── Rules/
│   │   │   ├── Rule.swift
│   │   │   ├── RuleEngine.swift
│   │   │   ├── Violation.swift
│   │   │   └── RuleCategory.swift
│   │   ├── Reporting/
│   │   │   ├── Reporter.swift
│   │   │   ├── HumanReporter.swift
│   │   │   ├── JSONReporter.swift
│   │   │   └── Diagnostic.swift
│   │   └── Utilities/
│   │       ├── Logger.swift
│   │       ├── FileSystem.swift
│   │       └── Extensions.swift
│   └── StrictSwiftCLI/
│       ├── main.swift
│       ├── Commands/
│       │   ├── CheckCommand.swift
│       │   ├── CICommand.swift
│       │   ├── BaselineCommand.swift
│       │   └── ExplainCommand.swift
│       └── Options/
│           ├── GlobalOptions.swift
│           └── OutputOptions.swift
├── Tests/
│   ├── StrictSwiftTests/
│   │   ├── ASTTests/
│   │   ├── ConfigurationTests/
│   │   ├── RulesTests/
│   │   └── ReportingTests/
│   ├── IntegrationTests/
│   │   ├── EndToEndTests.swift
│   │   └── PerformanceTests.swift
│   └── Fixtures/
│       ├── ConcurrentCode/
│       ├── CircularDependencies/
│       ├── MemorySafety/
│       └── Architectural/
│           ├── ExpectedResults/
│           └── Configurations/
├── Documentation/
│   ├── Architecture.md
│   ├── RuleWritingGuide.md
│   └── Examples/
├── .github/
│   └── workflows/
├── .swiftlint.yml
└── .gitignore
```

---

### Day 3-4: SwiftSyntax Integration

#### Task 2.1: AST Parser Infrastructure (8 hours)

**Acceptance Criteria:**
- [ ] Parse any valid Swift file without crashing
- [ ] Extract all declarations with locations
- [ ] Track import statements accurately
- [ ] Handle files up to 10k LOC in <1 second

**Implementation Details:**

Create `Sources/StrictSwiftCore/AST/SourceFile.swift`:
```swift
import SwiftSyntax
import Foundation

@StrictSwiftActor
public final class SourceFile {
    public let url: URL
    public let tree: SourceFileSyntax
    public let symbols: [Symbol]
    public let imports: [Import]

    public init(url: URL) throws {
        self.url = url
        let source = try String(contentsOf: url)
        self.tree = try Parser.parse(source: source)

        var symbolCollector = SymbolCollector()
        symbolCollector.walk(tree)
        self.symbols = symbolCollector.symbols

        var importTracker = ImportTracker()
        importTracker.walk(tree)
        self.imports = importTracker.imports
    }
}

public struct Symbol {
    public let name: String
    public let kind: SymbolKind
    public let location: Location
    public let accessibility: Accessibility
    public let attributes: [Attribute]
}

public enum SymbolKind {
    case class, struct, enum, protocol, function, variable, extension
}

public struct Import {
    public let moduleName: String
    public let kind: ImportKind
    public let location: Location
}
```

#### Task 2.2: Cross-File Analysis Context (6 hours)

**Acceptance Criteria:**
- [ ] Manage analysis of multiple files concurrently
- [ ] Build dependency graph between files
- [ ] Provide thread-safe access to shared state
- [ ] Cache parsed ASTs efficiently

Create `Sources/StrictSwiftCore/AST/AnalysisContext.swift`:
```swift
@StrictSwiftActor
public final class AnalysisContext {
    private var sourceFiles: [URL: SourceFile] = [:]
    private var dependencyGraph: DependencyGraph
    private let configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.dependencyGraph = DependencyGraph()
    }

    public func analyzeFile(at url: URL) throws -> SourceFile {
        if let cached = sourceFiles[url] {
            return cached
        }

        let sourceFile = try SourceFile(url: url)
        sourceFiles[url] = sourceFile

        // Update dependency graph
        for `import` in sourceFile.imports {
            dependencyGraph.addEdge(from: url, to: `import`.moduleName)
        }

        return sourceFile
    }

    public func allSourceFiles() -> [SourceFile] {
        return Array(sourceFiles.values)
    }

    public func dependencyGraph() -> DependencyGraph {
        return dependencyGraph
    }
}
```

---

### Day 5: Configuration System

#### Task 3.1: Configuration Models (8 hours)

**Acceptance Criteria:**
- [ ] Load YAML configuration with validation
- [ ] Apply profile defaults correctly
- [ ] Support per-rule overrides
- [ ] Generate clear error messages

**Implementation Details:**

Create `Sources/StrictSwiftCore/Configuration/Configuration.swift`:
```swift
import Yams
import Foundation

public struct Configuration: Codable, Equatable {
    public let profile: Profile
    public let rules: RulesConfiguration
    public let baseline: BaselineConfiguration?

    public static let `default` = Configuration(profile: .criticalCore)

    public static func load(from url: URL) throws -> Configuration {
        let data = try Data(contentsOf: url)
        let decoder = YAMLDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Configuration.self, from: data)
    }
}

public struct RulesConfiguration: Codable, Equatable {
    public var memory: MemoryRules
    public var concurrency: ConcurrencyRules
    public var architecture: ArchitectureRules
    public var safety: SafetyRules
    public var performance: PerformanceRules

    public static let `default` = RulesConfiguration(...)
}

public enum Profile: String, Codable, CaseIterable {
    case criticalCore = "critical-core"
    case serverDefault = "server-default"
    case libraryStrict = "library-strict"
    case appRelaxed = "app-relaxed"
    case rustEquivalent = "rust-equivalent" // Beta

    public var configuration: Configuration {
        switch self {
        case .criticalCore: return Configuration.loadCriticalCore()
        case .serverDefault: return Configuration.loadServerDefault()
        // ... other profiles
        }
    }
}
```

---

## Week 2: Testing & CI Framework

### Day 6-7: Testing Infrastructure

#### Task 4.1: Test Framework (8 hours)

**Acceptance Criteria:**
- [ ] Unit test suite achieves >80% coverage
- [ ] Snapshot tests detect output changes
- [ ] Performance tests validate timing constraints
- [ ] Test utilities simplify rule testing

**Implementation Details:**

Create `Tests/StrictSwiftTests/TestUtilities/TestCase.swift`:
```swift
import XCTest
import StrictSwiftCore

public struct TestCase {
    public let name: String
    public let source: String
    public let expectedViolations: [ExpectedViolation]
    public let configuration: Configuration

    public init(name: String, source: String, expectedViolations: [ExpectedViolation] = [], configuration: Configuration = .default) {
        self.name = name
        self.source = source
        self.expectedViolations = expectedViolations
        self.configuration = configuration
    }
}

public extension XCTestCase {
    func assertRule(_ rule: Rule, detects testCase: TestCase) async {
        let sourceFile = try! SourceFile(url: testCase.url)
        let context = AnalysisContext(configuration: testCase.configuration)
        let violations = await rule.analyze(sourceFile, in: context)

        XCTAssertEqual(
            violations.map { ($0.ruleId, $0.location.line) },
            testCase.expectedViolations.map { ($0.ruleId, $0.line) },
            "Rule \(rule.id) failed for test case: \(testCase.name)"
        )
    }
}
```

#### Task 4.2: Test Fixtures (6 hours)

**Acceptance Criteria:**
- [ ] Fixtures cover all major patterns
- [ ] Each fixture has configuration and expected results
- [ ] Update mechanism for adding new test cases

**Test Structure:**
```
Tests/Fixtures/ConcurrentCode/
├── NonSendableCapture.swift
├── AsyncGlobalMutation.swift
├── TaskWithoutIsolation.swift
├── configuration.yaml
└── expected.json
```

---

### Day 8-9: Baseline System

#### Task 5.1: Baseline Implementation (8 hours)

**Acceptance Criteria:**
- [ ] Create baseline from existing violations
- [ ] Suppress known violations in output
- [ ] Handle merge conflicts in baselines
- [ ] Support expiry dates for temporary exceptions

Create `Sources/StrictSwiftCore/Configuration/BaselineConfiguration.swift`:
```swift
public struct BaselineConfiguration: Codable {
    public let version: Int
    public let created: Date
    public let expires: Date?
    public let violations: [ViolationFingerprint]

    public static func load(from url: URL) throws -> BaselineConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BaselineConfiguration.self, from: data)
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url)
    }
}

public struct ViolationFingerprint: Codable, Hashable {
    public let ruleId: String
    public let file: String
    public let line: Int
    public let fingerprint: String // SHA-256 of normalized content

    public init(violation: Violation) {
        self.ruleId = violation.ruleId
        self.file = violation.location.file.path
        self.line = violation.location.line
        self.fingerprint = Self.fingerprint(for: violation)
    }
}
```

---

### Day 10: CI/CD Pipeline

#### Task 6.1: GitHub Actions (6 hours)

**Acceptance Criteria:**
- [ ] All tests pass on PR validation
- [ ] Coverage reports generated and viewable
- [ ] Performance regressions detected and reported
- [ ] Documentation auto-generated on release

Create `.github/workflows/test.yml`:
```yaml
name: Test
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    strategy:
      matrix:
        os: [macos-latest, ubuntu-latest]
        swift-version: ['6.0']

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4

      - name: Setup Swift
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: ${{ matrix.swift-version }}

      - name: Build
        run: swift build -v

      - name: Test
        run: swift test --enable-code-coverage

      - name: Generate coverage
        if: matrix.os == 'macos-latest'
        run: |
          xcrun llvm-cov report \
            .build/debug/StrictSwiftCorePackageTests.xctest/Contents/MacOS/StrictSwiftCorePackageTests \
            -instr-profile=.build/debug/codecov/default.profdata \
            -format=html \
            -output-dir coverage/

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: coverage/coverage.json
```

---

## Performance Targets & Benchmarks

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Single file parsing (100 LOC) | <10ms | Time Measurement in tests |
| Configuration loading | <50ms | Unit test with timer |
| Baseline processing (1k violations) | <100ms | Benchmark utility |
| Memory usage (10k LOC) | <50MB | Memory profiling |
| Test coverage | ≥80% | llvm-cov report |
| CI pipeline duration | <5 minutes | GitHub Actions timing |

---

## Risk Mitigation Strategies

1. **SwiftSyntax Compatibility**
   - Pin to specific minor version
   - Create compatibility layer for breaking changes

2. **Performance Regression**
   - Continuous benchmarking in CI
   - Alert on >10% performance degradation

3. **Configuration Complexity**
   - Provide clear validation messages
   - Include configuration examples in documentation

4. **Test Coverage**
   - Enforce coverage gates in CI
   - Require tests for new rules

---

## Daily Stand-up Topics

- **Day 1**: Package setup issues, dependency resolution
- **Day 2**: Directory structure, initial build verification
- **Day 3**: AST parsing challenges, SwiftSyntax API questions
- **Day 4**: Performance optimization, concurrent parsing
- **Day 5**: Configuration format validation, profile defaults
- **Day 6**: Test framework design, fixture organization
- **Day 7**: Coverage goals, test utility functions
- **Day 8**: Baseline format, fingerprinting approach
- **Day 9**: Baseline merging strategy, expiry handling
- **Day 10**: CI configuration, performance baselines

---

## Deliverables Summary

1. **Source Code**
   - Complete package structure with all modules
   - AST parsing and analysis infrastructure
   - Configuration system with profile support
   - Baseline management functionality

2. **Testing**
   - Comprehensive test suite with >80% coverage
   - Test fixtures for various Swift patterns
   - Performance benchmarking utilities

3. **CI/CD**
   - GitHub Actions workflows
   - Automated testing and coverage reporting
   - Performance regression detection

4. **Documentation**
   - Architecture documentation
   - API documentation placeholders
   - Development setup guide

---

## Next Steps

Upon completion of Phase 0, the team will have:
- A solid foundation for rapid rule development
- Performant AST processing pipeline
- Flexible configuration system
- Comprehensive testing infrastructure
- Automated CI/CD pipeline

This enables immediate start of Phase 1: Core Analysis Engine with confidence in the underlying infrastructure quality and performance.