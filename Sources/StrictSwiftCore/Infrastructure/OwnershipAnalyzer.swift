import Foundation
import SwiftSyntax
import SwiftParser

/// Performs static analysis of ownership patterns and memory safety
public final class OwnershipAnalyzer: Sendable {
    /// Analysis context for tracking state during traversal
    private struct OwnershipAnalysisContext {
        var scopeStack: [String] = []
        var functionIdStack: [String] = []
        var nodeCounter: Int = 0
        var currentFile: URL
        var graph: OwnershipGraph

        init(file: URL, graph: OwnershipGraph) {
            self.currentFile = file
            self.graph = graph
        }

        mutating func pushScope(component: String) {
            scopeStack.append(component)
        }

        mutating func popScope() {
            _ = scopeStack.popLast()
        }

        mutating func nextComponent(kind: String, name: String?) -> String {
            if let name, !name.isEmpty {
                return "\(kind).\(name)"
            }
            nodeCounter += 1
            return "\(kind)#\(nodeCounter)"
        }

        func qualifiedName(for component: String) -> String {
            let fileComponent = currentFile.deletingPathExtension().lastPathComponent
            let components = [fileComponent] + scopeStack + [component]
            return components.filter { !$0.isEmpty }.joined(separator: ".")
        }

        mutating func createNode(component: String, typeDescription: String, location: Location, isReferenceType: Bool, isEscaping: Bool = false, lifetime: OwnershipGraph.Lifetime? = nil) -> OwnershipGraph.Node {
            let id = qualifiedName(for: component)
            // Determine lifetime based on type characteristics
            let resolvedLifetime: OwnershipGraph.Lifetime
            if let explicitLifetime = lifetime {
                resolvedLifetime = explicitLifetime
            } else if isEscaping {
                resolvedLifetime = .escaping
            } else if isReferenceType {
                resolvedLifetime = .automatic
            } else {
                // Value types have stack-based lifetime (manual in our model)
                resolvedLifetime = .manual
            }
            return OwnershipGraph.Node(
                id: id,
                type: typeDescription,
                location: location,
                isReferenceType: isReferenceType,
                isEscaping: isEscaping,
                lifetime: resolvedLifetime
            )
        }

        var currentFunctionId: String? {
            functionIdStack.last
        }

        mutating func addNodeToCollection(_ node: OwnershipGraph.Node) {
            // This will be collected by the visitor
        }

        mutating func addReferenceToCollection(_ reference: OwnershipGraph.Reference) {
            // This will be collected by the visitor
        }
    }

    private let graph: OwnershipGraph

    public init(graph: OwnershipGraph? = nil) {
        self.graph = graph ?? OwnershipGraph()
    }

    /// Analyze source files for ownership patterns
    public func analyze(files: [SourceFile]) async -> OwnershipAnalysisResult {
        // Create a new graph instance for this analysis to ensure thread safety
        let analysisGraph = OwnershipGraph()

        var allNodes: [OwnershipGraph.Node] = []
        var allReferences: [OwnershipGraph.Reference] = []

        for file in files {
            let source = file.source()
            let tree = Parser.parse(source: source)

            var context = OwnershipAnalysisContext(file: file.url, graph: analysisGraph)
            let analyzer = OwnershipAnalyzerVisitor(context: &context, tree: tree)
            analyzer.walk(tree)

            // Collect nodes and references from this file
            allNodes.append(contentsOf: analyzer.collectedNodes)
            allReferences.append(contentsOf: analyzer.collectedReferences)
        }

        // Batch add all nodes and references to the analysis graph
        for node in allNodes {
            await analysisGraph.addNodeSync(node)
        }
        for reference in allReferences {
            await analysisGraph.addReferenceSync(reference)
        }

        let issues = await findMemorySafetyIssues(graph: analysisGraph)
        return OwnershipAnalysisResult(
            graph: analysisGraph,
            statistics: await analysisGraph.statistics,
            issues: issues
        )
    }

    /// Analyze a single source file
    public func analyze(_ file: SourceFile) async -> OwnershipAnalysisResult {
        return await analyze(files: [file])
    }

    /// Get the ownership graph
    public var ownershipGraph: OwnershipGraph {
        return graph
    }

