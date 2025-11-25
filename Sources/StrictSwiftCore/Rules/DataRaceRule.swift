import Foundation
import SwiftSyntax

/// Detects patterns that could lead to data races using AST-based analysis
public final class DataRaceRule: Rule, Sendable {
    public var id: String { "data_race" }
    public var name: String { "Data Race" }
    public var description: String { "Detects patterns that could lead to data races" }
    public var category: RuleCategory { .concurrency }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let tree = sourceFile.tree
        let visitor = DataRaceVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        return visitor.violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// AST-based visitor that finds potential data race patterns
private final class DataRaceVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    // Track context as we traverse
    private var concurrentContextDepth = 0
    private var staticMutableVariables: Set<String> = []

    private var isInConcurrentContext: Bool { concurrentContextDepth > 0 }

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Track Static Mutable Variables

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let isStatic = node.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.static)
        }
        let isVar = node.bindingSpecifier.tokenKind == .keyword(.var)

        if isStatic && isVar {
            for binding in node.bindings {
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    staticMutableVariables.insert(identifier.identifier.text)
                }
            }
        }

        return .visitChildren
    }

    // MARK: - Track Concurrent Contexts via Function Calls

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callDescription = node.calledExpression.trimmedDescription

        // Detect DispatchQueue.*.async patterns
        if callDescription.contains("DispatchQueue") && 
           (callDescription.hasSuffix("async") || callDescription.hasSuffix("sync")) {
            concurrentContextDepth += 1
        }

        // Detect OperationQueue.addOperation patterns
        if callDescription.contains("addOperation") || 
           callDescription.contains("addOperations") {
            concurrentContextDepth += 1
        }

        // Detect Task.detached
        if callDescription.contains("Task.detached") {
            concurrentContextDepth += 1
        }

        // Detect Thread creation
        if callDescription.contains("Thread.detachNewThread") ||
           callDescription == "Thread" {
            concurrentContextDepth += 1
        }

        // Check for static mutable variable access within concurrent context
        if isInConcurrentContext {
            checkForStaticMutableAccess(in: node)
        }

        return .visitChildren
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        let callDescription = node.calledExpression.trimmedDescription

        if (callDescription.contains("DispatchQueue") && 
            (callDescription.hasSuffix("async") || callDescription.hasSuffix("sync"))) ||
           callDescription.contains("addOperation") ||
           callDescription.contains("addOperations") ||
           callDescription.contains("Task.detached") ||
           callDescription.contains("Thread.detachNewThread") ||
           callDescription == "Thread" {
            concurrentContextDepth = max(0, concurrentContextDepth - 1)
        }
    }

    // MARK: - Detect Task { } Blocks (unstructured concurrency)

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for Task macro/initializer
        if node.macroName.text == "Task" {
            concurrentContextDepth += 1
        }
        return .visitChildren
    }

    override func visitPost(_ node: MacroExpansionExprSyntax) {
        if node.macroName.text == "Task" {
            concurrentContextDepth = max(0, concurrentContextDepth - 1)
        }
    }

    // MARK: - Detect Unsafe Pointer Usage

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.name.text

        if isInConcurrentContext {
            if typeName == "UnsafeMutablePointer" ||
               typeName == "UnsafeMutableRawPointer" ||
               typeName == "UnsafeMutableBufferPointer" {

                let location = sourceFile.location(of: node)
                let violation = ViolationBuilder(
                    ruleId: "data_race",
                    category: .concurrency,
                    location: location
                )
                .message("Unsafe mutable pointer '\(typeName)' used in concurrent context - potential data race")
                .suggestFix("Use thread-safe alternatives like atomics or proper synchronization")
                .severity(.error)
                .build()

                violations.append(violation)
            }
        }

        return .visitChildren
    }

    // MARK: - Check Static Mutable Variable Access

    private func checkForStaticMutableAccess(in node: FunctionCallExprSyntax) {
        // Walk through arguments looking for static variable references
        for argument in node.arguments {
            checkExpressionForStaticAccess(argument.expression)
        }

        // Check trailing closure
        if let trailingClosure = node.trailingClosure {
            for statement in trailingClosure.statements {
                checkStatementForStaticAccess(statement)
            }
        }
    }

    private func checkExpressionForStaticAccess(_ expr: ExprSyntax) {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            let name = ref.baseName.text
            if staticMutableVariables.contains(name) {
                reportStaticMutableAccess(at: ref.position, name: name)
            }
        }
    }

    private func checkStatementForStaticAccess(_ statement: CodeBlockItemSyntax) {
        // Simple check for identifier references in statements
        let description = statement.trimmedDescription
        for staticVar in staticMutableVariables {
            if description.contains(staticVar) {
                // Found potential access - report at statement level
                reportStaticMutableAccess(at: statement.position, name: staticVar)
                break
            }
        }
    }

    private func reportStaticMutableAccess(at position: AbsolutePosition, name: String) {
        let location = sourceFile.location(for: position)
        let violation = ViolationBuilder(
            ruleId: "data_race",
            category: .concurrency,
            location: location
        )
        .message("Access to static mutable variable '\(name)' in concurrent context without synchronization")
        .suggestFix("Use actors, locks, or atomic operations for thread-safe access")
        .severity(.error)
        .build()

        violations.append(violation)
    }

    // MARK: - Detect inout in Concurrent Closures

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if isInConcurrentContext {
            if let signature = node.signature,
               let capture = signature.capture {
                for item in capture.items {
                    // Check for inout captures (& prefix)
                    let itemDescription = item.trimmedDescription
                    if itemDescription.contains("&") {
                        let location = sourceFile.location(for: item.position)
                        let violation = ViolationBuilder(
                            ruleId: "data_race",
                            category: .concurrency,
                            location: location
                        )
                        .message("Capturing inout parameter in concurrent closure - potential data race")
                        .suggestFix("Copy the value before capturing or use a thread-safe wrapper")
                        .severity(.error)
                        .build()

                        violations.append(violation)
                    }
                }
            }
        }

        return .visitChildren
    }
}