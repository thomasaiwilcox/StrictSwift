import Foundation

/// Categories of rules that StrictSwift can enforce
public enum RuleCategory: String, Codable, CaseIterable, Sendable {
    case memory
    case concurrency
    case architecture
    case safety
    case performance
    case complexity
    case monolith
    case dependency
}

/// Severity levels for rule violations
public enum DiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case error
    case warning
    case info
    case hint
}