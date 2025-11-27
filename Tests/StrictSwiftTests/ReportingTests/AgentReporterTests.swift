import XCTest
@testable import StrictSwiftCore

final class AgentReporterTests: XCTestCase {
    
    // MARK: - Basic Output Tests
    
    func testAgentReporterOutputFormat() throws {
        let violations = [createTestViolation(ruleId: "force_unwrap", line: 10)]
        let reporter = AgentReporter()
        
        let output = try reporter.generateReport(violations)
        
        // Should be valid JSON
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        
        // Should have required structure
        XCTAssertEqual(json?["version"] as? Int, 1)
        XCTAssertEqual(json?["format"] as? String, "agent")
        XCTAssertNotNil(json?["summary"])
        XCTAssertNotNil(json?["violations"])
    }
    
    func testAgentReporterIncludesStableId() throws {
        let violation = createTestViolation(ruleId: "force_unwrap", line: 42)
        let reporter = AgentReporter()
        
        let output = try reporter.generateReport([violation])
        
        // Parse and check for stable ID
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let violations = json?["violations"] as? [[String: Any]]
        
        XCTAssertEqual(violations?.count, 1)
        let id = violations?.first?["id"] as? String
        XCTAssertNotNil(id)
        XCTAssertEqual(id, violation.stableId)
    }
    
    // MARK: - Summary Tests
    
    func testAgentReporterSummary() throws {
        let violations = [
            createTestViolation(ruleId: "force_unwrap", line: 1, severity: .error),
            createTestViolation(ruleId: "data_race", line: 2, severity: .warning),
            createTestViolation(ruleId: "unused_var", line: 3, severity: .warning),
            createTestViolation(ruleId: "style", line: 4, severity: .info)
        ]
        let reporter = AgentReporter()
        
        let output = try reporter.generateReport(violations)
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let summary = json?["summary"] as? [String: Any]
        
        XCTAssertEqual(summary?["total"] as? Int, 4)
        XCTAssertEqual(summary?["errors"] as? Int, 1)
        XCTAssertEqual(summary?["warnings"] as? Int, 2)
        XCTAssertEqual(summary?["info"] as? Int, 1)
    }
    
    // MARK: - Severity Filtering Tests
    
    func testAgentReporterSeverityFilteringErrors() throws {
        let violations = [
            createTestViolation(ruleId: "error1", line: 1, severity: .error),
            createTestViolation(ruleId: "warn1", line: 2, severity: .warning),
            createTestViolation(ruleId: "info1", line: 3, severity: .info)
        ]
        let options = AgentReporterOptions(minSeverity: .error)
        let reporter = AgentReporter(options: options)
        
        let output = try reporter.generateReport(violations)
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let summary = json?["summary"] as? [String: Any]
        let violationsList = json?["violations"] as? [[String: Any]]
        
        XCTAssertEqual(summary?["total"] as? Int, 1)
        XCTAssertEqual(violationsList?.count, 1)
        XCTAssertEqual(violationsList?.first?["rule"] as? String, "error1")
    }
    
    func testAgentReporterSeverityFilteringWarnings() throws {
        let violations = [
            createTestViolation(ruleId: "error1", line: 1, severity: .error),
            createTestViolation(ruleId: "warn1", line: 2, severity: .warning),
            createTestViolation(ruleId: "info1", line: 3, severity: .info),
            createTestViolation(ruleId: "hint1", line: 4, severity: .hint)
        ]
        let options = AgentReporterOptions(minSeverity: .warning)
        let reporter = AgentReporter(options: options)
        
        let output = try reporter.generateReport(violations)
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let violationsList = json?["violations"] as? [[String: Any]]
        
        XCTAssertEqual(violationsList?.count, 2) // error + warning only
    }
    
    func testAgentReporterNoSeverityFilter() throws {
        let violations = [
            createTestViolation(ruleId: "error1", line: 1, severity: .error),
            createTestViolation(ruleId: "warn1", line: 2, severity: .warning),
            createTestViolation(ruleId: "info1", line: 3, severity: .info),
            createTestViolation(ruleId: "hint1", line: 4, severity: .hint)
        ]
        let reporter = AgentReporter() // No filter
        
        let output = try reporter.generateReport(violations)
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let violationsList = json?["violations"] as? [[String: Any]]
        
        XCTAssertEqual(violationsList?.count, 4) // All violations
    }
    
    // MARK: - Context Lines Tests
    
    func testAgentReporterNoContextByDefault() throws {
        let violation = createTestViolation(ruleId: "force_unwrap", line: 5)
        let reporter = AgentReporter() // contextLines = 0 by default
        
        let output = try reporter.generateReport([violation])
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let violations = json?["violations"] as? [[String: Any]]
        
        // Context should be nil/absent when contextLines = 0
        let context = violations?.first?["context"]
        XCTAssertTrue(context == nil || (context as? NSNull) != nil)
    }
    
    func testAgentReporterContextLinesOption() throws {
        // Create a temp file with known content
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("Test.swift")
        let fileContent = """
        // Line 1
        // Line 2
        // Line 3
        let x = value!  // Line 4 - the violation
        // Line 5
        // Line 6
        // Line 7
        """
        try fileContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        let violation = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .warning,
            message: "Force unwrap",
            location: Location(file: testFile, line: 4, column: 15)
        )
        
