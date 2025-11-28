import XCTest
@testable import StrictSwiftCore

final class XcodeReporterTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func createTestViolation(
        ruleId: String = "test_rule",
        line: Int = 1,
        column: Int = 1,
        severity: DiagnosticSeverity = .warning,
        message: String = "Test violation"
    ) -> Violation {
        return Violation(
            ruleId: ruleId,
            category: .safety,
            severity: severity,
            message: message,
            location: Location(
                file: URL(fileURLWithPath: "/test/file.swift"),
                line: line,
                column: column
            )
        )
    }
    
    // MARK: - Basic Output Tests
    
    func testXcodeReporterOutputsCorrectFormat() throws {
        let violation = createTestViolation(
            ruleId: "force_unwrap",
            line: 42,
            column: 10,
            severity: .warning,
            message: "Force unwrap detected"
        )
        let reporter = XcodeReporter()
        
        let output = try reporter.generateReport([violation])
        
        XCTAssertEqual(
            output,
            "/test/file.swift:42:10: warning: Force unwrap detected [force_unwrap]"
        )
    }
    
    func testXcodeReporterMultipleViolations() throws {
        let violations = [
            createTestViolation(ruleId: "rule1", line: 10, column: 5, message: "First issue"),
            createTestViolation(ruleId: "rule2", line: 20, column: 15, message: "Second issue")
        ]
        let reporter = XcodeReporter()
        
        let output = try reporter.generateReport(violations)
        let lines = output.split(separator: "\n")
        
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("10:5"))
        XCTAssertTrue(lines[1].contains("20:15"))
    }
    
    func testXcodeReporterMapsSeverityToError() throws {
        let violation = createTestViolation(severity: .error, message: "Error message")
        let reporter = XcodeReporter()
        
        let output = try reporter.generateReport([violation])
        
        XCTAssertTrue(output.contains(": error:"))
        XCTAssertFalse(output.contains(": warning:"))
    }
    
    func testXcodeReporterMapsSeverityToWarning() throws {
        let violation = createTestViolation(severity: .warning, message: "Warning message")
        let reporter = XcodeReporter()
        
        let output = try reporter.generateReport([violation])
        
        XCTAssertTrue(output.contains(": warning:"))
    }
    
    func testXcodeReporterMapsSeverityToNote() throws {
        let infoViolation = createTestViolation(severity: .info, message: "Info message")
        let hintViolation = createTestViolation(severity: .hint, message: "Hint message")
        let reporter = XcodeReporter()
        
        let infoOutput = try reporter.generateReport([infoViolation])
        let hintOutput = try reporter.generateReport([hintViolation])
        
        XCTAssertTrue(infoOutput.contains(": note:"))
        XCTAssertTrue(hintOutput.contains(": note:"))
    }
    
    func testXcodeReporterIncludesRuleId() throws {
        let violation = createTestViolation(ruleId: "my_custom_rule", message: "Custom issue")
        let reporter = XcodeReporter()
        
        let output = try reporter.generateReport([violation])
        
        XCTAssertTrue(output.hasSuffix("[my_custom_rule]"))
    }
    
    func testXcodeReporterEmptyViolations() throws {
        let reporter = XcodeReporter()
        
        let output = try reporter.generateReport([])
        
        XCTAssertEqual(output, "")
    }
    
    func testXcodeReporterPathWithSpaces() throws {
        let violation = Violation(
            ruleId: "test",
            category: .safety,
            severity: .warning,
            message: "Test",
            location: Location(
                file: URL(fileURLWithPath: "/path with spaces/file.swift"),
                line: 1,
                column: 1
            )
        )
        let reporter = XcodeReporter()
        
        let output = try reporter.generateReport([violation])
        
        XCTAssertTrue(output.hasPrefix("/path with spaces/file.swift:"))
    }
}
