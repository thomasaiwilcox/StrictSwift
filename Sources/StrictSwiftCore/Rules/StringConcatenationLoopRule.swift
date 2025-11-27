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
        // Skip files that are explicitly for output generation
        // These legitimately build strings in loops for formatting/reporting
        let fileName = sourceFile.url.lastPathComponent
        let outputPatterns = ["Reporter", "Visualizer", "Generator", "Formatter", "Printer", "Writer", "Renderer", "Exporter"]
        if outputPatterns.contains(where: { fileName.contains($0) }) {
            return []
        }
        
        let visitor = StringConcatenationVisitor(sourceFile: sourceFile)
        visitor.walk(sourceFile.tree)
        return visitor.violations
    }
}

private final class StringConcatenationVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    var loopDepth = 0
    var inBoundedLoop = false  // Track if we're in a loop with bounded iterations
    var currentForLoop: ForStmtSyntax?

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        loopDepth += 1
        currentForLoop = node
        
        // Check if this is a bounded loop (small iteration count)
        inBoundedLoop = isBoundedLoop(node)
        
        return .visitChildren
    }

    override func visitPost(_ node: ForStmtSyntax) {
        loopDepth -= 1
        inBoundedLoop = false
        currentForLoop = nil
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
        guard loopDepth > 0, !inBoundedLoop else { return .visitChildren }
        
        let elements = Array(node.elements)
        for (index, element) in elements.enumerated() {
            guard let binOp = element.as(BinaryOperatorExprSyntax.self) else { continue }
            let op = binOp.operator.trimmedDescription
            
            // Only flag += (accumulating) operations, not simple + concatenations
            // Simple + for building a search string is O(1), not O(n²)
            guard op == "+=" else { continue }
            guard index > 0 && index + 1 < elements.count else { continue }
            
            let left = elements[index - 1]
            let right = elements[index + 1]
            
            // Skip if building a hash/key/identifier (intentional concatenation)
            if isHashOrKeyBuilding(left: left, right: right) { continue }
            
            guard isLikelyStringOperation(left: left, right: right) else { continue }
            
            let violation = createViolation(at: binOp, op: op, right: right)
            violations.append(violation)
        }
        return .visitChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        guard loopDepth > 0, !inBoundedLoop else { return .visitChildren }

        let op = node.operator.trimmedDescription
        // Only flag += (accumulating) operations, not simple + concatenations
        guard op == "+=" else { return .visitChildren }

        // Skip if building a hash/key/identifier (intentional concatenation)
        if isHashOrKeyBuilding(left: node.leftOperand, right: node.rightOperand) {
            return .visitChildren
        }

        if isLikelyStringOperation(left: node.leftOperand, right: node.rightOperand) {
            let violation = createViolation(at: node, op: op, right: node.rightOperand)
            violations.append(violation)
        }

        return .visitChildren
    }
    
    // MARK: - Helpers
    
    private func isBoundedLoop(_ node: ForStmtSyntax) -> Bool {
        let sequenceDesc = node.sequence.trimmedDescription
        
        // Check for .prefix() - bounded to small number of items
        if sequenceDesc.contains(".prefix(") {
            // Extract the number from prefix(N) if possible
            if let match = sequenceDesc.range(of: #"\.prefix\((\d+)\)"#, options: .regularExpression),
               let numStr = sequenceDesc[match].split(separator: "(").last?.dropLast(),
               let num = Int(numStr), num <= 5 {
                return true
            }
        }
        
        // Check for small literal ranges like 0..<3, 1...5
        // Only consider very small ranges (<=5) as truly bounded
        if let range = node.sequence.as(SequenceExprSyntax.self) {
            let rangeDesc = range.trimmedDescription
            if rangeDesc.contains("..<") || rangeDesc.contains("...") {
                let digits = rangeDesc.filter { $0.isNumber }
                if let endValue = Int(digits), endValue <= 5 {
                    return true
                }
            }
        }
        
        // Check for fixed-size collections
        let boundedPatterns = [".enumerated().prefix(", ".sorted().prefix("]
        if boundedPatterns.contains(where: { sequenceDesc.contains($0) }) {
            return true
        }
        
        return false
    }
    
    private func isHashOrKeyBuilding(left: ExprSyntax, right: ExprSyntax) -> Bool {
        let leftDesc = left.trimmedDescription.lowercased()
        
        // Common names for hash/key/cache key building
        let hashKeyPatterns = ["hash", "key", "identifier", "id", "cache", "signature", "digest", "checksum"]
        return hashKeyPatterns.contains(where: { leftDesc.contains($0) })
    }
    
    private func createViolation(at node: SyntaxProtocol, op: String, right: ExprSyntax) -> Violation {
        var builder = ViolationBuilder(
            ruleId: "string_concatenation_loop",
            category: .performance,
            location: sourceFile.location(of: node)
        )
        .message("String concatenation inside loop has O(n²) complexity")
        .suggestFix("Use an array of strings and join them, or use a string builder pattern")
        .severity(.warning)
        
        // Auto-fix: Convert += to .append()
        if op == "+=" {
            builder = addAppendFix(to: builder, node: node, right: right)
        }
        
        return builder.build()
    }
    
    private func addAppendFix(to builder: ViolationBuilder, node: SyntaxProtocol, right: ExprSyntax) -> ViolationBuilder {
        // Works for both InfixOperatorExprSyntax and BinaryOperatorExprSyntax (from SequenceExprSyntax)
        if let infixNode = node.as(InfixOperatorExprSyntax.self) {
            return builder.addStructuredFix(title: "Convert to .append()", kind: .refactor) { fix in
                fix.addEdit(TextEdit(
                    range: SourceRange(
                        start: self.sourceFile.location(of: infixNode.operator),
                        end: self.sourceFile.location(endOf: infixNode.operator)
                    ),
                    newText: ".append("
                ))
                fix.addEdit(TextEdit.insert(at: self.sourceFile.location(endOf: right), text: ")"))
            }
        } else if let binOp = node.as(BinaryOperatorExprSyntax.self) {
            return builder.addStructuredFix(title: "Convert to .append()", kind: .refactor) { fix in
                fix.addEdit(TextEdit(
                    range: SourceRange(
                        start: self.sourceFile.location(of: binOp),
                        end: self.sourceFile.location(endOf: binOp)
                    ),
                    newText: ".append("
                ))
                fix.addEdit(TextEdit.insert(at: self.sourceFile.location(endOf: right), text: ")"))
            }
        }
        return builder
    }

    private func isLikelyStringOperation(left: ExprSyntax, right: ExprSyntax) -> Bool {
        let rightDesc = right.trimmedDescription
        
        // Quick check: if right side is clearly numeric, skip
        if rightDesc.hasSuffix(".count") || 
           rightDesc.contains(".count ") ||
           Int(rightDesc) != nil {
            return false
        }
        
        // Skip if left side is a known output-building variable
        if isOutputBuildingVariable(left) { return false }

        // Check for string literals - this is the primary indicator
        if right.is(StringLiteralExprSyntax.self) { return true }
        if rightDesc.hasPrefix("\"") { return true }
        
        // Check for String() initializer
        if rightDesc.hasPrefix("String(") { return true }
        
        // Check for string interpolation
        if rightDesc.contains("\\(") { return true }
        
        // Check if left looks like a problematic string variable
        let identifierName = getIdentifierName(left).lowercased()
        let problematicPrefixes = ["str", "sql", "query"]
        let problematicSuffixes = ["string", "sql", "query"]
        
        if problematicPrefixes.contains(where: { identifierName.hasPrefix($0) }) { return true }
        if problematicSuffixes.contains(where: { identifierName.hasSuffix($0) }) { return true }

        return false
    }
    
    private func isOutputBuildingVariable(_ expr: ExprSyntax) -> Bool {
        let identifierName = getIdentifierName(expr)
        
        // Variables used for intentionally building output strings
        // These are legitimate O(n) operations for reporting/debugging/serialization
        let outputPatterns = ["desc", "result", "output", "text", "message", "html", 
                              "xml", "json", "content", "buffer", "log", "report",
                              "summary", "diff", "response", "body", "formatted",
                              "markdown", "regex", "pattern", "code", "snippet",
                              "source", "template", "script", "style"]
        
        return outputPatterns.contains(where: { identifierName.hasPrefix($0) }) ||
               outputPatterns.contains(where: { identifierName.hasSuffix($0) })
    }
    
    private func getIdentifierName(_ expr: ExprSyntax) -> String {
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text.lowercased()
        } else if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text.lowercased()
        }
        return expr.trimmedDescription.lowercased()
    }
}
