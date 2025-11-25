import Foundation
import SwiftSyntax

/// Detects force unwraps in Swift code
public final class ForceUnwrapRule: Rule {
    public var id: String { "force_unwrap" }
    public var name: String { "Force Unwrap" }
    public var description: String { "Detects force unwrapping of optional values" }
    public var category: RuleCategory { .safety }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        // Visit the tree to find force unwrap expressions
        let visitor = ForceUnwrapVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds force unwrap expressions
private final class ForceUnwrapVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        // Get the location from the position
        let location = sourceFile.location(for: node.position)

        let violation = ViolationBuilder(
            ruleId: "force_unwrap",
            category: .safety,
            location: location
        )
        .message("Force unwrap (!) of optional value. Consider using optional binding or guard let")
        .suggestFix("Replace with optional binding: if let value = optionalValue { ... }")
        .severity(.error)
        .build()

        violations.append(violation)

        return .skipChildren
    }

    public override func visit(_ node: OptionalChainingExprSyntax) -> SyntaxVisitorContinueKind {
        // Look for force unwrap within optional chaining (e.g., value!.property)
        if let forcedValue = node.expression.as(ForceUnwrapExprSyntax.self) {
            let location = sourceFile.location(for: forcedValue.position)

            let violation = ViolationBuilder(
                ruleId: "force_unwrap",
                category: .safety,
                location: location
            )
            .message("Force unwrap in optional chaining. Consider safe optional chaining instead")
            .suggestFix("Replace '?' instead of '!' if nil values are acceptable")
            .severity(.error)
            .build()

            violations.append(violation)
        }

        return .visitChildren
    }
}
