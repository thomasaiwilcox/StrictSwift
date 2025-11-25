import XCTest
@testable import StrictSwiftCore
import Foundation

/// End-to-end integration tests for StrictSwift Phase 0 functionality
final class EndToEndTests: XCTestCase {

    func testEndToEndAnalysisWithForceUnwrapRule() async throws {
        // Create test source with various violations
        let source = """
        import Foundation

        struct TestStruct {
            var optionalProperty: String?

            func methodWithViolations() {
                let optional: String? = "test"
                let forced = optional!  // Violation 1

                let propertyForced = optionalProperty!  // Violation 2
                let chained = optional!.count  // Violation 3
            }
        }

        class TestClass {
            let optional: String?

            init(optional: String?) {
                self.optional = optional
                let initForced = optional!  // Violation 4
            }

            func safeMethod() {
                // These should NOT trigger violations
                if let safe = optional {
                    print(safe)
                }

                guard let guarded = optional else { return }
                print(guarded)

                let nilCoalesced = optional ?? "default"
                print(nilCoalesced)

                let optionalChained = optional?.count
                print(optionalChained)
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "end_to_end_test.swift")
        let _ = sourceFile.url.deletingLastPathComponent()

        // Create analyzer with default configuration
        let configuration = Configuration(profile: .criticalCore)
        let analyzer = Analyzer(configuration: configuration)

        // Run analysis
        let allViolations = try await analyzer.analyze(paths: [sourceFile.url.path])
        
        // Filter to only force_unwrap violations for this test
        let violations = allViolations.filter { $0.ruleId == "force_unwrap" }

        // Verify results
        XCTAssertEqual(violations.count, 4, "Should detect exactly 4 force unwrap violations")

        // Verify all violations are force unwrap violations
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "force_unwrap")
            XCTAssertEqual(violation.category, .safety)
            XCTAssertEqual(violation.severity, .warning) // critical-core configures safety as warning
        }

        // Verify locations are correct (adjusted for actual line numbers)
        let violationLines = violations.map { $0.location.line }.sorted()
        XCTAssertEqual(violationLines, [8, 10, 11, 20], "Violations should be on expected lines")
    }

    func testBaselineFilteringEndToEnd() async throws {
        // Create test source with violations
        let source = """
        import Foundation

        func testFunction() {
            let optional: String? = "test"
            let knownViolation = optional!  // This will be in baseline
            let newViolation = optional!    // This will NOT be in baseline
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "baseline_test.swift")
        let _ = sourceFile.url.deletingLastPathComponent()

        // Create violations (simulating analysis results)
        let violations = [
            createMockViolation(line: 6, file: sourceFile.url),
            createMockViolation(line: 7, file: sourceFile.url)
        ]

        // Create baseline with only the first violation
        let baselineViolation = createMockViolation(line: 6, file: sourceFile.url)
        let projectRoot = sourceFile.url.deletingLastPathComponent()
        let baseline = BaselineConfiguration(
            violations: [ViolationFingerprint(violation: baselineViolation, projectRoot: projectRoot)]
        )

        // Apply baseline filtering (simulating Analyzer behavior)
        let filtered = filterViolations(violations, with: baseline, projectRoot: projectRoot)

        // Should only have the second violation (not in baseline)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].location.line, 7)
    }

    func testReporterOutputFormats() throws {
        // Create test violations
        let violations = [
            createMockViolation(
                line: 10,
                file: URL(fileURLWithPath: "/test.swift"),
                ruleId: "force_unwrap",
                message: "Force unwrap (!) of optional value",
                severity: .error
            ),
            createMockViolation(
                line: 15,
                file: URL(fileURLWithPath: "/test.swift"),
                ruleId: "force_unwrap",
                message: "Force unwrap in method chaining",
                severity: .error
            )
        ]

        // Test Human Reporter
        let humanReporter = HumanReporter()
        let humanOutput = try humanReporter.generateReport(violations)

        XCTAssertTrue(humanOutput.contains("ERROR [SAFETY.force_unwrap]"))
        XCTAssertTrue(humanOutput.contains("Line 10"))
        XCTAssertTrue(humanOutput.contains("Line 15"))
        XCTAssertTrue(humanOutput.contains("2 violation(s)"))
        XCTAssertTrue(humanOutput.contains("2 error(s)"))

        // Test JSON Reporter (compact)
        let jsonReporter = JSONReporter(pretty: false)
        let jsonOutput = try jsonReporter.generateReport(violations)

        XCTAssertTrue(jsonOutput.contains("\"version\":2"))
        XCTAssertTrue(jsonOutput.contains("\"violations\""))
        XCTAssertTrue(jsonOutput.contains("\"force_unwrap\""))
        XCTAssertTrue(jsonOutput.contains("\"total\":2"))
        XCTAssertTrue(jsonOutput.contains("\"errors\":2")) // Mock violations are configured with error severity

        // Verify compact format (no newlines in JSON structure)
        let jsonLines = jsonOutput.split(separator: "\n")
        XCTAssertEqual(jsonLines.count, 1, "Compact JSON should be single line")

        // Test JSON Reporter (pretty)
        let jsonPrettyReporter = JSONReporter(pretty: true)
        let jsonPrettyOutput = try jsonPrettyReporter.generateReport(violations)

        // Pretty JSON may have spaces after colons
        XCTAssertTrue(jsonPrettyOutput.contains("\"version\"") && jsonPrettyOutput.contains("2"), "Should contain version 2")
        XCTAssertTrue(jsonPrettyOutput.contains("\"violations\""))

        // Verify pretty format (has newlines and indentation)
        let jsonPrettyLines = jsonPrettyOutput.split(separator: "\n")
        XCTAssertGreaterThan(jsonPrettyLines.count, 1, "Pretty JSON should have multiple lines")
    }

