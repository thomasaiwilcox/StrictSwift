import Foundation
import SwiftSyntax

/// Detects hardcoded secrets, API keys, tokens, and passwords in source code
public final class HardcodedSecretsRule: Rule {
    public var id: String { "hardcoded_secrets" }
    public var name: String { "Hardcoded Secrets" }
    public var description: String { "Detects hardcoded secrets, API keys, and sensitive credentials in source code" }
    public var category: RuleCategory { .security }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = HardcodedSecretsVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Patterns for detecting various types of secrets
private struct SecretPattern {
    let name: String
    let regex: NSRegularExpression
    let message: String
    
    init(name: String, pattern: String, message: String) {
        self.name = name
        // swiftlint:disable:next force_try
        self.regex = try! NSRegularExpression(pattern: pattern, options: [])
        self.message = message
    }
}

/// Syntax visitor that finds hardcoded secrets
private final class HardcodedSecretsVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// Known secret patterns to detect
    private static let secretPatterns: [SecretPattern] = [
        // AWS Access Key ID
        SecretPattern(
            name: "AWS Access Key",
            pattern: #"AKIA[0-9A-Z]{16}"#,
            message: "Hardcoded AWS Access Key ID detected"
        ),
        // AWS Secret Access Key (40 character base64)
        SecretPattern(
            name: "AWS Secret Key",
            pattern: #"(?<![A-Za-z0-9/+=])[A-Za-z0-9/+=]{40}(?![A-Za-z0-9/+=])"#,
            message: "Potential AWS Secret Access Key detected (40-char base64)"
        ),
        // GitHub Personal Access Token (classic)
        SecretPattern(
            name: "GitHub Token",
            pattern: #"ghp_[A-Za-z0-9]{36}"#,
            message: "Hardcoded GitHub Personal Access Token detected"
        ),
        // GitHub Fine-grained Token
        SecretPattern(
            name: "GitHub Fine-grained Token",
            pattern: #"github_pat_[A-Za-z0-9]{22}_[A-Za-z0-9]{59}"#,
            message: "Hardcoded GitHub Fine-grained Personal Access Token detected"
        ),
        // Slack Token
        SecretPattern(
            name: "Slack Token",
            pattern: #"xox[baprs]-[0-9]{10,13}-[0-9]{10,13}[a-zA-Z0-9-]*"#,
            message: "Hardcoded Slack token detected"
        ),
        // Stripe API Key
        SecretPattern(
            name: "Stripe Key",
            pattern: #"sk_live_[0-9a-zA-Z]{24}"#,
            message: "Hardcoded Stripe live API key detected"
        ),
        // Stripe Test Key (lower severity)
        SecretPattern(
            name: "Stripe Test Key",
            pattern: #"sk_test_[0-9a-zA-Z]{24}"#,
            message: "Hardcoded Stripe test API key detected"
        ),
        // Generic API Key pattern
        SecretPattern(
            name: "Generic API Key",
            pattern: #"(?i)(api[_-]?key|apikey)\s*[=:]\s*['\"][A-Za-z0-9]{20,}['\"]"#,
            message: "Potential hardcoded API key detected"
        ),
        // Private Key block
        SecretPattern(
            name: "Private Key",
            pattern: #"-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"#,
            message: "Hardcoded private key detected"
        ),
        // JWT Token
        SecretPattern(
            name: "JWT Token",
            pattern: #"eyJ[A-Za-z0-9-_]+\.eyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+"#,
            message: "Hardcoded JWT token detected"
        ),
        // Google API Key
        SecretPattern(
            name: "Google API Key",
            pattern: #"AIza[0-9A-Za-z\-_]{35}"#,
            message: "Hardcoded Google API key detected"
        ),
        // Firebase Key
        SecretPattern(
            name: "Firebase Key",
            pattern: #"AAAA[A-Za-z0-9_-]{7}:[A-Za-z0-9_-]{140}"#,
            message: "Hardcoded Firebase Cloud Messaging key detected"
        ),
        // Twilio API Key
        SecretPattern(
            name: "Twilio Key",
            pattern: #"SK[0-9a-fA-F]{32}"#,
            message: "Hardcoded Twilio API key detected"
        ),
        // SendGrid API Key
        SecretPattern(
            name: "SendGrid Key",
            pattern: #"SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}"#,
            message: "Hardcoded SendGrid API key detected"
        ),
        // Heroku API Key
        SecretPattern(
            name: "Heroku Key",
            pattern: #"[hH]eroku[a-zA-Z0-9]{25,40}"#,
            message: "Potential hardcoded Heroku API key detected"
        ),
        // MailChimp API Key
        SecretPattern(
            name: "MailChimp Key",
            pattern: #"[0-9a-f]{32}-us[0-9]{1,2}"#,
            message: "Hardcoded MailChimp API key detected"
        ),
        // Square Access Token
        SecretPattern(
            name: "Square Token",
            pattern: #"sq0atp-[0-9A-Za-z\-_]{22}"#,
            message: "Hardcoded Square access token detected"
        ),
        // Square OAuth Secret
        SecretPattern(
            name: "Square OAuth",
            pattern: #"sq0csp-[0-9A-Za-z\-_]{43}"#,
            message: "Hardcoded Square OAuth secret detected"
        ),
        // Telegram Bot Token
        SecretPattern(
            name: "Telegram Token",
            pattern: #"[0-9]{8,10}:[A-Za-z0-9_-]{35}"#,
            message: "Hardcoded Telegram bot token detected"
        ),
    ]
    