        let options = AgentReporterOptions(contextLines: 2)
        let reporter = AgentReporter(options: options)
        
        let output = try reporter.generateReport([violation])
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let violations = json?["violations"] as? [[String: Any]]
        let context = violations?.first?["context"] as? [String]
        
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.count, 5) // 2 before + 1 current + 2 after
        XCTAssertTrue(context?.contains("let x = value!  // Line 4 - the violation") ?? false)
    }
    
    // MARK: - Fix Serialization Tests
    
    func testAgentReporterIncludesFixes() throws {
        let violation = createViolationWithFix()
        
        let options = AgentReporterOptions(includeFixes: true)
        let reporter = AgentReporter(options: options)
        
        let output = try reporter.generateReport([violation])
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let violations = json?["violations"] as? [[String: Any]]
        let fixes = violations?.first?["fixes"] as? [[String: Any]]
        
        XCTAssertNotNil(fixes)
        XCTAssertEqual(fixes?.count, 1)
        
        let firstFix = fixes?.first
        XCTAssertEqual(firstFix?["title"] as? String, "Replace with if-let")
        XCTAssertEqual(firstFix?["kind"] as? String, "insert_if_let")
        XCTAssertEqual(firstFix?["confidence"] as? String, "suggested")
        XCTAssertEqual(firstFix?["isPreferred"] as? Bool, true)
        
        let edits = firstFix?["edits"] as? [[String: Any]]
        XCTAssertEqual(edits?.count, 1)
        XCTAssertEqual(edits?.first?["newText"] as? String, "if let x = value { use(x) }")
    }
    
    func testAgentReporterExcludesFixesWhenDisabled() throws {
        let violation = createViolationWithFix()
        
        let options = AgentReporterOptions(includeFixes: false)
        let reporter = AgentReporter(options: options)
        
        let output = try reporter.generateReport([violation])
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let violations = json?["violations"] as? [[String: Any]]
        let fixes = violations?.first?["fixes"]
        
        XCTAssertTrue(fixes == nil || (fixes as? NSNull) != nil)
    }
    
    // MARK: - Violation Fields Tests
    
    func testAgentReporterViolationFields() throws {
        let violation = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .error,
            message: "Force unwrap detected",
            location: Location(
                file: URL(fileURLWithPath: "/path/to/Test.swift"),
                line: 42,
                column: 15
            )
        )
        
        let reporter = AgentReporter()
        let output = try reporter.generateReport([violation])
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let violations = json?["violations"] as? [[String: Any]]
        let v = violations?.first
        
        XCTAssertEqual(v?["rule"] as? String, "force_unwrap")
        XCTAssertEqual(v?["category"] as? String, "safety")
        XCTAssertEqual(v?["severity"] as? String, "error")
        XCTAssertEqual(v?["message"] as? String, "Force unwrap detected")
        XCTAssertTrue((v?["file"] as? String)?.hasSuffix("Test.swift") ?? false)
        XCTAssertEqual(v?["line"] as? Int, 42)
        XCTAssertEqual(v?["column"] as? Int, 15)
    }
    
    // MARK: - Empty Input Tests
    
    func testAgentReporterEmptyViolations() throws {
        let reporter = AgentReporter()
        let output = try reporter.generateReport([])
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let summary = json?["summary"] as? [String: Any]
        let violations = json?["violations"] as? [[String: Any]]
        
        XCTAssertEqual(summary?["total"] as? Int, 0)
        XCTAssertEqual(violations?.count, 0)
    }
    
    // MARK: - AgentFixReporter Tests
    
    func testAgentFixReporterOutputFormat() throws {
        let reporter = AgentFixReporter()
        let results: [FixApplicationResult] = []
        
        let output = try reporter.generateReport(results)
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertEqual(json?["version"] as? Int, 1)
        XCTAssertEqual(json?["format"] as? String, "agent-fix")
        XCTAssertNotNil(json?["summary"])
        XCTAssertNotNil(json?["applied"])
    }
    
    // MARK: - Helper Methods
    
    private func createTestViolation(
        ruleId: String,
        line: Int,
        severity: DiagnosticSeverity = .warning
    ) -> Violation {
        return Violation(
            ruleId: ruleId,
            category: .safety,
            severity: severity,
            message: "Test violation for \(ruleId)",
            location: Location(
                file: URL(fileURLWithPath: "/test/TestFile.swift"),
                line: line,
                column: 1
            )
        )
    }
    
    private func createViolationWithFix() -> Violation {
        let fix = StructuredFix(
            title: "Replace with if-let",
            kind: .insertIfLet,
            edits: [
                TextEdit(
                    range: SourceRange(
                        startLine: 10,
                        startColumn: 5,
                        endLine: 10,
                        endColumn: 15,
                        file: "/test/file.swift"
                    ),
                    newText: "if let x = value { use(x) }"
                )
            ],
            isPreferred: true,
            confidence: .suggested,
            ruleId: "force_unwrap"
        )
        
        return Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .warning,
            message: "Force unwrap detected",
            location: Location(
                file: URL(fileURLWithPath: "/test/TestFile.swift"),
                line: 10,
                column: 1
            ),
            structuredFixes: [fix]
        )
    }
}
