import Foundation

/// Configuration for individual rules or rule categories
public struct RuleConfiguration: Codable, Equatable, Sendable {
    public let severity: DiagnosticSeverity
    public let enabled: Bool
    public let options: [String: String]

    public init(
        severity: DiagnosticSeverity = .warning,
        enabled: Bool = true,
        options: [String: String] = [:]
    ) {
        self.severity = severity
        self.enabled = enabled
        self.options = options
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