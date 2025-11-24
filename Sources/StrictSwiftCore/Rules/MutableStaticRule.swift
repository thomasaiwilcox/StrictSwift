import Foundation
import SwiftSyntax

/// Detects mutable static variables which can cause data races and global state issues
public final class MutableStaticRule: Rule {
    public var id: String { "mutable_static" }
    public var name: String { "Mutable Static" }
    public var description: String { "Detects mutable static variables which can cause data races and global state issues" }
    public var category: RuleCategory { .safety }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = MutableStaticVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds mutable static variables
private final class MutableStaticVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        // Look for patterns that indicate mutable static variables
        let nodeDescription = node.description

        // Pattern 1: "static var" (mutable static properties)
        if nodeDescription.contains("static var") {
            let location = sourceFile.location(for: node.position)

            let violation = ViolationBuilder(
                ruleId: "mutable_static",
                category: .safety,
                location: location
            )
            .message("Mutable static variable can cause data races and global state issues")
            .suggestFix("Consider using a constant static property, dependency injection, or proper synchronization")
            .severity(.warning)
            .build()

            violations.append(violation)
            return .skipChildren
        }

        // Pattern 2: Look for static variable declarations that might be formatted differently
        if (nodeDescription.contains("static") && nodeDescription.contains("var")) &&
           !nodeDescription.contains("static let") &&
           !nodeDescription.contains("static func") &&
           !nodeDescription.contains("static class") &&
           !nodeDescription.contains("// static") && // Skip comments
           !nodeDescription.contains("/* static") { // Skip block comments

            // Additional check to make sure this is actually a variable declaration
            let words = nodeDescription.components(separatedBy: .whitespacesAndNewlines)
            if words.contains("static") && words.contains("var") {
                let location = sourceFile.location(for: node.position)

                let violation = ViolationBuilder(
                    ruleId: "mutable_static",
                    category: .safety,
                    location: location
                )
                .message("Mutable static variable can cause data races and global state issues")
                .suggestFix("Consider using a constant static property, dependency injection, or proper synchronization")
                .severity(.warning)
                .build()

                violations.append(violation)
                return .skipChildren
            }
        }

        return .visitChildren
    }
}