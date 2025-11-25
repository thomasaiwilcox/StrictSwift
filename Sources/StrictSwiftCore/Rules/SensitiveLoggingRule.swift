import Foundation
import SwiftSyntax

/// Detects logging of sensitive data like passwords, tokens, and PII
public final class SensitiveLoggingRule: Rule {
    public var id: String { "sensitive_logging" }
    public var name: String { "Sensitive Data Logging" }
    public var description: String { "Detects logging of sensitive data like passwords, tokens, API keys, and PII" }
    public var category: RuleCategory { .security }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = SensitiveLoggingVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds sensitive data being logged
private final class SensitiveLoggingVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// Logging function names to check
    private static let loggingFunctions: Set<String> = [
        "print", "debugPrint", "dump",
        "NSLog",
        "os_log", "Logger", "log",
        "DDLog", "DDLogDebug", "DDLogInfo", "DDLogWarn", "DDLogError", "DDLogVerbose",
        "logDebug", "logInfo", "logWarning", "logError",
        "debug", "info", "warning", "error", "verbose", "trace"
    ]
    
    /// Sensitive variable name patterns (lowercase for comparison)
    private static let sensitivePatterns: [(pattern: String, type: String)] = [
        // Authentication
        ("password", "password"),
        ("passwd", "password"),
        ("pwd", "password"),
        ("secret", "secret"),
        ("apikey", "API key"),
        ("api_key", "API key"),
        ("apitoken", "API token"),
        ("api_token", "API token"),
        ("authtoken", "auth token"),
        ("auth_token", "auth token"),
        ("accesstoken", "access token"),
        ("access_token", "access token"),
        ("refreshtoken", "refresh token"),
        ("refresh_token", "refresh token"),
        ("bearer", "bearer token"),
        ("jwt", "JWT token"),
        ("sessionid", "session ID"),
        ("session_id", "session ID"),
        ("sessiontoken", "session token"),
        ("privatekey", "private key"),
        ("private_key", "private key"),
        ("secretkey", "secret key"),
        ("secret_key", "secret key"),
        ("credentials", "credentials"),
        ("oauth", "OAuth token"),
        
        // PII - Personally Identifiable Information
        ("ssn", "SSN"),
        ("socialsecurity", "social security number"),
        ("social_security", "social security number"),
        ("taxid", "tax ID"),
        ("tax_id", "tax ID"),
        ("creditcard", "credit card"),
        ("credit_card", "credit card"),
        ("cardnumber", "card number"),
        ("card_number", "card number"),
        ("cvv", "CVV"),
        ("cvc", "CVC"),
        ("accountnumber", "account number"),
        ("account_number", "account number"),
        ("routingnumber", "routing number"),
        ("routing_number", "routing number"),
        ("driverslicense", "driver's license"),
        ("drivers_license", "driver's license"),
        ("passport", "passport number"),
        ("dateofbirth", "date of birth"),
        ("date_of_birth", "date of birth"),
        ("dob", "date of birth"),
        
        // Healthcare (HIPAA)
        ("medicalrecord", "medical record"),
        ("medical_record", "medical record"),
        ("healthrecord", "health record"),
        ("health_record", "health record"),
        ("diagnosis", "diagnosis"),
        ("prescription", "prescription"),
        
        // Financial
        ("bankaccount", "bank account"),
        ("bank_account", "bank account"),
        ("iban", "IBAN"),
        ("swift", "SWIFT code"),
        ("pin", "PIN"),
    ]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Get the function name being called
        let functionName = extractFunctionName(from: node.calledExpression)
        
        // Check if this is a logging function
        guard Self.loggingFunctions.contains(functionName) ||
              isLoggerMethod(node.calledExpression) else {
            return .visitChildren
        }
        