    /// Find potential memory safety issues
    public func findMemorySafetyIssues(graph: OwnershipGraph? = nil) async -> [MemorySafetyIssue] {
        var issues: [MemorySafetyIssue] = []
        let targetGraph = graph ?? self.graph

        // Find use-after-free scenarios
        for (node, reference) in await targetGraph.findUseAfterFree() {
            issues.append(MemorySafetyIssue(
                type: .useAfterFree,
                location: reference.location,
                message: "Potential use-after-free: weak/unowned reference to '\(node.type)' at \(reference.location.line):\(reference.location.column)",
                severity: .error,
                nodeId: node.id,
                referenceId: "\(reference.from)->\(reference.to)"
            ))
        }

        // Find memory leaks
        for leakedNode in await targetGraph.findMemoryLeaks() {
            issues.append(MemorySafetyIssue(
                type: .memoryLeak,
                location: leakedNode.location,
                message: "Potential memory leak: reference type '\(leakedNode.type)' with no outgoing references",
                severity: .warning,
                nodeId: leakedNode.id,
                referenceId: nil
            ))
        }

        // Find retain cycles
        for cycle in await targetGraph.findRetainCycles() {
            if let firstRef = cycle.first {
                issues.append(MemorySafetyIssue(
                    type: .retainCycle,
                    location: firstRef.location,
                    message: "Potential retain cycle detected: \(cycle.map { "\($0.from) -> \($0.to)" }.joined(separator: " -> "))",
                    severity: .error,
                    nodeId: firstRef.from,
                    referenceId: cycle.map { "\($0.from)->\($0.to)" }.joined(separator: ", ")
                ))
            }
        }

        // Find escaping references
        for escapingRef in await targetGraph.findEscapingReferences() {
            issues.append(MemorySafetyIssue(
                type: .escapingReference,
                location: escapingRef.location,
                message: "Escaping reference: '\(escapingRef.from)' escaping scope at \(escapingRef.location.line):\(escapingRef.location.column)",
                severity: .warning,
                nodeId: escapingRef.from,
                referenceId: "\(escapingRef.from)->\(escapingRef.to)"
            ))
        }

        // Find exclusive access violations
        for (access1, access2) in await targetGraph.findExclusiveAccessViolations() {
            issues.append(MemorySafetyIssue(
                type: .exclusiveAccessViolation,
                location: access1.location,
                message: "Potential exclusive access violation: multiple mutable accesses to '\(access1.to)'",
                severity: .error,
                nodeId: access1.to,
                referenceId: "\(access1.from)->\(access1.to), \(access2.from)->\(access2.to)"
            ))
        }

        return issues.sorted { $0.location.line < $1.location.line }
    }

    /// Visitor for analyzing ownership patterns in Swift syntax
private class OwnershipAnalyzerVisitor: SyntaxAnyVisitor {
    private var context: OwnershipAnalysisContext
    private let converter: SourceLocationConverter

    // Collections for batch processing
    var collectedNodes: [OwnershipGraph.Node] = []
    var collectedReferences: [OwnershipGraph.Reference] = []

    init(context: inout OwnershipAnalysisContext, tree: SourceFileSyntax) {
        self.context = context
        self.converter = SourceLocationConverter(fileName: context.currentFile.path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    // Helper method to create proper Location with real line/column
    private func createLocation(from position: AbsolutePosition) -> Location {
        let loc = converter.location(for: position)
        return Location(
            file: context.currentFile,
            line: loc.line,
            column: loc.column
        )
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = createLocation(from: node.position)
        let component = context.nextComponent(kind: "class", name: node.name.text)
        let classNode = context.createNode(component: component, typeDescription: "Class.\(node.name.text)", location: location, isReferenceType: true)
        collectedNodes.append(classNode)
        context.pushScope(component: component)

        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        context.popScope()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = createLocation(from: node.position)
        let component = context.nextComponent(kind: "struct", name: node.name.text)
        let structNode = context.createNode(component: component, typeDescription: "Struct.\(node.name.text)", location: location, isReferenceType: false)
        collectedNodes.append(structNode)
        context.pushScope(component: component)

        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        context.popScope()
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let bindings = node.bindings.first else { return .skipChildren }
        let location = createLocation(from: node.position)

        // Determine variable type
        var variableType = "Unknown"
        var isReferenceType = false
        var isWeak = false
        var isUnowned = false

        if let typeAnnotation = bindings.typeAnnotation {
            variableType = typeAnnotation.type.trimmedDescription
            isReferenceType = isReferenceTypeString(variableType)
        }

        // Check for weak/unowned in modifiers
        // In Swift, weak and unowned are declaration modifiers
        for modifier in node.modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.weak):
                isWeak = true
            case .keyword(.unowned):
                isUnowned = true
            default:
                break
            }
        }

