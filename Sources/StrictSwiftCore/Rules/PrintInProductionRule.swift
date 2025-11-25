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
private final class PrintInProductionVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// Debug output functions to detect
    private let debugFunctions = ["print", "dump", "debugPrint"]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        let description = node.description
        
        // Check for debug output function calls
        for funcName in debugFunctions {
            let pattern = "\(funcName)("
            if description.contains(pattern) {
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

                return .skipChildren
            }
        }

        return .visitChildren
    }
}