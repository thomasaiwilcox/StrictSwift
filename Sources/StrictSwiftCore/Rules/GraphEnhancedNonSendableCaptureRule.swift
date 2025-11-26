import Foundation
import SwiftSyntax

/// Enhanced non-Sendable capture detection using GlobalReferenceGraph
///
/// Uses the symbol graph to check actual Sendable conformance of captured types,
/// providing more accurate detection than heuristic-based approaches.
///
/// Enable with `useEnhancedRules: true` in strictswift.yml
public final class GraphEnhancedNonSendableCaptureRule: Rule {
    public var id: String { "non_sendable_capture_graph" }
    public var name: String { "Non-Sendable Capture (Graph)" }
    public var description: String { "Detects non-Sendable captures using symbol graph conformance checking" }
    public var category: RuleCategory { .concurrency }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { false } // Opt-in via useEnhancedRules

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        guard context.configuration.useEnhancedRules else { return [] }

        var violations: [Violation] = []
        let graph = context.globalGraph()

        // Find closures in async contexts
        let visitor = AsyncClosureVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile.tree)

        for capture in visitor.capturedVariables {
            // Try to find the type of the captured variable
            if let typeID = findTypeForVariable(capture.variableName, in: sourceFile, graph: graph) {
                // Check if type conforms to Sendable
                if !graph.conformsToSendable(typeID) {
                    let violation = ViolationBuilder(ruleId: id, category: category, location: capture.location)
                        .message("Captured variable '\(capture.variableName)' may not be Sendable")
                        .suggestFix("Make the type conform to Sendable or use a value type")
                        .severity(defaultSeverity)
                        .build()
                    violations.append(violation)
                }
            }
        }

        return violations
    }

    /// Attempts to find the type symbol for a variable by name
    private func findTypeForVariable(
        _ name: String, 
        in sourceFile: SourceFile, 
        graph: GlobalReferenceGraph
    ) -> SymbolID? {
        // Look for variable symbol in file
        for symbol in sourceFile.symbols where symbol.name == name && symbol.kind == .variable {
            // Check references from this variable to find its type
            let references = graph.getReferences(symbol.id)
            for ref in references {
                if ref.kind == .class || ref.kind == .struct || ref.kind == .actor {
                    return ref
                }
            }
        }
        return nil
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

// MARK: - Async Closure Visitor

private struct CapturedVariable {
    let variableName: String
    let location: Location
}

private final class AsyncClosureVisitor: SyntaxVisitor {
    var capturedVariables: [CapturedVariable] = []
    private var inAsyncContext = false
    var currentFileURL: URL?

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for Task { } or other async-initiating calls
        let callText = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        
        if callText == "Task" || callText.contains("Task.detached") || callText.contains("TaskGroup") {
            let wasInAsync = inAsyncContext
            inAsyncContext = true
            
            // Analyze the trailing closure for captured variables
            if let closure = node.trailingClosure {
                analyzeClosureCaptures(closure)
            }
            
            inAsyncContext = wasInAsync
        }
        
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for async functions - visiting children will be in async context
        let isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
        if isAsync {
            inAsyncContext = true
        }
        return .visitChildren
    }

    private func analyzeClosureCaptures(_ closure: ClosureExprSyntax) {
        // Look for explicit capture list
        if let captureList = closure.signature?.capture?.items {
            for capture in captureList {
                let name = capture.expression.description.trimmingCharacters(in: .whitespaces)
                let location = Location(
                    file: currentFileURL ?? URL(fileURLWithPath: "unknown"),
                    line: 1,
                    column: 1
                )
                capturedVariables.append(CapturedVariable(variableName: name, location: location))
            }
        }
        
        // Look for implicit captures (variables referenced in closure body)
        let bodyVisitor = VariableReferenceVisitor(viewMode: .sourceAccurate)
        bodyVisitor.currentFileURL = currentFileURL
        bodyVisitor.walk(closure.statements)
        
        for ref in bodyVisitor.variableReferences {
            capturedVariables.append(ref)
        }
    }
}

private final class VariableReferenceVisitor: SyntaxVisitor {
    var variableReferences: [CapturedVariable] = []
    var currentFileURL: URL?

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        let location = Location(
            file: currentFileURL ?? URL(fileURLWithPath: "unknown"),
            line: 1,
            column: 1
        )
        variableReferences.append(CapturedVariable(variableName: name, location: location))
        return .visitChildren
    }
}
