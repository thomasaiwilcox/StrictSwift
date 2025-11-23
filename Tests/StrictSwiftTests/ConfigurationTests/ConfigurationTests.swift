import Foundation
import StrictSwiftCore
import XCTest

final class ConfigurationTests: XCTestCase {
    func testProfileLoading() {
        let config = Profile.criticalCore.configuration

        XCTAssertEqual(config.profile, .criticalCore)
        XCTAssertEqual(config.rules.memory.severity, .error)
        XCTAssertEqual(config.rules.concurrency.severity, .error)
        XCTAssertEqual(config.rules.safety.severity, .error)
        XCTAssertEqual(config.rules.performance.severity, .warning)
    }

    func testConfigurationValidation() {
        var config = Configuration.default

        // Valid configuration should not throw
        XCTAssertNoThrow(try config.validate())

        // Invalid maxJobs should throw
        config = Configuration(maxJobs: 0)
        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidMaxJobs)
        }
    }

    func testConfigurationMerging() {
        let merged = Configuration.load(from: nil, profile: .criticalCore)
        XCTAssertNotEqual(merged.include.count, 0)
    }

    func testBaselineConfiguration() throws {
        let baseline = BaselineConfiguration()

        XCTAssertFalse(baseline.isExpired)
        XCTAssertEqual(baseline.version, 1)
        XCTAssertTrue(baseline.violations.isEmpty)

        let violation = ViolationFingerprint(
            ruleId: "test_rule",
            file: "test.swift",
            line: 1,
            fingerprint: "abc123"
        )

        let newBaseline = baseline.adding(violation: violation)
        XCTAssertEqual(newBaseline.violations.count, 1)
    }
}