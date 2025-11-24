import Foundation
import SwiftSyntax

/// Detects potential actor isolation violations
public final class ActorIsolationRule: Rule {
    public var id: String { "actor_isolation" }
    public var name: String { "Actor Isolation" }
    public var description: String { "Detects potential actor isolation violations" }
    public var category: RuleCategory { .concurrency }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = ActorIsolationVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds potential actor isolation violations
private final class ActorIsolationVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    // Patterns that indicate actor contexts
    private let actorContexts: Set<String> = [
        "actor", "MainActor", "@MainActor", "nonisolated"
    ]

    // Patterns that might indicate actor isolation violations
    private let riskyPatterns: Set<String> = [
        "DispatchQueue.main", "NotificationCenter", "UserDefaults",
        "FileManager", "URLSession", "Timer", "RunLoop"
    ]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        let nodeDescription = node.description

        // Look for actor definitions and their usage
        if isActorContext(nodeDescription) {
            analyzeActorContext(node, nodeDescription: nodeDescription)
        }

        // Look for MainActor usage with potential issues
        if nodeDescription.contains("@MainActor") || nodeDescription.contains("MainActor") {
            analyzeMainActorUsage(node, nodeDescription: nodeDescription)
        }

        return .visitChildren
    }

    private func isActorContext(_ nodeDescription: String) -> Bool {
        return nodeDescription.contains("actor ") ||
               nodeDescription.contains("@MainActor") ||
               nodeDescription.contains("MainActor.run") ||
               nodeDescription.contains("nonisolated")
    }

    private func analyzeActorContext(_ node: Syntax, nodeDescription: String) {
        // Check for potentially risky operations in actor context
        for pattern in riskyPatterns {
            if nodeDescription.contains(pattern) {
                let location = sourceFile.location(for: node.position)

                let violation = ViolationBuilder(
                    ruleId: "actor_isolation",
                    category: .concurrency,
                    location: location
                )
                .message("Potentially unsafe operation '\(pattern)' in actor context")
                .suggestFix("Consider using proper actor isolation or move to non-isolated context")
                .severity(.warning)
                .build()

                violations.append(violation)
                break
            }
        }
    }

    private func analyzeMainActorUsage(_ node: Syntax, nodeDescription: String) {
        // Look for MainActor with synchronous access to non-MainActor isolated code
        if nodeDescription.contains("@MainActor") &&
           (nodeDescription.contains("DispatchQueue") ||
            nodeDescription.contains("NotificationCenter") ||
            nodeDescription.contains("UserDefaults")) {

            let location = sourceFile.location(for: node.position)

            let violation = ViolationBuilder(
                ruleId: "actor_isolation",
                category: .concurrency,
                location: location
            )
            .message("MainActor context accessing non-actor isolated APIs")
            .suggestFix("Use Task.detached or proper isolation boundaries")
            .severity(.warning)
            .build()

            violations.append(violation)
        }

        // Check for actor isolation bypass patterns
        if nodeDescription.contains("nonisolated") &&
           nodeDescription.contains("Task") &&
           nodeDescription.contains("MainActor") {

            let location = sourceFile.location(for: node.position)

            let violation = ViolationBuilder(
                ruleId: "actor_isolation",
                category: .concurrency,
                location: location
            )
            .message("Potential actor isolation bypass using nonisolated")
            .suggestFix("Ensure this isolation bypass is intentional and safe")
            .severity(.warning)
            .build()

            violations.append(violation)
        }
    }
}