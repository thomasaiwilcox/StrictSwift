import Foundation
import SwiftSyntax

/// Detects excessive timeouts and sleep calls in test code
public final class AsyncTestTimeoutRule: Rule {
    public var id: String { "async_test_timeout" }
    public var name: String { "Async Test Timeout" }
    public var description: String { "Detects excessive timeouts and sleep calls in test code that slow down test suites" }
    public var category: RuleCategory { .testing }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = AsyncTestTimeoutVisitor(sourceFile: sourceFile)
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

/// Syntax visitor that finds timeout and sleep issues in tests
private final class AsyncTestTimeoutVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// Maximum recommended sleep duration in seconds
    private static let maxSleepSeconds: Double = 5.0
    /// Maximum recommended timeout duration in seconds
    private static let maxTimeoutSeconds: Double = 30.0

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let functionName = extractFunctionName(from: node.calledExpression)
        let fullExpr = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        
        // Check for sleep calls
        if isSleepCall(functionName, fullExpr: fullExpr) {
            if let duration = extractSleepDuration(from: node) {
                if duration > Self.maxSleepSeconds {
                    let location = sourceFile.location(of: node)
                    violations.append(
                        ViolationBuilder(
                            ruleId: "async_test_timeout",
                            category: .testing,
                            location: location
                        )
                        .message("Sleep of \(duration)s in test is excessive (max recommended: \(Self.maxSleepSeconds)s)")
                        .suggestFix("Use expectations/waiters or reduce sleep duration")
                        .severity(.warning)
                        .build()
                    )
                }
            } else {
                // Can't determine duration, still flag it
                let location = sourceFile.location(of: node)
                violations.append(
                    ViolationBuilder(
                        ruleId: "async_test_timeout",
                        category: .testing,
                        location: location
                    )
                    .message("Sleep in test code - consider using expectations/waiters instead")
                    .suggestFix("Replace sleep with XCTestExpectation or proper async/await patterns")
                    .severity(.info)
                    .build()
                )
            }
        }
        
        // Check for XCTestExpectation timeout
        if functionName == "wait" && fullExpr.contains("wait(for:") {
            if let timeout = extractWaitTimeout(from: node) {
                if timeout > Self.maxTimeoutSeconds {
                    let location = sourceFile.location(of: node)
                    violations.append(
                        ViolationBuilder(
                            ruleId: "async_test_timeout",
                            category: .testing,
                            location: location
                        )
                        .message("Expectation timeout of \(timeout)s is excessive (max recommended: \(Self.maxTimeoutSeconds)s)")
                        .suggestFix("Reduce timeout or investigate why test needs such long waits")
                        .severity(.warning)
                        .build()
                    )
                }
            }
        }
        
        // Check for DispatchQueue.asyncAfter
        if functionName == "asyncAfter" {
            let location = sourceFile.location(of: node)
            violations.append(
                ViolationBuilder(
                    ruleId: "async_test_timeout",
                    category: .testing,
                    location: location
                )
                .message("DispatchQueue.asyncAfter in tests can cause flaky behavior")
                .suggestFix("Use XCTestExpectation.fulfill() or async/await instead")
                .severity(.warning)
                .build()
            )
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
    
    private func isSleepCall(_ functionName: String, fullExpr: String) -> Bool {
        // Thread.sleep, sleep(), usleep(), Task.sleep
        let sleepFunctions = ["sleep", "usleep", "nanosleep"]
        if sleepFunctions.contains(functionName) {
            return true
        }
        if fullExpr.contains("Thread.sleep") || fullExpr.contains("Task.sleep") {
            return true
        }
        return false
    }
    
    private func extractSleepDuration(from node: FunctionCallExprSyntax) -> Double? {
        let fullExpr = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        
        for argument in node.arguments {
            // Look for the duration argument
            let label = argument.label?.text ?? ""
            let expr = argument.expression
            
            // Task.sleep(nanoseconds:)
            if label == "nanoseconds" || fullExpr.contains("nanoseconds") {
                if let value = extractNumericValue(from: expr) {
                    return value / 1_000_000_000.0
                }
            }
            
            // Task.sleep(for:) with Duration
            if label == "for" {
                if let value = extractDurationValue(from: expr) {
                    return value
                }
            }
            
            // Thread.sleep(forTimeInterval:)
            if label == "forTimeInterval" {
                if let value = extractNumericValue(from: expr) {
                    return value
                }
            }
            
            // Plain sleep(seconds) or usleep(microseconds)
            if label.isEmpty {
                if let value = extractNumericValue(from: expr) {
                    let functionName = extractFunctionName(from: node.calledExpression)
                    if functionName == "usleep" {
                        return value / 1_000_000.0
                    }
                    return value
                }
            }
        }
        
        return nil
    }
    
    private func extractWaitTimeout(from node: FunctionCallExprSyntax) -> Double? {
        for argument in node.arguments {
            let label = argument.label?.text ?? ""
            
            if label == "timeout" {
                if let value = extractNumericValue(from: argument.expression) {
                    return value
                }
            }
        }
        return nil
    }
    
    private func extractNumericValue(from expr: ExprSyntax) -> Double? {
        // Integer literal
        if let intLiteral = expr.as(IntegerLiteralExprSyntax.self) {
            return Double(intLiteral.literal.text)
        }
        
        // Float literal
        if let floatLiteral = expr.as(FloatLiteralExprSyntax.self) {
            return Double(floatLiteral.literal.text)
        }
        
        // Underscore-separated literals (1_000_000)
        if let intLiteral = expr.as(IntegerLiteralExprSyntax.self) {
            let text = intLiteral.literal.text.replacingOccurrences(of: "_", with: "")
            return Double(text)
        }
        
        return nil
    }
    
    private func extractDurationValue(from expr: ExprSyntax) -> Double? {
        // Handle .seconds(X), .milliseconds(X), etc.
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            // Check if it's a Duration call
            if let funcCall = memberAccess.base?.as(FunctionCallExprSyntax.self) {
                return extractDurationValue(from: ExprSyntax(funcCall))
            }
        }
        
        if let funcCall = expr.as(FunctionCallExprSyntax.self) {
            let functionName = extractFunctionName(from: funcCall.calledExpression)
            
            for argument in funcCall.arguments {
                if let value = extractNumericValue(from: argument.expression) {
                    switch functionName {
                    case "seconds":
                        return value
                    case "milliseconds":
                        return value / 1000.0
                    case "microseconds":
                        return value / 1_000_000.0
                    case "nanoseconds":
                        return value / 1_000_000_000.0
                    default:
                        break
                    }
                }
            }
        }
        
        return nil
    }
}
