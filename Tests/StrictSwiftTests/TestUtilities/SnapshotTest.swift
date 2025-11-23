import Foundation
import StrictSwiftCore
import XCTest

/// Snapshot testing helper for diagnostics
public struct SnapshotTester {
    /// Take a snapshot of the violations
    public static func snapshot(violations: [Violation]) -> String {
        guard !violations.isEmpty else { return "No violations" }

        let sorted = violations.sorted { lhs, rhs in
            if lhs.location.file.path != rhs.location.file.path {
                return lhs.location.file.path < rhs.location.file.path
            }
            if lhs.location.line != rhs.location.line {
                return lhs.location.line < rhs.location.line
            }
            return lhs.ruleId < rhs.ruleId
        }

        var result = ""
        for violation in sorted {
            result += "\(violation.severity.rawValue.uppercased) [\(violation.category.rawValue).\(violation.ruleId)]\n"
            result += "  \(violation.message)\n"
            result += "  File: \(violation.location.file.path):\(violation.location.line):\(violation.location.column)\n"
            if !violation.suggestedFixes.isEmpty {
                result += "  Suggested fixes:\n"
                for fix in violation.suggestedFixes {
                    result += "    - \(fix)\n"
                }
            }
            result += "\n"
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Snapshot test assertions
public extension XCTestCase {
    /// Assert snapshot matches expected value
    func assertSnapshot(
        _ violations: [Violation],
        matches expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = SnapshotTester.snapshot(violations: violations)

        // Normalize line endings
        let normalizedActual = actual.replacingOccurrences(of: "\r\n", with: "\n")
        let normalizedExpected = expected.replacingOccurrences(of: "\r\n", with: "\n")

        XCTAssertEqual(
            normalizedActual,
            normalizedExpected,
            "Snapshot mismatch",
            file: file,
            line: line
        )
    }

    /// Assert snapshot matches file contents
    func assertSnapshotMatchesFile(
        _ violations: [Violation],
        fileURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expected = try String(contentsOf: fileURL)
        assertSnapshot(violations, matches: expected, file: file, line: line)
    }
}