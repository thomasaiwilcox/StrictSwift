import XCTest
@testable import StrictSwiftCore

final class SARIFReporterTests: XCTestCase {
    
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
    
    func testSARIFReporterOutputsValidJSON() throws {
        let violations = [createTestViolation(ruleId: "force_unwrap", line: 10)]
        let reporter = SARIFReporter()
        
        let output = try reporter.generateReport(violations)
        
        // Should be valid JSON
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
    }
    
    func testSARIFReporterIncludesSchema() throws {
        let violations = [createTestViolation()]
        let reporter = SARIFReporter()
        
        let output = try reporter.generateReport(violations)
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertEqual(json?["$schema"] as? String, "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json")
        XCTAssertEqual(json?["version"] as? String, "2.1.0")
    }
    
    func testSARIFReporterIncludesToolInfo() throws {
        let violations = [createTestViolation()]
        let reporter = SARIFReporter()
        
        let output = try reporter.generateReport(violations)
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runs = json?["runs"] as? [[String: Any]]
        let tool = runs?.first?["tool"] as? [String: Any]
        let driver = tool?["driver"] as? [String: Any]
        
        XCTAssertEqual(driver?["name"] as? String, "StrictSwift")
        XCTAssertNotNil(driver?["version"])
    }
    
    func testSARIFReporterMapsViolationsToResults() throws {
        let violations = [
            createTestViolation(ruleId: "force_unwrap", line: 10, severity: .error),
            createTestViolation(ruleId: "data_race", line: 20, severity: .warning)
        ]
        let reporter = SARIFReporter()
        
        let output = try reporter.generateReport(violations)
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runs = json?["runs"] as? [[String: Any]]
        let results = runs?.first?["results"] as? [[String: Any]]
        
        XCTAssertEqual(results?.count, 2)
        
        // Check first result
        let firstResult = results?.first
        XCTAssertEqual(firstResult?["ruleId"] as? String, "force_unwrap")
        XCTAssertEqual(firstResult?["level"] as? String, "error")
    }
    
    func testSARIFReporterMapsLocations() throws {
        let violation = createTestViolation(ruleId: "test", line: 42, column: 10)
        let reporter = SARIFReporter()
        
        let output = try reporter.generateReport([violation])
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runs = json?["runs"] as? [[String: Any]]
        let results = runs?.first?["results"] as? [[String: Any]]
        let locations = results?.first?["locations"] as? [[String: Any]]
        let physicalLocation = locations?.first?["physicalLocation"] as? [String: Any]
        let region = physicalLocation?["region"] as? [String: Any]
        
        XCTAssertEqual(region?["startLine"] as? Int, 42)
        XCTAssertEqual(region?["startColumn"] as? Int, 10)
    }
    
    func testSARIFReporterMapsSeverities() throws {
        let violations = [
            createTestViolation(ruleId: "e", severity: .error),
            createTestViolation(ruleId: "w", severity: .warning),
            createTestViolation(ruleId: "i", severity: .info),
            createTestViolation(ruleId: "h", severity: .hint)
        ]
        let reporter = SARIFReporter()
        
        let output = try reporter.generateReport(violations)
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runs = json?["runs"] as? [[String: Any]]
        let results = runs?.first?["results"] as? [[String: Any]]
        
        let levels = results?.compactMap { $0["level"] as? String }
        XCTAssertEqual(levels, ["error", "warning", "note", "note"])
    }
    
    func testSARIFReporterIncludesFingerprints() throws {
        let violation = createTestViolation(ruleId: "test", line: 42)
        let reporter = SARIFReporter()
        
        let output = try reporter.generateReport([violation])
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runs = json?["runs"] as? [[String: Any]]
        let results = runs?.first?["results"] as? [[String: Any]]
        let fingerprints = results?.first?["fingerprints"] as? [String: String]
        
        XCTAssertNotNil(fingerprints?["stableId"])
        XCTAssertEqual(fingerprints?["stableId"], violation.stableId)
    }
    
    func testSARIFReporterIncludesRules() throws {
        let violations = [
            createTestViolation(ruleId: "force_unwrap"),
            createTestViolation(ruleId: "data_race")
        ]
        let reporter = SARIFReporter(includeRules: true)
        
        let output = try reporter.generateReport(violations)
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runs = json?["runs"] as? [[String: Any]]
        let tool = runs?.first?["tool"] as? [String: Any]
        let driver = tool?["driver"] as? [String: Any]
        let rules = driver?["rules"] as? [[String: Any]]
        
        XCTAssertEqual(rules?.count, 2)
        
        let ruleIds = rules?.compactMap { $0["id"] as? String }.sorted()
        XCTAssertEqual(ruleIds, ["data_race", "force_unwrap"])
    }
    
    func testSARIFReporterEmptyViolations() throws {
        let reporter = SARIFReporter()
        
        let output = try reporter.generateReport([])
        
        let data = output.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runs = json?["runs"] as? [[String: Any]]
        let results = runs?.first?["results"] as? [[String: Any]]
        
        XCTAssertEqual(results?.count, 0)
    }
}
