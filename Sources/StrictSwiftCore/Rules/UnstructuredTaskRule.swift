import Foundation
import SwiftSyntax

/// Detects unstructured Task creation that should use structured concurrency
public final class UnstructuredTaskRule: Rule {
    public var id: String { "unstructured_task" }
    public var name: String { "Unstructured Task" }
    public var description: String { "Detects unstructured Task creation that should use structured concurrency" }
    public var category: RuleCategory { .concurrency }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = UnstructuredTaskVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds unstructured Task creation
private final class UnstructuredTaskVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Only check actual function call expressions
        let calledExpr = node.calledExpression.trimmedDescription
        
        // Check if this is a Task call (not Task.detached, TaskGroup, etc.)
        guard calledExpr == "Task" || calledExpr == "Task.init" else {
            return .visitChildren
        }
        
        // This is a standalone Task { } or Task.init() call
        // Check if it's followed by .value (which makes it structured)
        if let parent = node.parent, parent.description.contains("}.value") {
            return .visitChildren
        }
        
        // Check if this is inside a withTaskGroup (structured concurrency)
        var ancestor = node.parent
        while let current = ancestor {
            let description = current.trimmedDescription
            if description.hasPrefix("withTaskGroup") || 
               description.hasPrefix("withThrowingTaskGroup") {
                return .visitChildren
            }
            ancestor = current.parent
        }
        
        // Check for justification comments that explain why unstructured Task is intentional
        // Common patterns: fire-and-forget, deprecated bridging, intentional detachment
        let leadingTrivia = node.leadingTrivia.description.lowercased()
        let justificationPatterns = [
            "fire-and-forget", "fire and forget",
            "intentional", "deprecated",
            "task:", "// ok", "// ok:",
            "bridging", "legacy"
        ]
        if justificationPatterns.contains(where: { leadingTrivia.contains($0) }) {
            return .visitChildren
        }

        let location = sourceFile.location(of: Syntax(node))

        let violation = ViolationBuilder(
            ruleId: "unstructured_task",
            category: .concurrency,
            location: location
        )
        .message("Unstructured Task creation detected")
        .suggestFix("Consider using structured concurrency with TaskGroup, async let, or proper task handling")
        .severity(.warning)
        .build()

        violations.append(violation)
        return .skipChildren
    }
}