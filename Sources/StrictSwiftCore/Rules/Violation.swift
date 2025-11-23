import Foundation

/// A rule violation found during analysis
public struct Violation: Codable, Hashable, Sendable {
    /// Unique identifier for the rule that generated this violation
    public let ruleId: String
    /// Category of the rule
    public let category: RuleCategory
    /// Severity of the violation
    public let severity: DiagnosticSeverity
    /// Human-readable message
    public let message: String
    /// Primary location of the violation
    public let location: Location
    /// Additional related locations (e.g., in circular dependencies)
    public let relatedLocations: [Location]
    /// Suggested fixes
    public let suggestedFixes: [String]
    /// Context information for the violation
    public let context: [String: String]

    public init(
        ruleId: String,
        category: RuleCategory,
        severity: DiagnosticSeverity,
        message: String,
        location: Location,
        relatedLocations: [Location] = [],
        suggestedFixes: [String] = [],
        context: [String: String] = [:]
    ) {
        self.ruleId = ruleId
        self.category = category
        self.severity = severity
        self.message = message
        self.location = location
        self.relatedLocations = relatedLocations
        self.suggestedFixes = suggestedFixes
        self.context = context
    }
}

/// Violation builder for easier construction
public struct ViolationBuilder {
    public let ruleId: String
    public let category: RuleCategory
    public let location: Location

    private var severity: DiagnosticSeverity = .warning
    private var message: String = ""
    private var relatedLocations: [Location] = []
    private var suggestedFixes: [String] = []
    private var context: [String: String] = [:]

    public init(ruleId: String, category: RuleCategory, location: Location) {
        self.ruleId = ruleId
        self.category = category
        self.location = location
    }

    public func severity(_ severity: DiagnosticSeverity) -> ViolationBuilder {
        var builder = self
        builder.severity = severity
        return builder
    }

    public func message(_ message: String) -> ViolationBuilder {
        var builder = self
        builder.message = message
        return builder
    }

    public func addRelatedLocation(_ location: Location) -> ViolationBuilder {
        var builder = self
        builder.relatedLocations.append(location)
        return builder
    }

    public func suggestFix(_ fix: String) -> ViolationBuilder {
        var builder = self
        builder.suggestedFixes.append(fix)
        return builder
    }

    public func addContext(key: String, value: String) -> ViolationBuilder {
        var builder = self
        builder.context[key] = value
        return builder
    }

    public func build() -> Violation {
        Violation(
            ruleId: ruleId,
            category: category,
            severity: severity,
            message: message,
            location: location,
            relatedLocations: relatedLocations,
            suggestedFixes: suggestedFixes,
            context: context
        )
    }
}