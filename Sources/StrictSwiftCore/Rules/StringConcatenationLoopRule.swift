import SwiftSyntax

/// Rule that detects string concatenation inside loops
/// SAFETY: @unchecked Sendable is safe because the rule is stateless and analyze() creates a fresh visitor.
public final class StringConcatenationLoopRule: Rule, @unchecked Sendable {
    public var id: String { "string_concatenation_loop" }
    public var name: String { "String Concatenation in Loop" }
    public var description: String { "Detects string concatenation inside loops which has O(n²) complexity" }
    public var category: RuleCategory { .performance }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let visitor = StringConcatenationVisitor(sourceFile: sourceFile)
        visitor.walk(sourceFile.tree)
        return visitor.violations
    }
}

private final class StringConcatenationVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    var loopDepth = 0

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        loopDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: ForStmtSyntax) {
        loopDepth -= 1
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        loopDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: WhileStmtSyntax) {
        loopDepth -= 1
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        loopDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: RepeatStmtSyntax) {
        loopDepth -= 1
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard loopDepth > 0 else { return .visitChildren }
        
        let elements = Array(node.elements)
        for (index, element) in elements.enumerated() {
            if let binOp = element.as(BinaryOperatorExprSyntax.self) {
                let op = binOp.operator.trimmedDescription
                if op == "+" || op == "+=" {
                    // Left is index - 1, Right is index + 1
                    if index > 0 && index + 1 < elements.count {
                        let left = elements[index - 1]
                        let right = elements[index + 1]
                        
                        if isLikelyStringOperation(left: left, right: right) {
                            var builder = ViolationBuilder(
                                ruleId: "string_concatenation_loop",
                                category: .performance,
                                location: sourceFile.location(of: binOp)
                            )
                            .message("String concatenation inside loop has O(n²) complexity")
                            .suggestFix("Use an array of strings and join them, or use a string builder pattern")
                            .severity(.warning)
                            
                            // Auto-fix: Convert += to .append()
                            if op == "+=" {
                                builder = builder.addStructuredFix(
                                    title: "Convert to .append()",
                                    kind: .refactor
                                ) { fix in
                                    // Replace " += " with ".append("
                                    fix.addEdit(TextEdit(range: SourceRange(start: sourceFile.location(of: binOp), end: sourceFile.location(endOf: binOp)), newText: ".append("))
                                    // Append ")" at the end of the right operand
                                    fix.addEdit(TextEdit.insert(at: sourceFile.location(endOf: right), text: ")"))
                                }
                            }
                            
                            violations.append(builder.build())
                        }
                    }
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        guard loopDepth > 0 else { return .visitChildren }

        let op = node.operator.trimmedDescription
        guard op == "+=" || op == "+" else { return .visitChildren }

        if isLikelyStringOperation(left: node.leftOperand, right: node.rightOperand) {
            violations.append(
                ViolationBuilder(
                    ruleId: "string_concatenation_loop",
                    category: .performance,
                    location: sourceFile.location(of: node)
                )
                .message("String concatenation inside loop has O(n²) complexity")
                .suggestFix("Use an array of strings and join them, or use a string builder pattern")
                .severity(.warning)
                .build()
            )
        }

        return .visitChildren
    }

    private func isLikelyStringOperation(left: ExprSyntax, right: ExprSyntax) -> Bool {
        let leftDesc = left.trimmedDescription
        let rightDesc = right.trimmedDescription

        // Check for string literals
        if leftDesc.contains("\"") || rightDesc.contains("\"") { return true }
        
        // Check for String initializer
        if leftDesc.contains("String(") || rightDesc.contains("String(") { return true }

        // Check for common string variable names (heuristic)
        let stringNames = ["str", "string", "text", "message", "html", "json", "xml", "query", "sql", "path", "url", "result", "output", "line", "content", "buffer", "log"]
        let leftLower = leftDesc.lowercased()
        
        // Check if variable name contains string-like terms
        if stringNames.contains(where: { leftLower.contains($0) }) { return true }

        return false
    }
}
