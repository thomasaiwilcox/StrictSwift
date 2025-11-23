import Foundation

/// Protocol for formatting and outputting analysis results
public protocol Reporter: Sendable {
    /// Generate report for violations
    func generateReport(_ violations: [Violation]) throws -> String
}