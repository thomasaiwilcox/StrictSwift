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
private final class MutableStaticVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if this is a static var (not static let)
        let hasStatic = node.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.static)
        }
        
        // Check if this is a var (mutable) and not a let (immutable)
        let isVar = node.bindingSpecifier.tokenKind == .keyword(.var)
        
        // Only flag static var declarations
        guard hasStatic && isVar else {
            return .visitChildren
        }
        
        let location = sourceFile.location(of: node)

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
        return .visitChildren
    }
}
