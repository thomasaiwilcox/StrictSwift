import Foundation
import SwiftSyntax

/// Detects patterns that commonly cause flaky tests
public final class FlakyTestPatternRule: Rule {
    public var id: String { "flaky_test_pattern" }
    public var name: String { "Flaky Test Pattern" }
    public var description: String { "Detects patterns that commonly cause flaky or non-deterministic tests" }
    public var category: RuleCategory { .testing }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = FlakyTestPatternVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        let path = sourceFile.url.path.lowercased()
        return sourceFile.url.pathExtension == "swift" &&
               (path.contains("test") || path.contains("spec"))
    }
}

/// Syntax visitor that finds flaky test patterns
private final class FlakyTestPatternVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let functionName = extractFunctionName(from: node.calledExpression)
        let fullExpr = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        
        // Check for Date() comparisons (timing-dependent)
        if functionName == "Date" || fullExpr == "Date()" {
            // Check if it's being used in a comparison context
            if isInComparisonContext(node) {
                let location = sourceFile.location(of: node)
                violations.append(
                    ViolationBuilder(
                        ruleId: "flaky_test_pattern",
                        category: .testing,
                        location: location
                    )
                    .message("Date() comparisons in tests can be timing-dependent and flaky")
                    .suggestFix("Use a fixed date or mock the date provider for deterministic tests")
                    .severity(.warning)
                    .build()
                )
            }
        }
        
        // Check for unseeded random (non-deterministic)
        if isRandomCall(functionName, fullExpr: fullExpr) {
            let location = sourceFile.location(of: node)
            violations.append(
                ViolationBuilder(
                    ruleId: "flaky_test_pattern",
                    category: .testing,
                    location: location
                )
                .message("Unseeded random values in tests cause non-deterministic behavior")
                .suggestFix("Use a seeded random generator or fixed values for reproducible tests")
                .severity(.warning)
                .build()
            )
        }
        
        // Check for network calls without mocking indicators
        if isNetworkCall(functionName, fullExpr: fullExpr) {
            let location = sourceFile.location(of: node)
            violations.append(
                ViolationBuilder(
                    ruleId: "flaky_test_pattern",
                    category: .testing,
                    location: location
                )
                .message("Real network calls in tests can be slow and flaky")
                .suggestFix("Use URLProtocol mocking or a mock HTTP client")
                .severity(.info)
                .build()
            )
        }
        
        // Check for Task.yield or other race-condition-prone patterns
        if functionName == "yield" && fullExpr.contains("Task") {
            let location = sourceFile.location(of: node)
            violations.append(
                ViolationBuilder(
                    ruleId: "flaky_test_pattern",
                    category: .testing,
                    location: location
                )
                .message("Task.yield() in tests can cause race conditions")
                .suggestFix("Use proper synchronization or expectations instead of yielding")
                .severity(.warning)
                .build()
            )
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let memberName = node.declName.baseName.text
        
        // Check for timeIntervalSinceNow or similar timing-dependent properties
        let timingProperties = ["timeIntervalSinceNow", "timeIntervalSince1970", "timeIntervalSinceReferenceDate"]
        
        if timingProperties.contains(memberName) {
            // Check if being used in assertion
            if isInAssertionContext(node) {
                let location = sourceFile.location(of: node)
                violations.append(
                    ViolationBuilder(
                        ruleId: "flaky_test_pattern",
                        category: .testing,
                        location: location
                    )
                    .message("Time interval comparisons can be flaky due to timing variations")
                    .suggestFix("Use a tolerance in comparisons or mock the time source")
                    .severity(.warning)
                    .build()
                )
            }
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        let opText = node.operator.description.trimmingCharacters(in: .whitespaces)
        
        // Check for equality comparisons on floating point from timing
        if opText == "==" || opText == "!=" {
            // Check if comparing Date or TimeInterval
            let leftText = node.leftOperand.description
            let rightText = node.rightOperand.description
            
            if containsTimingType(leftText) || containsTimingType(rightText) {
                let location = sourceFile.location(of: node)
                violations.append(
                    ViolationBuilder(
                        ruleId: "flaky_test_pattern",
                        category: .testing,
                        location: location
                    )
                    .message("Exact equality comparison on time values is fragile")
                    .suggestFix("Use XCTAssertEqual with accuracy or compare with tolerance")
                    .severity(.warning)
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
    
    private func isInComparisonContext(_ node: SyntaxProtocol) -> Bool {
        var current: Syntax? = node._syntaxNode
        while let parent = current?.parent {
            if let infixOp = parent.as(InfixOperatorExprSyntax.self) {
                let op = infixOp.operator.description.trimmingCharacters(in: .whitespaces)
                if ["==", "!=", "<", ">", "<=", ">="].contains(op) {
                    return true
                }
            }
            // Check if in XCTAssert call
            if let funcCall = parent.as(FunctionCallExprSyntax.self) {
                let name = extractFunctionName(from: funcCall.calledExpression)
                if name.hasPrefix("XCTAssert") || name == "expect" || name == "require" {
                    return true
                }
            }
            current = parent
        }
        return false
    }
    
    private func isInAssertionContext(_ node: SyntaxProtocol) -> Bool {
        var current: Syntax? = node._syntaxNode
        while let parent = current?.parent {
            if let funcCall = parent.as(FunctionCallExprSyntax.self) {
                let name = extractFunctionName(from: funcCall.calledExpression)
                if name.hasPrefix("XCTAssert") || name == "expect" || name == "require" {
                    return true
                }
            }
            current = parent
        }
        return false
    }
    
    private func isRandomCall(_ functionName: String, fullExpr: String) -> Bool {
        let randomFunctions = ["random", "randomElement", "shuffled"]
        
        // Int.random, Double.random, etc.
        if randomFunctions.contains(functionName) {
            // Check if it has a generator parameter (seeded)
            if fullExpr.contains("using:") {
                return false // Seeded random is fine
            }
            return true
        }
        
        // UUID() is also non-deterministic
        if functionName == "UUID" && !fullExpr.contains("uuidString:") {
            return true
        }
        
        return false
    }
    
    private func isNetworkCall(_ functionName: String, fullExpr: String) -> Bool {
        // URLSession data tasks
        if fullExpr.contains("URLSession") {
            let networkMethods = ["data", "dataTask", "download", "uploadTask"]
            return networkMethods.contains(functionName)
        }
        
        // Alamofire, etc.
        let networkIndicators = ["request", "fetch", "get", "post", "put", "delete", "patch"]
        if networkIndicators.contains(functionName.lowercased()) {
            // Try to determine if this is actually network-related
            if fullExpr.contains("URL") || fullExpr.contains("http") {
                return true
            }
        }
        
        return false
    }
    
    private func containsTimingType(_ text: String) -> Bool {
        let timingIndicators = [
            "Date", "TimeInterval", "timeInterval", "timestamp",
            "duration", "elapsed", "seconds", "milliseconds"
        ]
        for indicator in timingIndicators {
            if text.contains(indicator) {
                return true
            }
        }
        return false
    }
}
