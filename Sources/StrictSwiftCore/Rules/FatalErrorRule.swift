import Foundation
import SwiftSyntax

/// Detects fatalError(), preconditionFailure(), and assertionFailure() calls which crash the application
public final class FatalErrorRule: Rule {
    public var id: String { "fatal_error" }
    public var name: String { "Fatal Error" }
    public var description: String { "Detects fatalError(), preconditionFailure(), and assertionFailure() calls which crash the application" }
    public var category: RuleCategory { .safety }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = FatalErrorVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds fatalError(), preconditionFailure(), and assertionFailure() calls
private final class FatalErrorVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// Fatal/crash functions to detect
    private static let fatalFunctions: Set<String> = ["fatalError", "preconditionFailure", "assertionFailure"]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Get the function name from the called expression
        let funcName: String
        
        if let identifier = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            funcName = identifier.baseName.text
        } else if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            // Handle cases like Swift.fatalError()
            funcName = memberAccess.declName.baseName.text
        } else {
            return .visitChildren
        }
        
        // Check if this is a fatal function call
        guard Self.fatalFunctions.contains(funcName) else {
            return .visitChildren
        }
        
        let location = sourceFile.location(of: node)

        let violation = ViolationBuilder(
            ruleId: "fatal_error",
            category: .safety,
            location: location
        )
        .message("\(funcName)() call crashes the application unconditionally")
        .suggestFix("Replace with proper error handling: return error, use optional, or throw an exception")
        .severity(.error)
        .build()

        violations.append(violation)

        return .visitChildren
    }
}