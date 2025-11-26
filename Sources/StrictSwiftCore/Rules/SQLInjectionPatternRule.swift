import Foundation
import SwiftSyntax

/// Detects potential SQL injection vulnerabilities from string interpolation
public final class SQLInjectionPatternRule: Rule {
    public var id: String { "sql_injection_pattern" }
    public var name: String { "SQL Injection Pattern" }
    public var description: String { "Detects string interpolation in SQL queries. Requires SQL structure (keyword + clause like SELECT...FROM, UPDATE...SET) to avoid false positives on Swift keywords" }
    public var category: RuleCategory { .security }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = SQLInjectionVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds SQL injection patterns
private final class SQLInjectionVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// SQL keywords that indicate a query
    private static let sqlKeywords: [String] = [
        "SELECT", "INSERT", "UPDATE", "DELETE", "DROP", "CREATE", "ALTER",
        "TRUNCATE", "MERGE", "REPLACE", "EXEC", "EXECUTE", "UNION"
    ]
    
    /// SQL clause keywords that often have user input
    private static let sqlClauseKeywords: [String] = [
        "WHERE", "AND", "OR", "SET", "VALUES", "INTO", "FROM", "JOIN",
        "ORDER BY", "GROUP BY", "HAVING", "LIMIT", "OFFSET"
    ]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        // Check if this string looks like SQL
        guard containsSQLKeywords(node) else {
            return .visitChildren
        }
        
        // Check for string interpolation in SQL
        if hasInterpolation(node) {
            let location = sourceFile.location(of: node)
            
            violations.append(
                ViolationBuilder(
                    ruleId: "sql_injection_pattern",
                    category: .security,
                    location: location
                )
                .message("Potential SQL injection: string interpolation in SQL query")
                .suggestFix("Use parameterized queries or prepared statements instead of string interpolation")
                .severity(.error)
                .build()
            )
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for common database query functions
        let functionName = extractFunctionName(from: node.calledExpression).lowercased()
        
        let queryFunctions = [
            "execute", "query", "rawquery", "execsql", "rawsql",
            "raw", "execute", "performquery", "runsql", "sql"
        ]
        
        guard queryFunctions.contains(where: { functionName.contains($0) }) else {
            return .visitChildren
        }
        
        // Check arguments for interpolated SQL
        for argument in node.arguments {
            if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                if hasInterpolation(stringLiteral) {
                    let location = sourceFile.location(of: node)
                    
                    violations.append(
                        ViolationBuilder(
                            ruleId: "sql_injection_pattern",
                            category: .security,
                            location: location
                        )
                        .message("Potential SQL injection: interpolated string passed to database query function")
                        .suggestFix("Use parameterized queries with placeholders (?, $1, :name) instead")
                        .severity(.error)
                        .build()
                    )
                    break
                }
            }
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        // Check for SQL query assignments with interpolation
        guard let identifier = node.pattern.as(IdentifierPatternSyntax.self) else {
            return .visitChildren
        }
        
        let varName = identifier.identifier.text.lowercased()
        let sqlVarNames = ["query", "sql", "statement", "sqlquery", "sqlstatement", "rawsql"]
        
        guard sqlVarNames.contains(where: { varName.contains($0) }) else {
            return .visitChildren
        }
        
        // Check if assigned an interpolated string
        if let initializer = node.initializer,
           let stringLiteral = initializer.value.as(StringLiteralExprSyntax.self) {
            if hasInterpolation(stringLiteral) {
                let location = sourceFile.location(of: node)
                
                violations.append(
                    ViolationBuilder(
                        ruleId: "sql_injection_pattern",
                        category: .security,
                        location: location
                    )
                    .message("Potential SQL injection: SQL variable contains interpolated values")
                    .suggestFix("Use parameterized queries with placeholders instead of string interpolation")
                    .severity(.error)
                    .build()
                )
            }
        }
        
        return .visitChildren
    }
    
    private func extractFunctionName(from expr: ExprSyntax) -> String {
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
        return ""
    }
    
    /// Checks if a string looks like SQL by requiring BOTH a main keyword AND a clause keyword
    /// at word boundaries. This prevents false positives on Swift keywords like `.union()` or `update`.
    private func containsSQLKeywords(_ stringLiteral: StringLiteralExprSyntax) -> Bool {
        let content = extractStringContent(from: stringLiteral)
        
        // Check for main SQL keyword at word boundary
        guard hasSQLKeywordAtWordBoundary(content, keywords: Self.sqlKeywords) else {
            return false
        }
        
        // Also require a clause keyword to confirm SQL structure
        // This prevents false positives on strings that happen to contain "UPDATE" or "UNION"
        return hasSQLKeywordAtWordBoundary(content, keywords: Self.sqlClauseKeywords)
    }
    
    /// Checks if any of the keywords appear at word boundaries in the content
    private func hasSQLKeywordAtWordBoundary(_ content: String, keywords: [String]) -> Bool {
        let uppercased = content.uppercased()
        
        for keyword in keywords {
            // Build a pattern that requires word boundaries
            // Word boundary = start of string, whitespace, quote, paren, or comma
            let escapedKeyword = NSRegularExpression.escapedPattern(for: keyword)
            let pattern = "(?:^|[\\s\"'(,])(\(escapedKeyword))(?:[\\s\"'),;]|$)"
            
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            
            let range = NSRange(uppercased.startIndex..., in: uppercased)
            if regex.firstMatch(in: uppercased, options: [], range: range) != nil {
                return true
            }
        }
        
        return false
    }
    
    private func hasInterpolation(_ stringLiteral: StringLiteralExprSyntax) -> Bool {
        for segment in stringLiteral.segments {
            if segment.is(ExpressionSegmentSyntax.self) {
                return true
            }
        }
        return false
    }
    
    private func extractStringContent(from node: StringLiteralExprSyntax) -> String {
        return node.segments.compactMap { segment -> String? in
            if let stringSegment = segment.as(StringSegmentSyntax.self) {
                return stringSegment.content.text
            }
            return nil
        }.joined()
    }
}
