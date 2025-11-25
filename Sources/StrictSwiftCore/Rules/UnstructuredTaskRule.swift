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

    public override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        let nodeDescription = node.description

        // Look for Task.init or standalone Task calls that indicate unstructured concurrency
        if isUnstructuredTaskCreation(nodeDescription) {
            let location = sourceFile.location(of: node)

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

        return .visitChildren
    }

    private func isUnstructuredTaskCreation(_ nodeDescription: String) -> Bool {
        // Exclude structured concurrency patterns first (more comprehensive)
        if nodeDescription.contains("TaskGroup") ||
           nodeDescription.contains("withTaskGroup") ||
           nodeDescription.contains("async let") ||
           nodeDescription.contains("Task.detached") ||
           nodeDescription.contains("await Task") ||
           (nodeDescription.contains("Task {") && nodeDescription.contains("}.value")) {
            return false
        }

        // Look for specific unstructured Task creation patterns
        // Pattern 1: Task { ... } - standalone task creation
        if nodeDescription.contains("Task {") && !nodeDescription.contains("Task.detached") {
            return true
        }

        // Pattern 2: Task.init(...) - explicit task initialization
        if nodeDescription.contains("Task.init") {
            return true
        }

        return false
    }
}