        let variableName = bindings.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
        let component = context.nextComponent(kind: "var", name: variableName)
        let variableNode = context.createNode(component: component, typeDescription: variableType, location: location, isReferenceType: isReferenceType)
        collectedNodes.append(variableNode)

        // Analyze initial value
        if let initializer = bindings.initializer {
            analyzeInitializer(initializer.value, variableNode: variableNode, isWeak: isWeak, isUnowned: isUnowned, location: location)
        } else if isWeak || isUnowned {
            // For weak/unowned properties without initializer, still record the reference type
            let referenceType: OwnershipGraph.ReferenceType = isWeak ? .weak : .unowned
            let reference = OwnershipGraph.Reference(
                from: variableNode.id,
                to: variableType,
                type: referenceType,
                location: location,
                isWeak: isWeak
            )
            collectedReferences.append(reference)
        }

        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let location = createLocation(from: node.position)
        let component = context.nextComponent(kind: "func", name: node.name.text)
        let functionNode = context.createNode(component: component, typeDescription: "Function.\(node.name.text)", location: location, isReferenceType: false)
        collectedNodes.append(functionNode)
        context.functionIdStack.append(functionNode.id)
        context.pushScope(component: component)

        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        context.popScope()
        _ = context.functionIdStack.popLast()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        let location = createLocation(from: node.position)
        let component = context.nextComponent(kind: "closure", name: nil)
        let closureNode = context.createNode(component: component, typeDescription: "Closure", location: location, isReferenceType: false)
        collectedNodes.append(closureNode)
        context.pushScope(component: component)

        // Analyze capture list - API changed in SwiftSyntax 600.0.0
        // TODO: Update capture list analysis for new SwiftSyntax API
        // if let captureList = node.signature?.captures {
        //     analyzeCaptureList(captureList, closureNode: closureNode)
        // }

        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        context.popScope()
    }

    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        if let expression = node.expression {
            analyzeReturnStatement(expression, location: createLocation(from: node.position))
        }
        return .skipChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        // In SwiftSyntax 600.0.0, assignments are InfixOperatorExprSyntax where
        // the operator is AssignmentExprSyntax
        guard node.operator.as(AssignmentExprSyntax.self) != nil else {
            return .visitChildren
        }
        
        let location = createLocation(from: node.position)
        let lhs = node.leftOperand
        let rhs = node.rightOperand
        
