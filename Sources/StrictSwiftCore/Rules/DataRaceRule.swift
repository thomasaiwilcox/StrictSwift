import Foundation
import SwiftSyntax

/// Detects patterns that could lead to data races
public final class DataRaceRule: Rule {
    public var id: String { "data_race" }
    public var name: String { "Data Race" }
    public var description: String { "Detects patterns that could lead to data races" }
    public var category: RuleCategory { .concurrency }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = DataRaceVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds potential data race patterns
private final class DataRaceVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    // Patterns that could indicate data races
    private let dataRacePatterns: Set<String> = [
        "DispatchQueue.global().async",
        "Thread.detachNewThread",
        "Thread()",
        "OperationQueue",
        "NSOperationQueue",
        "pthread_create"
    ]

    // Patterns with mutable state accessed concurrently
    private let mutableStatePatterns: Set<String> = [
        "var", "inout", "&mutating", "UnsafeMutablePointer",
        "UnsafeRawPointer", "UnsafeMutableRawPointer"
    ]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        let nodeDescription = node.description

        // Check for concurrent access patterns
        if isConcurrentAccessPattern(nodeDescription) {
            let location = sourceFile.location(for: node.position)

            let violation = ViolationBuilder(
                ruleId: "data_race",
                category: .concurrency,
                location: location
            )
            .message("Potential data race: concurrent access without proper synchronization")
            .suggestFix("Use locks, queues, or proper synchronization mechanisms")
            .severity(.error)
            .build()

            violations.append(violation)
            return .skipChildren
        }

        // Check for unsafe pointer usage in concurrent contexts
        if isUnsafePointerPattern(nodeDescription) {
            let location = sourceFile.location(for: node.position)

            let violation = ViolationBuilder(
                ruleId: "data_race",
                category: .concurrency,
                location: location
            )
            .message("Unsafe pointer usage detected - potential data race")
            .suggestFix("Consider using safer alternatives or proper memory management")
            .severity(.error)
            .build()

            violations.append(violation)
            return .skipChildren
        }

        // Check for shared mutable state without synchronization
        if isSharedMutableStatePattern(nodeDescription) {
            let location = sourceFile.location(for: node.position)

            let violation = ViolationBuilder(
                ruleId: "data_race",
                category: .concurrency,
                location: location
            )
            .message("Shared mutable state without proper synchronization")
            .suggestFix("Use proper synchronization, actors, or immutable data structures")
            .severity(.error)
            .build()

            violations.append(violation)
            return .skipChildren
        }

        return .visitChildren
    }

    private func isConcurrentAccessPattern(_ nodeDescription: String) -> Bool {
        // Look for concurrent operations on mutable state
        for pattern in dataRacePatterns {
            if nodeDescription.contains(pattern) {
                // Check if there are also mutable state indicators
                for mutablePattern in mutableStatePatterns {
                    if nodeDescription.contains(mutablePattern) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func isUnsafePointerPattern(_ nodeDescription: String) -> Bool {
        // Look for unsafe pointer patterns in concurrent contexts
        return (nodeDescription.contains("UnsafeMutablePointer") ||
                nodeDescription.contains("UnsafeRawPointer") ||
                nodeDescription.contains("UnsafeMutableRawPointer")) &&
               (nodeDescription.contains("DispatchQueue") ||
                nodeDescription.contains("Thread") ||
                nodeDescription.contains("Task {"))
    }

    private func isSharedMutableStatePattern(_ nodeDescription: String) -> Bool {
        // Look for static variables accessed from concurrent contexts
        return nodeDescription.contains("static var") &&
               (nodeDescription.contains("DispatchQueue") ||
                nodeDescription.contains("Thread") ||
                nodeDescription.contains("Task {"))
    }
}