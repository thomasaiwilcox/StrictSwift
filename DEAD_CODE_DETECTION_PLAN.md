# Dead Code Detection Implementation Plan

## Overview
This document outlines the implementation plan for adding **Dead Code Detection** to StrictSwift. The goal is to identify unused functions, types, and properties across the entire codebase by building a **Global Reference Graph**.

## Current Limitations
- **Shallow Collection**: `SymbolCollector` currently skips child nodes (`.skipChildren`), missing nested types and methods.
- **Flat Model**: `Symbol` lacks hierarchical relationships (parent/child) and unique identifiers (USRs).
- **Regex Dependencies**: `DependencyAnalyzer` relies on fragile string parsing instead of robust AST traversal.

## Architecture: Global Reference Graph
We will move from a file-by-file analysis to a whole-module analysis using a graph structure where:
- **Nodes**: Definitions (Classes, Structs, Functions, Properties).
- **Edges**: References (Function calls, Type usage, Property access).

## Implementation Phases

### Phase 1: Enhance Symbol Model ✅ COMPLETE
**Goal**: Enable symbols to represent a hierarchy and be uniquely identifiable.

**Completed Changes to `Symbol.swift`**:
- ✅ Added `SymbolID` struct with `moduleName`, `qualifiedName`, `kind`, `locationHash`
- ✅ Added `parentID` to `Symbol` for tracking nesting (e.g., method inside a class)
- ✅ Added `accessibility` property for determining entry points (public/open)
- ✅ Added `attributes` array for tracking decorators (@available, @MainActor, etc.)

### Phase 2: Deep Symbol Collection ✅ COMPLETE
**Goal**: Capture the full structure of the code, not just top-level declarations.

**Completed Changes to `SymbolCollector.swift`**:
- ✅ Implemented `scopeStack` to track current parent symbol during traversal
- ✅ Changed traversal to visit children for type declarations (classes, structs, enums, protocols, actors, extensions)
- ✅ Captures all relevant declarations with proper parent-child relationships:
    - `ClassDecl`, `StructDecl`, `EnumDecl`, `ProtocolDecl`
    - `ActorDecl` (Swift concurrency support)
    - `FunctionDecl`
    - `VariableDecl` (all bindings in multi-variable declarations like `let x = 1, y = 2`)
    - `InitializerDecl`, `DeinitializerDecl`
    - `SubscriptDecl`, `TypeAliasDeclSyntax`, `AssociatedTypeDeclSyntax`
    - `EnumCaseDeclSyntax` (all case elements)
    - `OperatorDecl`, `PrecedenceGroupDecl` (custom operators)
    - `MacroDecl` (Swift macros)

**Completed Changes to `Symbol.swift`**:
- ✅ Added `SymbolKind.actor` for actor declarations
- ✅ Added `SymbolKind.operator` for custom operators
- ✅ Added `SymbolKind.precedenceGroup` for precedence group declarations
- ✅ Added `SymbolKind.macro` for macro declarations

**Tests Added**: `SymbolCollectorPhase2Tests.swift` with 20 comprehensive test cases covering:
- Actor declarations with members and nested types
- Operator declarations (infix, prefix, postfix)
- Precedence group declarations
- Macro declarations
- Multiple variable bindings
- Integration scenarios

### Phase 3: Reference Collection ✅ COMPLETE
**Goal**: Identify where symbols are *used*.

**Completed Changes to `Symbol.swift`**:
- ✅ Added `ReferenceKind` enum with cases: `functionCall`, `propertyAccess`, `typeReference`, `inheritance`, `conformance`, `identifier`, `extensionTarget`, `enumCase`, `initializer`, `genericArgument`
- ✅ Added `SymbolReference` struct with: `referencedName`, `fullExpression`, `kind`, `location`, `scopeContext`, `inferredBaseType`

**Created `ReferenceCollector.swift`**:
- ✅ `SyntaxAnyVisitor` subclass with scope tracking (push/pop for type declarations)
- ✅ Built-in type exclusion (Int, String, Bool, etc. are not recorded as references)
- ✅ Expression visitors:
    - `FunctionCallExprSyntax` → detects function calls and initializer calls (`Type()`)
    - `MemberAccessExprSyntax` → detects property access, enum cases, method calls
    - `DeclReferenceExprSyntax` → detects bare identifier references (excludes `self`, `super`)
- ✅ Type reference visitors:
    - `IdentifierTypeSyntax` → type annotations with generic argument extraction
    - `InheritanceClauseSyntax` → superclass and protocol conformances
    - `ExtensionDeclSyntax` → extension target types
    - `MemberTypeSyntax` → qualified type names (e.g., `Module.Type`)
    - `TypeExprSyntax` → type expressions (e.g., `MyType.self`)
- ✅ Scope context tracking for reference resolution