        analyzeAssignment(lhs: lhs, rhs: rhs, location: location)
        return .visitChildren
    }

    // MARK: - Private Helper Methods

    private func analyzeInitializer(_ value: ExprSyntax, variableNode: OwnershipGraph.Node, isWeak: Bool, isUnowned: Bool, location: Location) {
        let valueString = value.trimmedDescription
        
        // Skip literal values - they don't create ownership relationships
        guard !isUnassignableLiteral(valueString) else {
            return
        }

        // Create reference from variable to value
        var referenceType: OwnershipGraph.ReferenceType = .assignment
        if isWeak {
            referenceType = .weak
        } else if isUnowned {
            referenceType = .unowned
        }

        let reference = OwnershipGraph.Reference(
            from: variableNode.id,
            to: valueString,
            type: referenceType,
            location: location,
            isWeak: isWeak
        )

        collectedReferences.append(reference)
    }

    private func analyzeCaptureList(_ captureList: any SyntaxCollection, closureNode: OwnershipGraph.Node) {
        // In SwiftSyntax 600.0.0, capture list structure may have changed
        for item in captureList {
            guard let syntax = item as? SyntaxProtocol else { continue }
            let loc = converter.location(for: syntax.position)
            let location = Location(
                file: context.currentFile,
                line: loc.line,
                column: loc.column
            )

            // Try to extract the capture variable name from different possible syntax structures
            if let identifierPattern = item as? IdentifierPatternSyntax {
                let identifier = identifierPattern.identifier
                let variableName = identifier.text

                // Create escaping reference from closure to captured variable
                let reference = OwnershipGraph.Reference(
                    from: closureNode.id,
                    to: variableName,
                    type: .capture,
                    location: location,
                    isEscaping: true
                )

                collectedReferences.append(reference)
            }
        }
    }

    private func analyzeReturnStatement(_ expression: ExprSyntax, location: Location) {
        // Analyze what's being returned
        let returnValue = expression.trimmedDescription

        // Create return reference from current function to return value
        if let currentFunctionId = context.currentFunctionId {
            let reference = OwnershipGraph.Reference(
                from: currentFunctionId,
                to: returnValue,
                type: .returnValue,
                location: location,
                isEscaping: true
            )

            collectedReferences.append(reference)
        }
    }

    private func analyzeAssignment(lhs: ExprSyntax, rhs: ExprSyntax, location: Location) {
        let lhsString = lhs.trimmedDescription
        let rhsString = rhs.trimmedDescription
        
        // Skip if LHS is a literal value - you can't assign TO a literal
        // This filters out false positives from malformed AST parsing
        guard !isUnassignableLiteral(lhsString) else {
            return
        }
        
        // Skip if RHS is nil - assigning nil doesn't create ownership relationships
        // that could cause exclusive access violations
        if rhsString == "nil" {
            return
        }

        // Create assignment reference
        let reference = OwnershipGraph.Reference(
            from: lhsString,
            to: rhsString,
            type: .assignment,
            location: location
        )

        collectedReferences.append(reference)
    }
    
    /// Checks if a string represents a value that cannot be assigned to (LHS of assignment)
    private func isUnassignableLiteral(_ value: String) -> Bool {
        // Nil literal - cannot assign TO nil
        if value == "nil" { return true }
        
        // Boolean literals
        if value == "true" || value == "false" { return true }
        
        // Numeric literals (integers and floating point)
        if let _ = Int(value) { return true }
        if let _ = Double(value) { return true }
        
        // Empty collection literals
        if value == "[]" || value == "[:]" || value == "()" { return true }
        
        // String literals - cannot assign to a string literal
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("#\"") && value.hasSuffix("\"#")) ||
           (value.hasPrefix("\"\"\"") && value.hasSuffix("\"\"\"")) {
            return true
        }
        
        return false
    }

    private func isReferenceTypeString(_ type: String) -> Bool {
        // Heuristic to determine if a type is a reference type
        let referenceTypes = ["String", "Array", "Dictionary", "Set", "Data", "URL", "Date", "NSObject", "UIView", "UIViewController"]
        return referenceTypes.contains { type.contains($0) } || type.hasSuffix("Class") || type.hasSuffix("Controller") || type.hasSuffix("View")
    }
}
}

/// Result of ownership analysis
public struct OwnershipAnalysisResult: Sendable {
    public let graph: OwnershipGraph
    public let statistics: OwnershipStatistics
    public let issues: [MemorySafetyIssue]

    init(graph: OwnershipGraph, statistics: OwnershipStatistics, issues: [MemorySafetyIssue] = []) {
        self.graph = graph
        self.statistics = statistics
        self.issues = issues
    }
}

/// Types of memory safety issues
public enum MemorySafetyIssueType: String, Codable, CaseIterable, Sendable {
    case useAfterFree = "use_after_free"
    case memoryLeak = "memory_leak"
    case retainCycle = "retain_cycle"
    case escapingReference = "escaping_reference"
    case exclusiveAccessViolation = "exclusive_access_violation"
}

/// Represents a memory safety issue found during analysis
public struct MemorySafetyIssue: Codable, Sendable {
    public let type: MemorySafetyIssueType
    public let location: Location
    public let message: String
    public let severity: DiagnosticSeverity
    public let nodeId: String
    public let referenceId: String?

    public init(type: MemorySafetyIssueType, location: Location, message: String, severity: DiagnosticSeverity, nodeId: String, referenceId: String? = nil) {
        self.type = type
        self.location = location
        self.message = message
        self.severity = severity
        self.nodeId = nodeId
        self.referenceId = referenceId
    }
}


/// Extension to get path without extension
private extension URL {
    var pathWithoutExtension: String {
        return self.deletingPathExtension().path
    }
}
