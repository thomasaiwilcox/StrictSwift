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
        guard sourceFile.url.pathExtension == "swift" else { return false }
        
        // Skip CLI modules - print() is expected and legitimate there
        let path = sourceFile.url.path
        if path.contains("/CLI/") || path.contains("CLI.swift") || 
           path.hasSuffix("Command.swift") || path.contains("/Commands/") {
            return false
        }
        
        return true
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
        
        let location = sourceFile.location(of: node)
        
        // Generate structured fixes
        let fixes = generateStructuredFixes(for: node, funcName: funcName)

        var builder = ViolationBuilder(
            ruleId: "print_in_production",
            category: .safety,
            location: location
        )
        .message("\(funcName)() statement found in production code")
        .suggestFix("Replace with proper logging framework or remove debug output")
        .severity(.warning)
        
        for fix in fixes {
            builder = builder.addStructuredFix(fix)
        }
        
        violations.append(builder.build())

        return .visitChildren
    }
    
    /// Generates structured fixes for a print statement
    private func generateStructuredFixes(for node: FunctionCallExprSyntax, funcName: String) -> [StructuredFix] {
        var fixes: [StructuredFix] = []
        
        // Get position info from node
        let startLocation = sourceFile.location(of: node)
        let endLocation = sourceFile.location(for: node.endPosition)
        let filePath = sourceFile.url.path
        
        let range = SourceRange(
            startLine: startLocation.line,
            startColumn: startLocation.column,
            endLine: endLocation.line,
            endColumn: endLocation.column,
            file: filePath
        )
        
        // Find the full statement including any trailing newline
        let statementRange = findStatementRange(for: node)
        
        // Fix 1: Wrap in #if DEBUG (preferred)
        let wrappedCode = "#if DEBUG\n\(node.description)\n#endif"
        fixes.append(StructuredFix(
            title: "Wrap in #if DEBUG",
            kind: .wrapConditional,
            edits: [TextEdit(range: range, newText: wrappedCode)],
            isPreferred: true,
            confidence: .safe,
            description: "Wraps the \(funcName)() call in a #if DEBUG block so it only runs in debug builds",
            ruleId: "print_in_production"
        ))
        
        // Fix 2: Remove the statement entirely
        fixes.append(StructuredFix(
            title: "Remove \(funcName)() statement",
            kind: .removeCode,
            edits: [TextEdit.delete(range: statementRange)],
            isPreferred: false,
            confidence: .suggested,
            description: "Removes the debug output statement entirely",
            ruleId: "print_in_production"
        ))
        
        // Fix 3: Replace with os_log (if available)
        let arguments = node.arguments.map { $0.expression.description }.joined(separator: ", ")
        let osLogCode = "os_log(\"%{public}@\", \(arguments))"
        fixes.append(StructuredFix(
            title: "Replace with os_log()",
            kind: .replace,
            edits: [TextEdit(range: range, newText: osLogCode)],
            isPreferred: false,
            confidence: .experimental,
            description: "Replaces with os_log() for proper system logging (requires 'import os')",
            ruleId: "print_in_production"
        ))
        
        return fixes
    }
    
    /// Finds the full statement range including leading whitespace and trailing newline
    private func findStatementRange(for node: FunctionCallExprSyntax) -> SourceRange {
        let startLocation = sourceFile.location(of: node)
        let endLocation = sourceFile.location(for: node.endPosition)
        let filePath = sourceFile.url.path
        
        // For removal, we want to include the entire line if this is the only statement
        return SourceRange(
            startLine: startLocation.line,
            startColumn: 1, // Start from beginning of line
            endLine: endLocation.line + 1,
            endColumn: 1, // Include the newline
            file: filePath
        )
    }
}