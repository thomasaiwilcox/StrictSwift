import SwiftSyntax

/// Rule that detects regex compilation inside loops
/// SAFETY: @unchecked Sendable is safe because the rule is stateless and analyze() creates a fresh visitor.
public final class RegexCompilationInLoopRule: Rule, @unchecked Sendable {
    public var id: String { "regex_compilation_in_loop" }
    public var name: String { "Regex Compilation in Loop" }
    public var description: String { "Detects regex compilation inside loops which is expensive" }
    public var category: RuleCategory { .performance }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let visitor = RegexCompilationVisitor(sourceFile: sourceFile)
        visitor.walk(sourceFile.tree)
        return visitor.violations
    }
}

private final class RegexCompilationVisitor: SyntaxVisitor {
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

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard loopDepth > 0 else { return .visitChildren }

        let called = node.calledExpression.trimmedDescription
        
        if isRegexCompilation(called) {
            violations.append(
                ViolationBuilder(
                    ruleId: "regex_compilation_in_loop",
                    category: .performance,
                    location: sourceFile.location(of: node)
                )
                .message("Regex compilation '\(called)' inside loop is expensive")
                .suggestFix("Compile the regex once outside the loop and reuse it")
                .severity(.warning)
                .build()
            )
        }

        return .visitChildren
    }
    
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        guard loopDepth > 0 else { return .visitChildren }
        
        // Check for #/ regex literal syntax which compiles at runtime in some contexts?
        // Actually #/.../ is a compile-time literal in Swift 5.7+, so it's fine!
        // But Regex(...) initializer is runtime.
        
        return .visitChildren
    }

    private func isRegexCompilation(_ name: String) -> Bool {
        let patterns = [
            "Regex",
            "NSRegularExpression",
            "try Regex",
            "try! Regex",
            "try? Regex"
        ]
        
        return patterns.contains { pattern in
            name == pattern || name.hasSuffix("." + pattern)
        }
    }
}