**Tests Added**: `ReferenceCollectorTests.swift` with 32 comprehensive test cases covering:
- Function calls (simple, method, chained, static)
- Initializer calls
- Property and enum case access
- Identifier references (with self/super exclusion)
- Type references (annotations, parameters, return types, optionals, generics)
- Inheritance and protocol conformance
- Extension targets
- Scope context verification
- Built-in type exclusion

### Phase 4: Graph Construction ✅ COMPLETED
**Goal**: Link definitions to references.

**Implementation**: `GlobalReferenceGraph.swift` (643 lines)

**Data Structures**:
- **Symbol Indexes**:
  - `symbolsByID: [SymbolID: Symbol]` - O(1) lookup by ID
  - `symbolsByName: [String: [SymbolID]]` - Name-based resolution
  - `symbolsByQualifiedName: [String: [SymbolID]]` - Precise lookups
  - `symbolsByFile: [URL: Set<SymbolID>]` - File-based incremental updates

- **Reference Edges**:
  - `referencedBy: [SymbolID: Set<SymbolID>]` - Incoming edges
  - `references: [SymbolID: Set<SymbolID>]` - Outgoing edges
  - `referencesByFile: [URL: [SymbolReference]]` - For incremental updates

- **Protocol Conformance**:
  - `protocolImplementations: [SymbolID: Set<SymbolID>]` - Protocol method → implementing methods
  - `implementsProtocol: [SymbolID: Set<SymbolID>]` - Type → protocols

- **Associated Types**:
  - `associatedTypeBindings: [SymbolID: [String: SymbolID]]` - Type → [assoc name → concrete type]

- **Conditional Conformance**:
  - `conditionalConformances: [SymbolID: [ConditionalConformance]]`
  - `WhereRequirement` enum: `.conformance(typeParam:protocolName:)`, `.sameType(typeParam:concreteType:)`

**Methods**:
- Symbol Registration: `registerSymbol()`, `symbol(for:)`, `symbols(named:)`, `symbols(qualifiedName:)`, `symbolsInScope()`, `symbols(inFile:)`
- Edge Management: `addEdge()`, `getReferencedBy()`, `getReferences()`
- Protocol Handling: `addProtocolConformance()`, `addProtocolImplementation()`, `getConformedProtocols()`, `getImplementingMethods()`, `getProtocolRequirements()`
- Associated Types: `addAssociatedTypeBinding()`, `getAssociatedTypeBinding()`
- Conditional Conformance: `addConditionalConformance()`, `getConditionalConformances()`
- Reference Resolution: `resolveReference()` with kind compatibility, scope matching, import filtering
- Graph Construction: `build(from:)` with 5-pass algorithm
- Incremental Updates: `addFile()`, `removeFile()`, `updateFile()`, `clear()`

**Resolution Algorithm**:
1. Get all symbols with matching name
2. Filter by kind compatibility (e.g., `.functionCall` → `.function`)
3. Prioritize by inferred base type (member access)
4. Use scope context for same-scope matching
5. Filter by imports for external modules
6. Return all remaining candidates (conservative approach)

**Tests**: 25 tests in `GlobalReferenceGraphTests.swift`

### Phase 5: Reachability Analysis ✅ COMPLETED
**Goal**: Determine which symbols are never reached.

**Implementation**: `DeadCodeAnalyzer.swift` (478 lines), `DeadCodeRule.swift` (114 lines)

**Configuration Model**:
- `DeadCodeMode` enum: `.library` (public = entry points) vs `.executable` (@main/main.swift = entry points)
- `DeadCodeConfiguration` struct with:
  - `mode`: library vs executable
  - `treatPublicAsEntryPoint`, `treatOpenAsEntryPoint`: accessibility-based entry points
  - `entryPointAttributes`: [@main, @UIApplicationMain, @NSApplicationMain, @objc, @IBAction, @IBOutlet]
  - `entryPointFilePatterns`: ["**/main.swift"] for executable mode
  - `ignoredPatterns`, `ignoredPrefixes`: skip specific symbols (e.g., `_privateHelper`)
  - `synthesizedMemberProtocols`: [Codable, Encodable, Decodable, Equatable, Hashable, CustomStringConvertible]
- `DeadCodeConfiguration.libraryDefault` and `.executableDefault` presets

**Entry Point Detection**:
- Accessibility-based: public/open symbols in library mode
- Attribute-based: @main, @UIApplicationMain, @objc, @IBAction, @IBOutlet
- File pattern-based: main.swift in executable mode
- XCTest integration: test classes and test methods

**BFS Reachability Algorithm**:
1. Identify entry points and ignored symbols
2. BFS from entry points using `graph.getReferences()` for outgoing edges
3. Mark children live when parent is live (initializers, deinitializers)
4. Mark protocol implementations live via `graph.getImplementingMethods()`
5. Mark synthesized members live for Codable/Equatable/Hashable

**Protocol-Aware Handling**:
- Protocol requirements are ignored (not flagged as dead if protocol is live)
- Protocol implementations marked live when type is live
- Synthesized members (CodingKeys, encode/init for Codable, == for Equatable, hash for Hashable, description for CustomStringConvertible)

