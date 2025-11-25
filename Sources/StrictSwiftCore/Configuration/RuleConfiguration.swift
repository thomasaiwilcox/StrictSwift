import Foundation

/// Configuration for individual rules or rule categories
public struct RuleConfiguration: Codable, Equatable, Sendable {
    public let severity: DiagnosticSeverity
    public let enabled: Bool
    public let options: [String: String]
    
    /// Tracks whether severity was explicitly set (vs using default)
    /// This is used for profile merging - false means use profile default
    private let severityExplicitlySet: Bool

    public init(
        severity: DiagnosticSeverity = .warning,
        enabled: Bool = true,
        options: [String: String] = [:],
        severityExplicitlySet: Bool = false
    ) {
        self.severity = severity
        self.enabled = enabled
        self.options = options
        self.severityExplicitlySet = severityExplicitlySet
    }
    
    /// Whether the severity was explicitly configured (not just using default)
    public var hasSeverityOverride: Bool {
        return severityExplicitlySet
    }
    
    // Custom Codable implementation to detect explicit severity
    private enum CodingKeys: String, CodingKey {
        case severity, enabled, options
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Check if severity was explicitly provided in YAML
        let explicitSeverity = try container.decodeIfPresent(DiagnosticSeverity.self, forKey: .severity)
        self.severity = explicitSeverity ?? .warning
        self.severityExplicitlySet = explicitSeverity != nil
        
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.options = try container.decodeIfPresent([String: String].self, forKey: .options) ?? [:]
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(severity, forKey: .severity)
        try container.encode(enabled, forKey: .enabled)
        if !options.isEmpty {
            try container.encode(options, forKey: .options)
        }
    }
    
    /// Equatable conformance (ignoring severityExplicitlySet for equality)
    public static func == (lhs: RuleConfiguration, rhs: RuleConfiguration) -> Bool {
        return lhs.severity == rhs.severity &&
               lhs.enabled == rhs.enabled &&
               lhs.options == rhs.options
    }
}

/// Configuration for all rule categories
public struct RulesConfiguration: Codable, Equatable, Sendable {
    public var memory: RuleConfiguration
    public var concurrency: RuleConfiguration
    public var architecture: RuleConfiguration
    public var safety: RuleConfiguration
    public var performance: RuleConfiguration
    public var complexity: RuleConfiguration
    public var monolith: RuleConfiguration
    public var dependency: RuleConfiguration

    public static let `default` = RulesConfiguration(
        memory: RuleConfiguration(),
        concurrency: RuleConfiguration(),
        architecture: RuleConfiguration(),
        safety: RuleConfiguration(),
        performance: RuleConfiguration(),
        complexity: RuleConfiguration(),
        monolith: RuleConfiguration(),
        dependency: RuleConfiguration()
    )

    public init(
        memory: RuleConfiguration = RuleConfiguration(),
        concurrency: RuleConfiguration = RuleConfiguration(),
        architecture: RuleConfiguration = RuleConfiguration(),
        safety: RuleConfiguration = RuleConfiguration(),
        performance: RuleConfiguration = RuleConfiguration(),
        complexity: RuleConfiguration = RuleConfiguration(),
        monolith: RuleConfiguration = RuleConfiguration(),
        dependency: RuleConfiguration = RuleConfiguration()
    ) {
        self.memory = memory
        self.concurrency = concurrency
        self.architecture = architecture
        self.safety = safety
        self.performance = performance
        self.complexity = complexity
        self.monolith = monolith
        self.dependency = dependency
    }

    /// Get configuration for a specific rule category
    public func configuration(for category: RuleCategory) -> RuleConfiguration {
        switch category {
        case .memory:
            return memory
        case .concurrency:
            return concurrency
        case .architecture:
            return architecture
        case .safety:
            return safety
        case .performance:
            return performance
        case .complexity:
            return complexity
        case .monolith:
            return monolith
        case .dependency:
            return dependency
        }
    }

    /// Update configuration for a specific rule category
    public mutating func setConfiguration(_ config: RuleConfiguration, for category: RuleCategory) {
        switch category {
        case .memory:
            memory = config
        case .concurrency:
            concurrency = config
        case .architecture:
            architecture = config
        case .safety:
            safety = config
        case .performance:
            performance = config
        case .complexity:
            complexity = config
        case .monolith:
            monolith = config
        case .dependency:
            dependency = config
        }
    }
}