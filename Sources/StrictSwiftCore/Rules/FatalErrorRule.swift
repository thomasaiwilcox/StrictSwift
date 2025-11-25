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
private final class FatalErrorVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// Fatal/crash functions to detect
    private let fatalFunctions = ["fatalError", "preconditionFailure", "assertionFailure"]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        let description = node.description
        
        // Check for fatal function calls
        for funcName in fatalFunctions {
            let pattern = "\(funcName)("
            if description.contains(pattern) {
                let location = sourceFile.location(for: node.position)

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

                return .skipChildren
            }
        }

        return .visitChildren
    }
}