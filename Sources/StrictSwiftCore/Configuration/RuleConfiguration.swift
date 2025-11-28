import Foundation

/// Configuration for individual rules or rule categories
public struct RuleConfiguration: Codable, Equatable, Sendable {
    public let severity: DiagnosticSeverity
    public let enabled: Bool
    public let options: [String: String]
    
    /// Tracks whether severity was explicitly set (vs using default)
    /// This is used for profile merging - false means use profile default
    private let severityExplicitlySet: Bool
    
    /// Tracks whether options was explicitly set (even if empty)
    /// This distinguishes "options: {}" (clear profile options) from omitted (use profile options)
    private let optionsExplicitlySet: Bool

    public init(
        severity: DiagnosticSeverity = .warning,
        enabled: Bool = true,
        options: [String: String] = [:],
        severityExplicitlySet: Bool = false,
        optionsExplicitlySet: Bool = false
    ) {
        self.severity = severity
        self.enabled = enabled
        self.options = options
        self.severityExplicitlySet = severityExplicitlySet
        self.optionsExplicitlySet = optionsExplicitlySet
    }
    
    /// Whether the severity was explicitly configured (not just using default)
    public var hasSeverityOverride: Bool {
        return severityExplicitlySet
    }
    
    /// Whether options was explicitly configured (even if empty, meaning user wants no options)
    public var hasOptionsOverride: Bool {
        return optionsExplicitlySet
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
        
        // Check if options was explicitly provided (even if empty)
        // We use contains() to detect if the key exists at all
        self.optionsExplicitlySet = container.contains(.options)
        self.options = try container.decodeIfPresent([String: String].self, forKey: .options) ?? [:]
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Only encode severity if it was explicitly set (preserves round-trip intent)
        if severityExplicitlySet {
            try container.encode(severity, forKey: .severity)
        }
        
        try container.encode(enabled, forKey: .enabled)
        
        // Only encode options if explicitly set (even if empty - user wants no options)
        if optionsExplicitlySet {
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
    public var security: RuleConfiguration
    public var testing: RuleConfiguration

    public static let `default` = RulesConfiguration(
        memory: RuleConfiguration(),
        concurrency: RuleConfiguration(),
        architecture: RuleConfiguration(),
        safety: RuleConfiguration(),
        performance: RuleConfiguration(),
        complexity: RuleConfiguration(),
        monolith: RuleConfiguration(),
        dependency: RuleConfiguration(),
        security: RuleConfiguration(),
        testing: RuleConfiguration()
    )

    public init(
        memory: RuleConfiguration = RuleConfiguration(),
        concurrency: RuleConfiguration = RuleConfiguration(),
        architecture: RuleConfiguration = RuleConfiguration(),
        safety: RuleConfiguration = RuleConfiguration(),
        performance: RuleConfiguration = RuleConfiguration(),
        complexity: RuleConfiguration = RuleConfiguration(),
        monolith: RuleConfiguration = RuleConfiguration(),
        dependency: RuleConfiguration = RuleConfiguration(),
        security: RuleConfiguration = RuleConfiguration(),
        testing: RuleConfiguration = RuleConfiguration()
    ) {
        self.memory = memory
        self.concurrency = concurrency
        self.architecture = architecture
        self.safety = safety
        self.performance = performance
        self.complexity = complexity
        self.monolith = monolith
        self.dependency = dependency
        self.security = security
        self.testing = testing
    }
    
    // Custom Codable implementation to use defaults for missing keys
    private enum CodingKeys: String, CodingKey {
        case memory, concurrency, architecture, safety, performance, complexity, monolith, dependency, security, testing
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultConfig = RuleConfiguration()
        
        self.memory = try container.decodeIfPresent(RuleConfiguration.self, forKey: .memory) ?? defaultConfig
        self.concurrency = try container.decodeIfPresent(RuleConfiguration.self, forKey: .concurrency) ?? defaultConfig
        self.architecture = try container.decodeIfPresent(RuleConfiguration.self, forKey: .architecture) ?? defaultConfig
        self.safety = try container.decodeIfPresent(RuleConfiguration.self, forKey: .safety) ?? defaultConfig
        self.performance = try container.decodeIfPresent(RuleConfiguration.self, forKey: .performance) ?? defaultConfig
        self.complexity = try container.decodeIfPresent(RuleConfiguration.self, forKey: .complexity) ?? defaultConfig
        self.monolith = try container.decodeIfPresent(RuleConfiguration.self, forKey: .monolith) ?? defaultConfig
        self.dependency = try container.decodeIfPresent(RuleConfiguration.self, forKey: .dependency) ?? defaultConfig
        self.security = try container.decodeIfPresent(RuleConfiguration.self, forKey: .security) ?? defaultConfig
        self.testing = try container.decodeIfPresent(RuleConfiguration.self, forKey: .testing) ?? defaultConfig
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
        case .security:
            return security
        case .testing:
            return testing
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
        case .security:
            security = config
        case .testing:
            testing = config
        }
    }
}