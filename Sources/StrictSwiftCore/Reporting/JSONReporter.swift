import Foundation

/// JSON formatted reporter for CI/automation
public struct JSONReporter: Reporter {
    private let pretty: Bool

    public init(pretty: Bool = false) {
        self.pretty = pretty
    }

    public func generateReport(_ violations: [Violation]) throws -> String {
        let report = JSONReport(
            version: 2,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            summary: Summary(
                total: violations.count,
                errors: violations.filter { $0.severity == .error }.count,
                warnings: violations.filter { $0.severity == .warning }.count,
                info: violations.filter { $0.severity == .info }.count,
                hints: violations.filter { $0.severity == .hint }.count
            ),
            violations: violations.map { jsonViolation(from: $0) }
        )

        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        let data = try encoder.encode(report)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonViolation(from violation: Violation) -> JSONViolation {
        return JSONViolation(
            ruleId: violation.ruleId,
            category: violation.category.rawValue,
            severity: violation.severity.rawValue,
            message: violation.message,
            location: JSONLocation(
                file: violation.location.file.path,
                line: violation.location.line,
                column: violation.location.column
            ),
            relatedLocations: violation.relatedLocations.map { location in
                JSONLocation(
                    file: location.file.path,
                    line: location.line,
                    column: location.column
                )
            },
            suggestedFixes: violation.suggestedFixes,
            context: violation.context
        )
    }

    // MARK: - JSON Structures

    private struct JSONReport: Codable {
        let version: Int
        let timestamp: String
        let summary: Summary
        let violations: [JSONViolation]
    }

    private struct Summary: Codable {
        let total: Int
        let errors: Int
        let warnings: Int
        let info: Int
        let hints: Int
    }

    private struct JSONViolation: Codable {
        let ruleId: String
        let category: String
        let severity: String
        let message: String
        let location: JSONLocation
        let relatedLocations: [JSONLocation]
        let suggestedFixes: [String]
        let context: [String: String]
    }

    private struct JSONLocation: Codable {
        let file: String
        let line: Int
        let column: Int
    }
}