        // Check arguments for sensitive data
        for argument in node.arguments {
            checkArgumentForSensitiveData(argument.expression, in: node)
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
    
    private func isLoggerMethod(_ expr: ExprSyntax) -> Bool {
        // Check for Logger.info(), logger.debug(), etc.
        guard let memberAccess = expr.as(MemberAccessExprSyntax.self) else {
            return false
        }
        
        let methodName = memberAccess.declName.baseName.text.lowercased()
        let logMethods = ["debug", "info", "warning", "error", "critical", "trace", "verbose", "log", "notice", "fault"]
        
        return logMethods.contains(methodName)
    }
    
    private func checkArgumentForSensitiveData(_ expr: ExprSyntax, in callNode: FunctionCallExprSyntax) {
        // Check for direct variable references
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            let varName = declRef.baseName.text.lowercased()
            if let sensitiveType = findSensitivePattern(in: varName) {
                reportViolation(
                    at: callNode,
                    variableName: declRef.baseName.text,
                    sensitiveType: sensitiveType
                )
            }
        }
        
        // Check for member access (object.password)
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            let memberName = memberAccess.declName.baseName.text.lowercased()
            if let sensitiveType = findSensitivePattern(in: memberName) {
                reportViolation(
                    at: callNode,
                    variableName: memberAccess.declName.baseName.text,
                    sensitiveType: sensitiveType
                )
            }
        }
        
        // Check string interpolation
        if let stringLiteral = expr.as(StringLiteralExprSyntax.self) {
            checkStringInterpolation(stringLiteral, in: callNode)
        }
        
        // Recursively check function call arguments
        if let funcCall = expr.as(FunctionCallExprSyntax.self) {
            for arg in funcCall.arguments {
                checkArgumentForSensitiveData(arg.expression, in: callNode)
            }
        }
        
        // Check ternary expressions
        if let ternary = expr.as(TernaryExprSyntax.self) {
            checkArgumentForSensitiveData(ternary.thenExpression, in: callNode)
            checkArgumentForSensitiveData(ternary.elseExpression, in: callNode)
        }
    }
    
    private func checkStringInterpolation(_ stringLiteral: StringLiteralExprSyntax, in callNode: FunctionCallExprSyntax) {
        for segment in stringLiteral.segments {
            if let interpolation = segment.as(ExpressionSegmentSyntax.self) {
                // Check the interpolated expression
                for labeledExpr in interpolation.expressions {
                    checkInterpolatedExpression(labeledExpr.expression, in: callNode)
                }
            }
        }
    }
    
    private func checkInterpolatedExpression(_ expr: ExprSyntax, in callNode: FunctionCallExprSyntax) {
        // Direct variable in interpolation
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            let varName = declRef.baseName.text.lowercased()
            if let sensitiveType = findSensitivePattern(in: varName) {
                reportViolation(
                    at: callNode,
                    variableName: declRef.baseName.text,
                    sensitiveType: sensitiveType
                )
            }
        }
        
        // Member access in interpolation
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            let memberName = memberAccess.declName.baseName.text.lowercased()
            if let sensitiveType = findSensitivePattern(in: memberName) {
                reportViolation(
                    at: callNode,
                    variableName: memberAccess.declName.baseName.text,
                    sensitiveType: sensitiveType
                )
            }
            // Recursively check base expression
            checkInterpolatedExpression(memberAccess.base!, in: callNode)
        }
    }
    
    private func findSensitivePattern(in varName: String) -> String? {
        for (pattern, type) in Self.sensitivePatterns {
            if varName.contains(pattern) {
                return type
            }
        }
        return nil
    }
    
    private func reportViolation(at node: FunctionCallExprSyntax, variableName: String, sensitiveType: String) {
        let location = sourceFile.location(of: node)
        
        violations.append(
            ViolationBuilder(
                ruleId: "sensitive_logging",
                category: .security,
                location: location
            )
            .message("Logging \(sensitiveType) ('\(variableName)') - sensitive data should not be logged")
            .suggestFix("Remove sensitive data from logs or use redaction: '\\(\(variableName), privacy: .private)' with OSLog")
            .severity(.error)
            .build()
        )
    }
}
