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

### Phase 1: Enhance Symbol Model
**Goal**: Enable symbols to represent a hierarchy and be uniquely identifiable.

1.  **Update `Symbol.swift`**:
    - Add `id`: A unique identifier (USR - Unified Symbol Resolution).
    - Add `parentID`: To track nesting (e.g., method inside a class).
    - Add `accessLevel`: To determine entry points (public/open).
    - Add `usr`: Store the SwiftSyntax USR if available, or generate a stable ID based on module + path + name.

### Phase 2: Deep Symbol Collection
**Goal**: Capture the full structure of the code, not just top-level declarations.

1.  **Update `SymbolCollector.swift`**:
    - Change traversal strategy from `.skipChildren` to `.visitChildren`.
    - Maintain a `scopeStack` to track the current parent symbol during traversal.
    - Capture all relevant declarations:
        - `ClassDecl`, `StructDecl`, `EnumDecl`, `ProtocolDecl`
        - `FunctionDecl`
        - `VariableDecl` (properties)
        - `InitializerDecl`

### Phase 3: Reference Collection
**Goal**: Identify where symbols are *used*.

1.  **Create `ReferenceCollector.swift`**:
    - A new `SyntaxVisitor` dedicated to finding usages.
    - Visit nodes that represent usage:
        - `MemberAccessExpr` (e.g., `obj.prop`)
        - `FunctionCallExpr` (e.g., `func()`)
        - `SimpleTypeIdentifier` (e.g., `let x: MyType`)
    - Record the location and the name of the referenced symbol.
    - *Challenge*: Without a full type checker (like SourceKit), resolving `obj.method()` to the exact `method` definition is hard. We will implement a **Name-Based Resolution** strategy initially (optimistic matching), potentially refining it with type inference later if needed.

### Phase 4: Graph Construction
**Goal**: Link definitions to references.

1.  **Create `GlobalReferenceGraph.swift`**:
    - **Data Structure**: Adjacency list or similar graph structure.
    - **Input**: A collection of `SourceFile`s.
    - **Process**:
        1.  Run `SymbolCollector` on all files to build the **Node Set**.
        2.  Run `ReferenceCollector` on all files to find **Edges**.
        3.  **Resolution**: Match references (names) to symbols (IDs). Handle ambiguity (e.g., two classes having `start()` method) by checking imports and scopes.

### Phase 5: Reachability Analysis
**Goal**: Determine which symbols are never reached.

1.  **Create `DeadCodeAnalyzer.swift`**:
    - **Identify Entry Points**:
        - Symbols marked `public` or `open` (library mode).
        - Symbols annotated with `@main` or `@UIApplicationMain`.
        - Top-level code in `main.swift`.
        - Test targets (XCTest classes).
    - **Traversal**:
        - Perform BFS/DFS starting from Entry Points.
        - Mark visited nodes as "Live".
    - **Reporting**:
        - Any node not marked "Live" is "Dead Code".
        - Filter out protocol requirements (if a type implements a protocol, its methods are "live" if the type is live).

### Phase 6: Integration & Reporting
**Goal**: Expose the feature to the user.

1.  **New Rule**: `DeadCodeRule.swift`.
    - Wraps the `DeadCodeAnalyzer`.
    - Reports violations via the standard `Reporter` interface.
2.  **CLI Integration**:
    - Ensure the analysis runs across all files before reporting.

## Risk Mitigation
- **False Positives**: The lack of full type checking means we might flag code as dead if we fail to resolve a reference.
    - *Mitigation*: Err on the side of caution. If a reference matches multiple symbols (e.g., `start()`), mark *all* of them as potentially live.
- **Reflection/Runtime**: Swift uses runtime features (CodingKeys, @objc) that static analysis misses.
    - *Mitigation*: Allowlist specific attributes (`@IBAction`, `@IBOutlet`, `@objc`) and protocols (`Codable`).

## Next Steps
1.  Begin Phase 1: Modify `Symbol.swift`.
