import XCTest
@testable import StrictSwiftCore

final class SecurityRulesTests: XCTestCase {
    
    // MARK: - HardcodedSecretsRule Tests
    
    func testHardcodedSecretsRuleDetectsAWSAccessKey() async throws {
        let code = """
        let accessKey = "AKIAIOSFODNN7EXAMPLE"
        """
        
        let violations = try await analyzeWithRule(HardcodedSecretsRule(), code: code)
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.ruleId, "hardcoded_secrets")
        XCTAssertTrue(violations.first?.message.contains("AWS") ?? false)
    }
    
    func testHardcodedSecretsRuleDetectsJWTToken() async throws {
        let code = """
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        """
        
        let violations = try await analyzeWithRule(HardcodedSecretsRule(), code: code)
        XCTAssertEqual(violations.count, 1)
        XCTAssertTrue(violations.first?.message.contains("JWT") ?? false)
    }
    
    func testHardcodedSecretsRuleDetectsGitHubToken() async throws {
        let code = """
        let githubToken = "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        """
        
        let violations = try await analyzeWithRule(HardcodedSecretsRule(), code: code)
        XCTAssertEqual(violations.count, 1)
        XCTAssertTrue(violations.first?.message.contains("GitHub") ?? false)
    }
    
    func testHardcodedSecretsRuleDetectsPrivateKey() async throws {
        let code = """
        let key = "-----BEGIN RSA PRIVATE KEY-----\\nMIIEow..."
        """
        
        let violations = try await analyzeWithRule(HardcodedSecretsRule(), code: code)
        XCTAssertEqual(violations.count, 1)
        XCTAssertTrue(violations.first?.message.contains("private key") ?? false)
    }
    
    func testHardcodedSecretsRuleDetectsPasswordAssignment() async throws {
        let code = """
        let password = "supersecret123"
        let apiKey = "abc123xyz789"
        let secret = "mysupersecretvalue"
        """
        
        let violations = try await analyzeWithRule(HardcodedSecretsRule(), code: code)
        XCTAssertGreaterThanOrEqual(violations.count, 3)
    }
    
    func testHardcodedSecretsRuleIgnoresNonSecretStrings() async throws {
        let code = """
        let message = "Hello, World!"
        let name = "John Doe"
        let emptyPassword = ""
        let placeholderApiKey = "placeholder"
        """
        
        let violations = try await analyzeWithRule(HardcodedSecretsRule(), code: code)
        XCTAssertEqual(violations.count, 0)
    }
    
    func testHardcodedSecretsRuleIgnoresEnvironmentVariables() async throws {
        let code = """
        let apiKey = ProcessInfo.processInfo.environment["API_KEY"]
        let secret = getenv("SECRET")
        """
        
        let violations = try await analyzeWithRule(HardcodedSecretsRule(), code: code)
        XCTAssertEqual(violations.count, 0)
    }
    
    // MARK: - InsecureCryptoRule Tests
    
    func testInsecureCryptoRuleDetectsMD5() async throws {
        let code = """
        import CryptoKit
        let hash = Insecure.MD5.hash(data: data)
        """
        
        let violations = try await analyzeWithRule(InsecureCryptoRule(), code: code)
        XCTAssertGreaterThanOrEqual(violations.count, 1)
        XCTAssertTrue(violations.contains { $0.message.contains("MD5") })
    }
    
    func testInsecureCryptoRuleDetectsSHA1() async throws {
        let code = """
        import CryptoKit
        let hash = Insecure.SHA1.hash(data: data)
        """
        
        let violations = try await analyzeWithRule(InsecureCryptoRule(), code: code)
        XCTAssertGreaterThanOrEqual(violations.count, 1, "Expected at least 1 violation for Insecure.SHA1")
    }
    
    func testInsecureCryptoRuleDetectsDeprecatedCrypto() async throws {
        let code = """
        import CommonCrypto
        let result = CC_MD5(data, length, hash)
        """
        
        let violations = try await analyzeWithRule(InsecureCryptoRule(), code: code)
        XCTAssertGreaterThanOrEqual(violations.count, 1)
    }
    
    func testInsecureCryptoRuleDetectsECBMode() async throws {
        let code = """
        let options = CCOptions(kCCOptionECBMode)
        """
        
        let violations = try await analyzeWithRule(InsecureCryptoRule(), code: code)
        XCTAssertEqual(violations.count, 1)
        XCTAssertTrue(violations.first?.message.contains("ECB") ?? false)
    }
    
    func testInsecureCryptoRuleAllowsSecureAlgorithms() async throws {
        let code = """
        import CryptoKit
        let hash = SHA256.hash(data: data)
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: key)
        """
        
        let violations = try await analyzeWithRule(InsecureCryptoRule(), code: code)
        XCTAssertEqual(violations.count, 0)
    }
    
    // MARK: - SensitiveLoggingRule Tests
    
    func testSensitiveLoggingRuleDetectsPasswordInPrint() async throws {
        let code = """
        func logUser(password: String) {
            print("Password: \\(password)")
        }
        """
        
        let violations = try await analyzeWithRule(SensitiveLoggingRule(), code: code)
        XCTAssertEqual(violations.count, 1)
        XCTAssertTrue(violations.first?.message.contains("password") ?? false)
    }
    
    func testSensitiveLoggingRuleDetectsSSNInLog() async throws {
        let code = """
        import os
        func processUser(ssn: String) {
            os_log("Processing SSN: %{public}@", ssn)
        }
        """
        
        let violations = try await analyzeWithRule(SensitiveLoggingRule(), code: code)
        XCTAssertEqual(violations.count, 1)
    }
    
    func testSensitiveLoggingRuleDetectsTokenInNSLog() async throws {
        let code = """
        func authenticate(authToken: String) {
            NSLog("Auth token: %@", authToken)
        }
        """
        
        let violations = try await analyzeWithRule(SensitiveLoggingRule(), code: code)
        XCTAssertGreaterThanOrEqual(violations.count, 1)
    }
    
    func testSensitiveLoggingRuleAllowsNonSensitiveData() async throws {
        let code = """
        func logUser(name: String, age: Int) {
            print("User: \\(name), Age: \\(age)")
        }
        """
        
        let violations = try await analyzeWithRule(SensitiveLoggingRule(), code: code)
        XCTAssertEqual(violations.count, 0)
    }
    
    func testSensitiveLoggingRuleDetectsCreditCardNumber() async throws {
        let code = """
        func processPayment(creditCardNumber: String) {
            print("Processing card: \\(creditCardNumber)")
        }
        """
        
        let violations = try await analyzeWithRule(SensitiveLoggingRule(), code: code)
        XCTAssertEqual(violations.count, 1)
    }
    
    // MARK: - SQLInjectionPatternRule Tests
    
    func testSQLInjectionPatternRuleDetectsInterpolation() async throws {
        let code = """
        func findUser(id: String) -> String {
            let query = "SELECT * FROM users WHERE id = '\\(id)'"
            return query
        }
        """
        
        let violations = try await analyzeWithRule(SQLInjectionPatternRule(), code: code)
        XCTAssertGreaterThanOrEqual(violations.count, 1)
        XCTAssertTrue(violations.contains { $0.message.contains("SQL") })
    }
    
    func testSQLInjectionPatternRuleDetectsInsertInterpolation() async throws {
        let code = """
        func insertUser(name: String) -> String {
            return "INSERT INTO users VALUES ('\\(name)')"
        }
        """
        
        let violations = try await analyzeWithRule(SQLInjectionPatternRule(), code: code)
        XCTAssertEqual(violations.count, 1)
    }
    
    func testSQLInjectionPatternRuleAllowsParameterizedQuery() async throws {
        let code = """
        func findUser(id: String) {
            let query = "SELECT * FROM users WHERE id = ?"
            db.execute(query, parameters: [id])
        }
        """
        
        let violations = try await analyzeWithRule(SQLInjectionPatternRule(), code: code)
        XCTAssertEqual(violations.count, 0)
    }
    
    func testSQLInjectionPatternRuleAllowsConstantQuery() async throws {
        let code = """
        let query = "SELECT * FROM users WHERE active = true"
        """
        
        let violations = try await analyzeWithRule(SQLInjectionPatternRule(), code: code)
        XCTAssertEqual(violations.count, 0)
    }
    
    // MARK: - Helper Methods
    
    private func analyzeWithRule(_ rule: Rule, code: String) async throws -> [Violation] {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("TestSecurityRules.swift")
        try code.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let sourceFile = try SourceFile(url: fileURL)
        let config = Configuration()
        let context = AnalysisContext(
            configuration: config,
            projectRoot: tempDir
        )
        context.addSourceFile(sourceFile)
        
        return await rule.analyze(sourceFile, in: context)
    }
}
