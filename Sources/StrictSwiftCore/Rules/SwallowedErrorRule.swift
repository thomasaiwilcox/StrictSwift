import SwiftSyntax

/// Rule that detects swallowed errors (empty catch blocks or catch blocks that only log)
/// SAFETY: @unchecked Sendable is safe because the rule is stateless.
public final class SwallowedErrorRule: Rule, @unchecked Sendable {
    public var id: String { "swallowed_error" }
    public var name: String { "Swallowed Error" }
    public var description: String { "Detects empty catch blocks or catch blocks that only log errors without handling them" }
    public var category: RuleCategory { .safety }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let visitor = SwallowedErrorVisitor(sourceFile: sourceFile)
        visitor.walk(sourceFile.tree)
        return visitor.violations
    }
}

private final class SwallowedErrorVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        let statements = node.body.statements
        
        // Check for empty catch block
        if statements.isEmpty {
            var builder = ViolationBuilder(
                ruleId: "swallowed_error",
                category: .safety,
                location: sourceFile.location(of: node)
            )
            .message("Empty catch block swallows errors silently")
            .suggestFix("Handle the error, log it, or rethrow it")
            .severity(.warning)
            
            // Auto-fix
            builder = builder.addStructuredFix(
                title: "Add TODO comment",
                kind: .refactor
            ) { fix in
                // Insert inside the block
                fix.addEdit(TextEdit.insert(
                    at: sourceFile.location(endOf: node.body.leftBrace), 
                    text: "\n    // TODO: Handle error"
                ))
            }
            
            violations.append(builder.build())
            return .visitChildren
        }
        
        // Check for catch block that only prints/logs
        // Heuristic: if all statements are print() or logger calls, and no return/throw/fatalError
        if areAllStatementsLogging(statements) {
             violations.append(
                ViolationBuilder(
                    ruleId: "swallowed_error",
                    category: .safety,
                    location: sourceFile.location(of: node)
                )
                .message("Catch block only logs error but continues execution")
                .suggestFix("Consider returning, throwing, or handling the error state")
                .severity(.warning)
                .build()
            )
        }

        return .visitChildren
    }
    
    private func areAllStatementsLogging(_ statements: CodeBlockItemListSyntax) -> Bool {
        for stmt in statements {
            if isControlFlow(stmt.item) { return false }
            
            if let exprStmt = stmt.item.as(ExpressionStmtSyntax.self) {
                if !isLoggingCall(exprStmt.expression) { return false }
            } else {
                // Any other statement type (declaration, loop, if, etc.) means it's doing logic
                return false
            }
        }
        return true
    }
    
    private func isControlFlow(_ item: CodeBlockItemSyntax.Item) -> Bool {
        return item.is(ReturnStmtSyntax.self) || 
               item.is(ThrowStmtSyntax.self) ||
               item.is(BreakStmtSyntax.self) ||
               item.is(ContinueStmtSyntax.self)
    }
    
    private func isLoggingCall(_ expr: ExprSyntax) -> Bool {
        guard let call = expr.as(FunctionCallExprSyntax.self) else { return false }
        let name = call.calledExpression.trimmedDescription
        
        let loggingNames = ["print", "debugPrint", "NSLog", "os_log", "Logger", "log", "info", "warning", "error", "debug"]
        return loggingNames.contains { name.contains($0) }
    }
}
