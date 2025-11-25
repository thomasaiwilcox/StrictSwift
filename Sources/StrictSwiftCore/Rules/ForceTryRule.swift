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
        
        let location = sourceFile.location(of: node)
        
        // Generate structured fixes
        let fixes = generateStructuredFixes(for: node)

        var builder = ViolationBuilder(
            ruleId: "force_try",
            category: .safety,
            location: location
        )
        .message("Force try (!) expression can crash the application if an error is thrown")
        .suggestFix("Use proper error handling: do-catch block, try?, or rethrow the error appropriately")
        .severity(.error)
        
        for fix in fixes {
            builder = builder.addStructuredFix(fix)
        }
        
        violations.append(builder.build())

        return .visitChildren
    }
    
    /// Generates structured fixes for a force try expression
    private func generateStructuredFixes(for node: TryExprSyntax) -> [StructuredFix] {
        var fixes: [StructuredFix] = []
        
        // Get position info from node
        let startLocation = sourceFile.location(for: node.position)
        let endLocation = sourceFile.location(for: node.endPosition)
        let filePath = sourceFile.url.path
        
        let range = SourceRange(
            startLine: startLocation.line,
            startColumn: startLocation.column,
            endLine: endLocation.line,
            endColumn: endLocation.column,
            file: filePath
        )
        
        let expressionText = node.expression.description.trimmingCharacters(in: .whitespaces)
        
        // Fix 1: Replace with try? (preferred - simple and safe)
        let tryOptionalCode = "try? \(expressionText)"
        fixes.append(StructuredFix(
            title: "Replace with try?",
            kind: .replaceWithTryOptional,
            edits: [TextEdit(range: range, newText: tryOptionalCode)],
            isPreferred: true,
            confidence: .safe,
            description: "Replaces try! with try? which returns nil on error instead of crashing",
            ruleId: "force_try"
        ))
        
        // Fix 2: Wrap in do-catch block
        let doCatchCode = """
            do {
                try \(expressionText)
            } catch {
                // Handle error appropriately
                print("Error: \\(error)")
            }
            """
        fixes.append(StructuredFix(
            title: "Wrap in do-catch block",
            kind: .addDoCatch,
            edits: [TextEdit(range: range, newText: doCatchCode)],
            isPreferred: false,
            confidence: .suggested,
            description: "Wraps the throwing call in a do-catch block for explicit error handling",
            ruleId: "force_try"
        ))
        
        // Fix 3: Convert to regular try (if in throwing context)
        let regularTryCode = "try \(expressionText)"
        fixes.append(StructuredFix(
            title: "Convert to regular try",
            kind: .replace,
            edits: [TextEdit(range: range, newText: regularTryCode)],
            isPreferred: false,
            confidence: .experimental,
            description: "Converts to regular try - only valid in a throwing function or do-catch",
            ruleId: "force_try"
        ))
        
        return fixes
    }
}