import Foundation
import SwiftSyntax

/// Detects force try statements (try!)
public final class ForceTryRule: Rule {
    public var id: String { "force_try" }
    public var name: String { "Force Try" }
    public var description: String { "Detects force try statements which can crash the application" }
    public var category: RuleCategory { .safety }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = ForceTryVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds force try expressions
private final class ForceTryVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        // Check if this is a force try (try!)
        // The questionOrExclamationMark property will be "!" for try!
        guard let mark = node.questionOrExclamationMark,
              mark.tokenKind == .exclamationMark else {
            return .visitChildren
        }
        
        let location = sourceFile.location(for: node.position)

        let violation = ViolationBuilder(
            ruleId: "force_try",
            category: .safety,
            location: location
        )
        .message("Force try (!) expression can crash the application if an error is thrown")
        .suggestFix("Use proper error handling: do-catch block, try?, or rethrow the error appropriately")
        .severity(.error)
        .build()

        violations.append(violation)

        return .visitChildren
    }
}