    /// Variable names that suggest password/secret storage
    private static let sensitiveVariablePatterns: [String] = [
        "password", "passwd", "pwd", "secret", "apikey", "api_key",
        "auth_token", "authtoken", "access_token", "accesstoken",
        "private_key", "privatekey", "secret_key", "secretkey",
        "credentials", "bearer"
    ]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        let stringContent = extractStringContent(from: node)
        
        // Skip empty or very short strings
        guard stringContent.count >= 10 else {
            return .visitChildren
        }
        
        // Check against known patterns
        for pattern in Self.secretPatterns {
            let range = NSRange(stringContent.startIndex..<stringContent.endIndex, in: stringContent)
            if pattern.regex.firstMatch(in: stringContent, options: [], range: range) != nil {
                let location = sourceFile.location(of: node)
                
                violations.append(
                    ViolationBuilder(
                        ruleId: "hardcoded_secrets",
                        category: .security,
                        location: location
                    )
                    .message(pattern.message)
                    .suggestFix("Move secrets to environment variables, secure configuration, or a secrets manager")
                    .severity(.error)
                    .build()
                )
                return .visitChildren
            }
        }
        
        // Check for high entropy strings that might be secrets
        if stringContent.count >= 20 && isHighEntropy(stringContent) && !isLikelyFalsePositive(stringContent) {
            let location = sourceFile.location(of: node)
            
            violations.append(
                ViolationBuilder(
                    ruleId: "hardcoded_secrets",
                    category: .security,
                    location: location
                )
                .message("High-entropy string detected - potential hardcoded secret")
                .suggestFix("If this is a secret, move it to environment variables or a secrets manager")
                .severity(.warning)
                .build()
            )
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        // Check if variable name suggests sensitive data
        guard let identifier = node.pattern.as(IdentifierPatternSyntax.self) else {
            return .visitChildren
        }
        
        let varName = identifier.identifier.text.lowercased()
        
        // Check if this is a sensitive variable with a string literal value
        for pattern in Self.sensitiveVariablePatterns {
            if varName.contains(pattern) {
                // Check if assigned a non-empty string literal
                if let initializer = node.initializer,
                   let stringLiteral = initializer.value.as(StringLiteralExprSyntax.self) {
                    let stringContent = extractStringContent(from: stringLiteral)
                    
                    // Skip if it's clearly a placeholder or empty
                    if !stringContent.isEmpty && 
                       !isPlaceholder(stringContent) &&
                       stringContent.count >= 4 {
                        let location = sourceFile.location(of: node)
                        
                        violations.append(
                            ViolationBuilder(
                                ruleId: "hardcoded_secrets",
                                category: .security,
                                location: location
                            )
                            .message("Sensitive variable '\(identifier.identifier.text)' contains hardcoded value")
                            .suggestFix("Load sensitive values from environment variables or secure configuration")
                            .severity(.error)
                            .build()
                        )
                    }
                }
                break
            }
        }
        
        return .visitChildren
    }
    
    /// Extract string content from a string literal expression
    private func extractStringContent(from node: StringLiteralExprSyntax) -> String {
        return node.segments.compactMap { segment -> String? in
            if let stringSegment = segment.as(StringSegmentSyntax.self) {
                return stringSegment.content.text
            }
            return nil
        }.joined()
    }
    
    /// Calculate Shannon entropy of a string (higher = more random)
    private func isHighEntropy(_ string: String) -> Bool {
        let entropy = calculateEntropy(string)
        // Threshold: typical English text has entropy ~4.0, random strings ~5.5+
        return entropy >= 4.5
    }
    
    private func calculateEntropy(_ string: String) -> Double {
        var frequencies: [Character: Int] = [:]
        for char in string {
            frequencies[char, default: 0] += 1
        }
        
        let length = Double(string.count)
        var entropy: Double = 0.0
        
        for (_, count) in frequencies {
            let probability = Double(count) / length
            entropy -= probability * log2(probability)
        }
        
        return entropy
    }
    
    /// Check if string is likely a false positive (common patterns that aren't secrets)
    private func isLikelyFalsePositive(_ string: String) -> Bool {
        // UUIDs are common and not secrets
        if string.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil {
            return true
        }
        
        // File paths
        if string.hasPrefix("/") || string.hasPrefix("./") || string.hasPrefix("~/") {
            return true
        }
        
        // URLs without credentials
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            // Only flag if URL contains potential credentials
            if !string.contains("@") && !string.contains("token") && !string.contains("key") {
                return true
            }
        }
        
        // Common test/example values
        let falsePositivePatterns = [
            "example", "test", "sample", "demo", "placeholder",
            "localhost", "your-", "xxx", "..."
        ]
        let lowercased = string.lowercased()
        for pattern in falsePositivePatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }
        
        // Repeated characters suggest placeholder
        let uniqueChars = Set(string)
        if uniqueChars.count < 5 {
            return true
        }
        
        return false
    }
    
    /// Check if string is a placeholder value
    private func isPlaceholder(_ string: String) -> Bool {
        let lowercased = string.lowercased()
        let placeholders = [
            "<", ">", "your_", "your-", "xxx", "todo", "fixme",
            "placeholder", "change_me", "replace", "insert"
        ]
        for placeholder in placeholders {
            if lowercased.contains(placeholder) {
                return true
            }
        }
        return false
    }
}
