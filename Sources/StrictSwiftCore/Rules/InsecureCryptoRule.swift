import Foundation
import SwiftSyntax

/// Detects usage of insecure or deprecated cryptographic algorithms and APIs
public final class InsecureCryptoRule: Rule {
    public var id: String { "insecure_crypto" }
    public var name: String { "Insecure Cryptography" }
    public var description: String { "Detects usage of weak or deprecated cryptographic algorithms like MD5, SHA1, and insecure cipher modes" }
    public var category: RuleCategory { .security }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = InsecureCryptoVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Insecure crypto pattern definition
private struct InsecureCryptoPattern {
    let pattern: String
    let message: String
    let severity: DiagnosticSeverity
    let suggestion: String
}

/// Syntax visitor that finds insecure cryptographic usage
private final class InsecureCryptoVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// Insecure function/type names to detect
    private static let insecurePatterns: [InsecureCryptoPattern] = [
        // MD5 - Vulnerable to collision attacks
        InsecureCryptoPattern(
            pattern: "CC_MD5",
            message: "MD5 is cryptographically broken and should not be used for security purposes",
            severity: .error,
            suggestion: "Use SHA-256 or higher (CC_SHA256, SHA256, CryptoKit.SHA256)"
        ),
        InsecureCryptoPattern(
            pattern: "MD5",
            message: "MD5 is cryptographically broken and should not be used for security purposes",
            severity: .error,
            suggestion: "Use SHA-256 or higher (CryptoKit.SHA256)"
        ),
        InsecureCryptoPattern(
            pattern: "Insecure.MD5",
            message: "Insecure.MD5 is explicitly marked insecure - use SHA256 or higher",
            severity: .error,
            suggestion: "Use SHA256 from CryptoKit for secure hashing"
        ),
        
        // SHA1 - Vulnerable to collision attacks
        InsecureCryptoPattern(
            pattern: "CC_SHA1",
            message: "SHA-1 is deprecated and vulnerable to collision attacks",
            severity: .error,
            suggestion: "Use SHA-256 or higher (CC_SHA256, SHA256, CryptoKit.SHA256)"
        ),
        InsecureCryptoPattern(
            pattern: "SHA1",
            message: "SHA-1 is deprecated and vulnerable to collision attacks",
            severity: .error,
            suggestion: "Use SHA256 or higher from CryptoKit"
        ),
        InsecureCryptoPattern(
            pattern: "Insecure.SHA1",
            message: "Insecure.SHA1 is explicitly marked insecure - use SHA256 or higher",
            severity: .error,
            suggestion: "Use SHA256 from CryptoKit for secure hashing"
        ),
        
        // DES - Too weak for modern use
        InsecureCryptoPattern(
            pattern: "kCCAlgorithmDES",
            message: "DES encryption is too weak for modern security requirements",
            severity: .error,
            suggestion: "Use AES-256 encryption (kCCAlgorithmAES, CryptoKit.AES)"
        ),
        InsecureCryptoPattern(
            pattern: "kCCAlgorithm3DES",
            message: "3DES is deprecated - use AES instead",
            severity: .warning,
            suggestion: "Use AES-256 encryption (kCCAlgorithmAES, CryptoKit.AES)"
        ),
        
        // ECB mode - Patterns are visible
        InsecureCryptoPattern(
            pattern: "kCCOptionECBMode",
            message: "ECB mode reveals patterns in encrypted data - use CBC or GCM",
            severity: .error,
            suggestion: "Use CBC mode with random IV or GCM for authenticated encryption"
        ),
        
        // RC4 - Broken stream cipher
        InsecureCryptoPattern(
            pattern: "kCCAlgorithmRC4",
            message: "RC4 is cryptographically broken and should never be used",
            severity: .error,
            suggestion: "Use AES-GCM or ChaCha20-Poly1305 for stream encryption"
        ),
        
        // Blowfish - Obsolete
        InsecureCryptoPattern(
            pattern: "kCCAlgorithmBlowfish",
            message: "Blowfish is obsolete - use AES instead",
            severity: .warning,
            suggestion: "Use AES-256 encryption (kCCAlgorithmAES, CryptoKit.AES)"
        ),
        
        // Weak key sizes
        InsecureCryptoPattern(
            pattern: "kCCKeySizeAES128",
            message: "AES-128 provides weaker security than AES-256",
            severity: .info,
            suggestion: "Consider using AES-256 for stronger security (kCCKeySizeAES256)"
        ),
        
        // Deprecated SecKey functions
        InsecureCryptoPattern(
            pattern: "SecKeyEncrypt",
            message: "SecKeyEncrypt is deprecated - use SecKeyCreateEncryptedData",
            severity: .warning,
            suggestion: "Use SecKeyCreateEncryptedData with appropriate algorithm"
        ),
        InsecureCryptoPattern(
            pattern: "SecKeyDecrypt",
            message: "SecKeyDecrypt is deprecated - use SecKeyCreateDecryptedData",
            severity: .warning,
            suggestion: "Use SecKeyCreateDecryptedData with appropriate algorithm"
        ),
        
        // Insecure random
        InsecureCryptoPattern(
            pattern: "arc4random",
            message: "arc4random may not be cryptographically secure on all platforms",
            severity: .info,
            suggestion: "Use SecRandomCopyBytes for cryptographic random numbers"
        ),
        InsecureCryptoPattern(
            pattern: "srand",
            message: "srand/rand are not cryptographically secure",
            severity: .error,
            suggestion: "Use SecRandomCopyBytes for cryptographic random numbers"
        ),
        InsecureCryptoPattern(
            pattern: "random()",
            message: "random() is not cryptographically secure",
            severity: .error,
            suggestion: "Use SecRandomCopyBytes for cryptographic random numbers"
        ),
        
        // Hardcoded IV
        InsecureCryptoPattern(
            pattern: "static.*iv",
            message: "Static IV defeats the purpose of initialization vectors",
            severity: .error,
            suggestion: "Generate a random IV for each encryption operation"
        ),
    ]
    
