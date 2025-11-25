import Foundation
import SwiftSyntax

/// Detects print() statements in production code
public final class PrintInProductionRule: Rule {
    public var id: String { "print_in_production" }
    public var name: String { "Print in Production" }
    public var description: String { "Detects print(), dump(), and debugPrint() statements that should not be in production code" }
    public var category: RuleCategory { .safety }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = PrintInProductionVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds print(), dump(), debugPrint() statements
private final class PrintInProductionVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// Debug output functions to detect
    private static let debugFunctions: Set<String> = ["print", "dump", "debugPrint"]

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
            // Handle cases like Swift.print()
            funcName = memberAccess.declName.baseName.text
        } else {
            return .visitChildren
        }
        
        // Check if this is a debug output function call
        guard Self.debugFunctions.contains(funcName) else {
            return .visitChildren
        }
        
        let location = sourceFile.location(for: node.position)

        let violation = ViolationBuilder(
            ruleId: "print_in_production",
            category: .safety,
            location: location
        )
        .message("\(funcName)() statement found in production code")
        .suggestFix("Replace with proper logging framework or remove debug output")
        .severity(.warning)
        .build()

        violations.append(violation)

        return .visitChildren
    }
}