import Foundation
import StrictSwiftCore
import XCTest

/// Test case for rule validation
public struct TestCase {
    /// Name of the test case
    public let name: String
    /// Swift source code to test
    public let source: String
    /// Expected violations
    public let expectedViolations: [ExpectedViolation]
    /// Configuration to use
    public let configuration: Configuration
    /// File URL (for location information)
    public let url: URL

    public init(
        name: String,
        source: String,
        expectedViolations: [ExpectedViolation] = [],
        configuration: Configuration = .default,
        url: URL = URL(fileURLWithPath: "/test.swift")
    ) {
        self.name = name
        self.source = source
        self.expectedViolations = expectedViolations
        self.configuration = configuration
        self.url = url
    }

    /// Create test case with minimal setup
    public static func simple(
        name: String,
        source: String,
        ruleId: String,
        line: Int = 1,
        configuration: Configuration = .default
    ) -> TestCase {
        return TestCase(
            name: name,
            source: source,
            expectedViolations: [
                ExpectedViolation(ruleId: ruleId, line: line)
            ],
            configuration: configuration
        )
    }
}

/// Expected violation for test validation
public struct ExpectedViolation {
    /// ID of the rule that should generate the violation
    public let ruleId: String
    /// Line number where violation should occur
    public let line: Int
    /// Message (optional, for exact match)
    public let message: String?

    public init(ruleId: String, line: Int, message: String? = nil) {
        self.ruleId = ruleId
        self.line = line
        self.message = message
    }
}

/// Test utilities for StrictSwift
public extension XCTestCase {
    /// Assert that a rule detects violations as expected
    func assertRule(
        _ rule: Rule,
        detects testCase: TestCase
    ) async throws {
        let sourceFile = SourceFile(url: testCase.url, source: testCase.source)
        let context = AnalysisContext(
            configuration: testCase.configuration,
            projectRoot: URL(fileURLWithPath: "/")
        )
        context.addSourceFile(sourceFile)

        let violations = await rule.analyze(sourceFile, in: context)

        // Check expected violations
        for expected in testCase.expectedViolations {
            let matching = violations.first { violation in
                violation.ruleId == expected.ruleId && violation.location.line == expected.line
            }

            XCTAssertNotNil(
                matching,
                "Rule '\(rule.id)' failed to detect expected violation at line \(expected.line) in test case '\(testCase.name)'.\nSource:\n\(testCase.source)\n\nActual violations: \(violations)"
            )

            // If message is specified, check it matches
            if let expectedMessage = expected.message,
               let actualViolation = matching {
                XCTAssertEqual(
                    actualViolation.message,
                    expectedMessage,
                    "Violation message mismatch for rule '\(rule.id)'"
                )
            }
        }

        // Check for unexpected violations
        let expectedRuleIds = Set(testCase.expectedViolations.map { $0.ruleId })
        let unexpectedViolations = violations.filter { !expectedRuleIds.contains($0.ruleId) }

        if !unexpectedViolations.isEmpty {
            XCTFail(
                "Rule '\(rule.id)' detected unexpected violations in test case '\(testCase.name)':\n" +
                unexpectedViolations.map { "- \($0.ruleId) at line \($0.location.line): \($0.message)" }.joined(separator: "\n")
            )
        }
    }

    /// Assert that no violations are detected
    func assertRule(
        _ rule: Rule,
        detectsNoViolationsIn source: String
    ) async throws {
        let testCase = TestCase(
            name: "No violations",
            source: source
        )

        let sourceFile = SourceFile(url: testCase.url, source: testCase.source)
        let context = AnalysisContext(
            configuration: testCase.configuration,
            projectRoot: URL(fileURLWithPath: "/")
        )
        context.addSourceFile(sourceFile)

        let violations = await rule.analyze(sourceFile, in: context)

        XCTAssertTrue(
            violations.isEmpty,
            "Rule '\(rule.id)' unexpectedly detected violations:\n" +
            violations.map { "- \($0.ruleId) at line \($0.location.line): \($0.message)" }.joined(separator: "\n")
        )
    }
}