    /// Import names that indicate crypto usage (for context)
    private var hasCryptoImport = false

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if file imports crypto libraries
        let importPath = node.path.description.trimmingCharacters(in: .whitespaces)
        if importPath.contains("CommonCrypto") || 
           importPath.contains("CryptoKit") ||
           importPath.contains("Security") {
            hasCryptoImport = true
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        checkForInsecureCrypto(identifier: node.baseName.text, node: Syntax(node))
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Check the full member access chain
        let fullAccess = node.description.trimmingCharacters(in: .whitespaces)
        checkForInsecureCrypto(identifier: fullAccess, node: Syntax(node))
        
        // Also check just the member name
        let memberName = node.declName.baseName.text
        checkForInsecureCrypto(identifier: memberName, node: Syntax(node))
        
        return .visitChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Get the function name being called
        let functionName = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        checkForInsecureCrypto(identifier: functionName, node: Syntax(node))
        return .visitChildren
    }
    
    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        // Check for static IV patterns
        guard let identifier = node.pattern.as(IdentifierPatternSyntax.self) else {
            return .visitChildren
        }
        
        let varName = identifier.identifier.text.lowercased()
        
        // Check for hardcoded IV
        if (varName.contains("iv") || varName == "initializationvector") {
            // Check if it's a static/constant with a literal value
            if let initializer = node.initializer,
               isDataOrArrayLiteral(initializer.value) {
                let location = sourceFile.location(of: node)
                
                violations.append(
                    ViolationBuilder(
                        ruleId: "insecure_crypto",
                        category: .security,
                        location: location
                    )
                    .message("Hardcoded initialization vector (IV) detected - IVs must be random")
                    .suggestFix("Generate a random IV for each encryption operation using SecRandomCopyBytes")
                    .severity(.error)
                    .build()
                )
            }
        }
        
        return .visitChildren
    }
    
    private func checkForInsecureCrypto(identifier: String, node: Syntax) {
        for pattern in Self.insecurePatterns {
            // Use case-sensitive matching for most patterns
            if identifier.contains(pattern.pattern) ||
               (pattern.pattern.contains(".*") && matchesWildcard(identifier, pattern: pattern.pattern)) {
                let location = sourceFile.location(of: node)
                
                violations.append(
                    ViolationBuilder(
                        ruleId: "insecure_crypto",
                        category: .security,
                        location: location
                    )
                    .message(pattern.message)
                    .suggestFix(pattern.suggestion)
                    .severity(pattern.severity)
                    .build()
                )
                return // Only report once per node
            }
        }
    }
    
    private func matchesWildcard(_ string: String, pattern: String) -> Bool {
        // Convert simple wildcard pattern to regex
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }
    
    private func isDataOrArrayLiteral(_ expr: ExprSyntax) -> Bool {
        // Check for Data literal
        if let funcCall = expr.as(FunctionCallExprSyntax.self) {
            let calledExpr = funcCall.calledExpression.description
            if calledExpr.contains("Data") || calledExpr.contains("[UInt8]") {
                return true
            }
        }
        
        // Check for array literal
        if expr.is(ArrayExprSyntax.self) {
            return true
        }
        
        return false
    }
}