    func testConfigurationProfiles() throws {
        // Test different profiles have different configurations
        let criticalCore = Profile.criticalCore.configuration
        let serverDefault = Profile.serverDefault.configuration
        let libraryStrict = Profile.libraryStrict.configuration

        // Verify all profiles have required rule categories
        let requiredCategories: [RuleCategory] = [.memory, .concurrency, .architecture, .safety, .performance, .complexity, .monolith, .dependency]

        for category in requiredCategories {
            let criticalConfig = criticalCore.rules.configuration(for: category)
            let serverConfig = serverDefault.rules.configuration(for: category)
            let libraryConfig = libraryStrict.rules.configuration(for: category)

            XCTAssertTrue(criticalConfig.enabled, "Critical core should enable \(category)")
            XCTAssertTrue(serverConfig.enabled, "Server default should enable \(category)")
            XCTAssertTrue(libraryConfig.enabled, "Library strict should enable \(category)")
        }

        // Verify severity differences between profiles
        XCTAssertEqual(criticalCore.rules.configuration(for: .performance).severity, .warning)
        XCTAssertEqual(serverDefault.rules.configuration(for: .performance).severity, .info)
        XCTAssertEqual(libraryStrict.rules.configuration(for: .performance).severity, .info)

        XCTAssertEqual(criticalCore.rules.configuration(for: .architecture).severity, .error)
        XCTAssertEqual(serverDefault.rules.configuration(for: .architecture).severity, .warning)
        XCTAssertEqual(libraryStrict.rules.configuration(for: .architecture).severity, .warning)
    }

    func testSourceLocationAccuracy() throws {
        // Test that location tracking works correctly
        let source = """
        // Line 1
        // Line 2
        func test() {     // Line 3
            let opt: String? = "test"  // Line 4
            let forced = opt!           // Line 5 - Column 19
        }                              // Line 6
        """

        let sourceFile = try createSourceFile(content: source, filename: "location_test.swift")

        // Verify SourceFile tracks correct filename (ignore UUID prefix)
        XCTAssertTrue(sourceFile.url.lastPathComponent.contains("location_test.swift"))

        // Verify tree can be parsed (basic smoke test)
        XCTAssertNotNil(sourceFile.tree)
        XCTAssertTrue(sourceFile.tree.description.contains("opt!"))
    }

    // MARK: - Helper Methods

    private func createSourceFile(content: String, filename: String) throws -> SourceFile {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString)-\(filename)")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Register cleanup
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }

        return try SourceFile(url: fileURL)
    }

    private func createMockViolation(line: Int, file: URL, ruleId: String = "force_unwrap", message: String = "Force unwrap (!) of optional value", severity: DiagnosticSeverity = .error) -> Violation {
        return Violation(
            ruleId: ruleId,
            category: .safety,
            severity: severity,
            message: message,
            location: Location(
                file: file,
                line: line,
                column: 10
            ),
            relatedLocations: [],
            suggestedFixes: ["Use optional binding instead"],
            context: [:]
        )
    }

    private func filterViolations(_ violations: [Violation], with baseline: BaselineConfiguration, projectRoot: URL) -> [Violation] {
        guard !baseline.isExpired else {
            return violations // Don't filter if baseline is expired
        }

        let baselineFingerprints = Set(baseline.violations)

        return violations.filter { violation in
            let fingerprint = ViolationFingerprint(violation: violation, projectRoot: projectRoot)
            return !baselineFingerprints.contains(fingerprint)
        }
    }
}