**DeadCodeRule Integration**:
- Rule ID: `dead-code`
- Category: `.architecture`
- Cross-file analysis: added to `crossFileRuleIdentifiers` for baseline support
- Builds GlobalReferenceGraph from all source files
- Reports violations with file/line location

**Result Model**:
- `DeadCodeResult` with `entryPoints`, `liveSymbols`, `deadSymbols`, `ignoredSymbols`
- Statistics: totalSymbols, entryPointCount, liveCount, deadCount, ignoredCount, analysisTimeMs

**Tests**: 20 tests in `DeadCodeAnalyzerTests.swift` covering:
- Entry point detection (public symbols, @main, @objc, @IBAction, main.swift, test methods)
- Reachability (function calls, type references, property chains, cross-file)
- Protocol handling (conformance marking, implementations)
- Codable synthesis (CodingKeys, encode/init)
- Configuration (library vs executable mode, ignored patterns/prefixes)
- Edge cases (empty files, no entry points, extensions, deinitializers)

### Phase 6: Integration & Reporting ✅ COMPLETED
**Goal**: Expose the feature to the user with full YAML configuration, confidence levels, and documentation.

**Implementation**:

1. **Rule Registration** ✅
   - `DeadCodeRule` registered in `RuleEngine.swift` under "Phase 5 Dead Code Detection"
   - Rule ID: `dead-code`, Category: `.architecture`, Default Severity: `.warning`

2. **Confidence Levels** ✅
   - Added `DeadCodeConfidence` enum with `.high`, `.medium`, `.low` cases
   - High = private/fileprivate (definitely dead), Medium = internal/package, Low = public/open
   - Confidence affects severity: high → error, medium → warning, low → hint
   - `deadSymbolsWithConfidence` property returns symbols with calculated confidence

3. **YAML Configuration Support** ✅
   - `buildConfiguration(from:context:)` reads rule parameters from config
   - Supported parameters:
     - `mode`: 'library', 'executable', 'hybrid', 'auto'
     - `treatPublicAsEntryPoint`: boolean
     - `ignoredPrefixes`: array of strings
     - `entryPointAttributes`: array of strings
     - `minimumConfidence`: 'high', 'medium', 'low'

4. **Auto Mode Detection** ✅
   - `detectProjectMode(allFiles:projectRoot:)` analyzes project structure
   - Checks Package.swift for library/executable targets
   - Detects @main attributes and main.swift files
   - Returns `.library`, `.executable`, or `.hybrid` based on findings

5. **Structured Fixes** ✅
   - `createStructuredFix(for:confidence:)` creates removal fixes
   - Uses `StructuredFix` with `TextEdit` for precise code removal
   - Fix kind: `.removeCode` with appropriate confidence level

6. **ExplainCommand Documentation** ✅
   - Comprehensive documentation for `dead-code` rule
   - Includes: description, how it works, configuration examples, confidence levels, examples, auto-fixes

7. **Integration Tests** ✅
   - `DeadCodeRuleTests.swift` with 6 tests covering:
     - Unused private function detection
     - Structured fix generation
     - Rule metadata verification
     - File type filtering
     - Location information in violations

**CLI Usage**:
```bash
# Run dead code analysis
swift-strict check --profile critical-core

# Explain the dead-code rule
swift-strict explain dead-code
```

**Configuration Example** (`.strictswift.yml`):
```yaml
rules:
  dead-code:
    enabled: true
    severity: warning
    parameters:
      mode: auto
      treatPublicAsEntryPoint: true
      ignoredPrefixes: ["_"]
      entryPointAttributes: ["@IBAction", "@objc"]
      minimumConfidence: medium
```

## Summary

All 6 phases of dead code detection are now complete:

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Enhanced Symbol Model | ✅ Complete |
| 2 | Deep Symbol Collection | ✅ Complete |
| 3 | Reference Collection | ✅ Complete |
| 4 | Global Reference Graph | ✅ Complete |
| 5 | Reachability Analysis | ✅ Complete |
| 6 | Integration & Reporting | ✅ Complete |

**Total Tests**: 461 tests (all passing)
- 20 DeadCodeAnalyzer tests
- 6 DeadCodeRule tests  
- 25 GlobalReferenceGraph tests
- 32 ReferenceCollector tests

## Risk Mitigation
- **False Positives**: The lack of full type checking means we might flag code as dead if we fail to resolve a reference.
    - *Mitigation*: Err on the side of caution. If a reference matches multiple symbols (e.g., `start()`), mark *all* of them as potentially live.
- **Reflection/Runtime**: Swift uses runtime features (CodingKeys, @objc) that static analysis misses.
    - *Mitigation*: Allowlist specific attributes (`@IBAction`, `@IBOutlet`, `@objc`) and protocols (`Codable`).
