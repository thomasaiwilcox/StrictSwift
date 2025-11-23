import XCTest
@testable import StrictSwiftCore
import Foundation

final class BaselineFilteringTests: XCTestCase {

    func testBaselineFiltersKnownViolations() async throws {
        // Create test source with violations
        let source = """
        import Foundation

        func testFunction() {
            let optional: String? = "test"
            let forced = optional!  // This will be in baseline
            let another = optional!  // This will be in baseline
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")

        // Create violations (simulating analysis)
        let violations = createMockViolations(count: 2, lines: [6, 7])

        // Create baseline with these violations
        let baseline = BaselineConfiguration(
            violations: violations.map { ViolationFingerprint(violation: $0, projectRoot: sourceFile.url.deletingLastPathComponent()) }
        )

        // Test baseline filtering
        let filtered = filterViolationsWithBaseline(violations, baseline: baseline, projectRoot: sourceFile.url.deletingLastPathComponent())

        // All violations should be filtered out
        XCTAssertEqual(filtered.count, 0)
    }

    func testBaselinePreservesNewViolations() async throws {
        // Create test source with violations
        let source = """
        import Foundation

        func testFunction() {
            let optional: String? = "test"
            let forced = optional!  // This will be in baseline
            let another = optional!  // This is NEW, not in baseline
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")

        // Create violations (simulating analysis)
        let knownViolation = createMockViolation(line: 6)
        let newViolation = createMockViolation(line: 7)
        let violations = [knownViolation, newViolation]

        // Create baseline with only the known violation
        let baseline = BaselineConfiguration(
            violations: [ViolationFingerprint(violation: knownViolation, projectRoot: sourceFile.url.deletingLastPathComponent())]
        )

        // Test baseline filtering
        let filtered = filterViolationsWithBaseline(violations, baseline: baseline, projectRoot: sourceFile.url.deletingLastPathComponent())

        // Only the new violation should remain
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].location.line, 7)
    }

    func testBaselineDoesNotFilterExpiredBaseline() async throws {
        // Create test source with violations
        let source = """
        import Foundation

        func testFunction() {
            let optional: String? = "test"
            let forced = optional!  // This will be in expired baseline
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")

        // Create violations
        let violations = createMockViolations(count: 1, lines: [6])

        // Create EXPIRED baseline
        let expiredDate = Date().addingTimeInterval(-86400) // Yesterday
        let baseline = BaselineConfiguration(
            created: Date().addingTimeInterval(-172800), // 2 days ago
            expires: expiredDate,
            violations: violations.map { ViolationFingerprint(violation: $0, projectRoot: sourceFile.url.deletingLastPathComponent()) }
        )

        // Test baseline filtering
        let filtered = filterViolationsWithBaseline(violations, baseline: baseline, projectRoot: sourceFile.url.deletingLastPathComponent())

        // Violations should NOT be filtered because baseline is expired
        XCTAssertEqual(filtered.count, 1)
    }

    func testBaselineFingerprintStability() throws {
        // Create identical violations and verify fingerprints match
        let violation1 = createMockViolation(line: 10, ruleId: "force_unwrap", message: "Force unwrap (!) of optional value")
        let violation2 = createMockViolation(line: 10, ruleId: "force_unwrap", message: "Force unwrap (!) of optional value")

        let projectRoot = URL(fileURLWithPath: "/test")
        let fingerprint1 = ViolationFingerprint(violation: violation1, projectRoot: projectRoot)
        let fingerprint2 = ViolationFingerprint(violation: violation2, projectRoot: projectRoot)

        // Fingerprints should be identical
        XCTAssertEqual(fingerprint1.fingerprint, fingerprint2.fingerprint)
        XCTAssertEqual(fingerprint1.line, fingerprint2.line)
        XCTAssertEqual(fingerprint1.ruleId, fingerprint2.ruleId)
    }

    func testBaselineUpdateDeterminism() throws {
        // Create multiple violations
        let violations = createMockViolations(count: 5, lines: [1, 3, 5, 7, 9])

        // Create baseline multiple times and verify output is identical
        let baseline1 = BaselineConfiguration(
            violations: violations.map { ViolationFingerprint(violation: $0, projectRoot: URL(fileURLWithPath: "/test")) }
        )

        let baseline2 = BaselineConfiguration(
            violations: violations.map { ViolationFingerprint(violation: $0, projectRoot: URL(fileURLWithPath: "/test")) }
        )

        // Baselines should be identical
        XCTAssertEqual(baseline1.violations.count, baseline2.violations.count)

        // Check that violations are in the same order (deterministic)
        for i in 0..<baseline1.violations.count {
            XCTAssertEqual(baseline1.violations[i].fingerprint, baseline2.violations[i].fingerprint)
        }
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

    private func createMockViolation(line: Int, ruleId: String = "force_unwrap", message: String = "Force unwrap (!) of optional value") -> Violation {
        return Violation(
            ruleId: ruleId,
            category: .safety,
            severity: .error,
            message: message,
            location: Location(
                file: URL(fileURLWithPath: "/test.swift"),
                line: line,
                column: 10
            ),
            relatedLocations: [],
            suggestedFixes: ["Use optional binding instead"],
            context: [:]
        )
    }

    private func createMockViolations(count: Int, lines: [Int]) -> [Violation] {
        return lines.enumerated().map { index, line in
            createMockViolation(line: line, message: "Force unwrap violation \(index + 1)")
        }
    }

    private func filterViolationsWithBaseline(_ violations: [Violation], baseline: BaselineConfiguration, projectRoot: URL) -> [Violation] {
        // Simulate the baseline filtering logic from Analyzer
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