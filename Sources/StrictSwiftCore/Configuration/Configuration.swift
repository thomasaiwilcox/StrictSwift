import Foundation
import Yams
import SystemPackage

/// Main configuration for StrictSwift analysis
public struct Configuration: Codable, Equatable, Sendable {
    /// Profile being used
    public let profile: Profile
    /// Rule configurations
    public let rules: RulesConfiguration
    /// Baseline configuration
    public let baseline: BaselineConfiguration?
    /// Paths to include
    public let include: [String]
    /// Paths to exclude
    public let exclude: [String]
    /// Maximum number of parallel jobs
    public let maxJobs: Int

    public init(
        profile: Profile = .criticalCore,
        rules: RulesConfiguration = RulesConfiguration.default,
        baseline: BaselineConfiguration? = nil,
        include: [String] = [],
        exclude: [String] = [],
        maxJobs: Int = ProcessInfo.processInfo.processorCount
    ) {
        self.profile = profile
        self.rules = rules
        self.baseline = baseline
        self.include = include
        self.exclude = exclude
        self.maxJobs = maxJobs
    }

    /// Default configuration
    public static let `default` = Configuration()

    /// Load configuration from file
    public static func load(from url: URL) throws -> Configuration {
        let data = try Data(contentsOf: url)
        let decoder = YAMLDecoder()
        return try decoder.decode(Configuration.self, from: data)
    }

    /// Load configuration with fallback to profile defaults
    public static func load(from url: URL?, profile: Profile = .criticalCore) -> Configuration {
        guard let url = url, FileManager.default.fileExists(atPath: url.path) else {
            return profile.configuration
        }

        do {
            let config = try load(from: url)
            // Apply profile defaults for any missing values
            return Configuration(
                profile: config.profile,
                rules: mergeWithProfile(config.rules, profile: config.profile),
                baseline: config.baseline,
                include: config.include.isEmpty ? profile.configuration.include : config.include,
                exclude: config.exclude.isEmpty ? profile.configuration.exclude : config.exclude,
                maxJobs: config.maxJobs > 0 ? config.maxJobs : profile.configuration.maxJobs
            )
        } catch {
            print("Warning: Failed to load configuration from \(url.path): \(error)")
            print("Using profile defaults instead")
            return profile.configuration
        }
    }

    /// Save configuration to file
    public func save(to url: URL) throws {
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(self)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Validate configuration
    public func validate() throws {
        guard maxJobs > 0 else {
            throw ConfigurationError.invalidMaxJobs
        }

        // Validate include/exclude patterns
        for pattern in include + exclude {
            guard !pattern.isEmpty else {
                throw ConfigurationError.emptyPattern
            }
        }
    }
}

/// Merge rules with profile defaults
private func mergeWithProfile(_ rules: RulesConfiguration, profile: Profile) -> RulesConfiguration {
    let profileRules = profile.configuration.rules

    return RulesConfiguration(
        memory: rules.memory.enabled ? rules.memory : profileRules.memory,
        concurrency: rules.concurrency.enabled ? rules.concurrency : profileRules.concurrency,
        architecture: rules.architecture.enabled ? rules.architecture : profileRules.architecture,
        safety: rules.safety.enabled ? rules.safety : profileRules.safety,
        performance: rules.performance.enabled ? rules.performance : profileRules.performance,
        complexity: rules.complexity.enabled ? rules.complexity : profileRules.complexity,
        monolith: rules.monolith.enabled ? rules.monolith : profileRules.monolith,
        dependency: rules.dependency.enabled ? rules.dependency : profileRules.dependency
    )
}

/// Configuration errors
public enum ConfigurationError: Error, LocalizedError, Equatable {
    case invalidMaxJobs
    case emptyPattern
    case invalidYAML(String)
    case fileNotFound

    public var errorDescription: String? {
        switch self {
        case .invalidMaxJobs:
            return "maxJobs must be greater than 0"
        case .emptyPattern:
            return "Include and exclude patterns cannot be empty"
        case .invalidYAML(let message):
            return "Invalid YAML: \(message)"
        case .fileNotFound:
            return "Configuration file not found"
        }
    }
}

// MARK: - Profile Defaults

extension Configuration {
    /// Load critical-core profile defaults
    public static func loadCriticalCore() -> Configuration {
        Configuration(
            profile: .criticalCore,
            rules: RulesConfiguration(
                memory: RuleConfiguration(severity: .error),
                concurrency: RuleConfiguration(severity: .error),
                architecture: RuleConfiguration(severity: .error),
                safety: RuleConfiguration(severity: .error),
                performance: RuleConfiguration(severity: .warning),
                complexity: RuleConfiguration(severity: .error),
                monolith: RuleConfiguration(severity: .error),
                dependency: RuleConfiguration(severity: .error)
            ),
            include: ["Sources/", "Tests/"],
            exclude: ["**/.build/**", "**/*.generated.swift"]
        )
    }

    /// Load server-default profile defaults
    public static func loadServerDefault() -> Configuration {
        Configuration(
            profile: .serverDefault,
            rules: RulesConfiguration(
                memory: RuleConfiguration(severity: .warning),
                concurrency: RuleConfiguration(severity: .error),
                architecture: RuleConfiguration(severity: .warning),
                safety: RuleConfiguration(severity: .error),
                performance: RuleConfiguration(severity: .info),
                complexity: RuleConfiguration(severity: .warning),
                monolith: RuleConfiguration(severity: .warning),
                dependency: RuleConfiguration(severity: .error)
            ),
            include: ["Sources/", "Tests/"],
            exclude: ["**/.build/**", "**/*.generated.swift"]
        )
    }

    /// Load library-strict profile defaults
    public static func loadLibraryStrict() -> Configuration {
        Configuration(
            profile: .libraryStrict,
            rules: RulesConfiguration(
                memory: RuleConfiguration(severity: .error),
                concurrency: RuleConfiguration(severity: .error),
                architecture: RuleConfiguration(severity: .warning),
                safety: RuleConfiguration(severity: .error),
                performance: RuleConfiguration(severity: .info),
                complexity: RuleConfiguration(severity: .warning),
                monolith: RuleConfiguration(severity: .info),
                dependency: RuleConfiguration(severity: .warning)
            ),
            include: ["Sources/"],
            exclude: ["**/.build/**", "**/*Tests/**", "**/*.generated.swift"]
        )
    }

    /// Load app-relaxed profile defaults
    public static func loadAppRelaxed() -> Configuration {
        Configuration(
            profile: .appRelaxed,
            rules: RulesConfiguration(
                memory: RuleConfiguration(severity: .info),
                concurrency: RuleConfiguration(severity: .warning),
                architecture: RuleConfiguration(severity: .info),
                safety: RuleConfiguration(severity: .warning),
                performance: RuleConfiguration(severity: .info),
                complexity: RuleConfiguration(severity: .info),
                monolith: RuleConfiguration(severity: .info),
                dependency: RuleConfiguration(severity: .warning)
            ),
            include: ["Sources/"],
            exclude: ["**/.build/**", "**/*.generated.swift"]
        )
    }

    /// Load rust-equivalent profile defaults
    public static func loadRustEquivalent() -> Configuration {
        Configuration(
            profile: .rustEquivalent,
            rules: RulesConfiguration(
                memory: RuleConfiguration(severity: .error),
                concurrency: RuleConfiguration(severity: .error),
                architecture: RuleConfiguration(severity: .error),
                safety: RuleConfiguration(severity: .error),
                performance: RuleConfiguration(severity: .error),
                complexity: RuleConfiguration(severity: .error),
                monolith: RuleConfiguration(severity: .error),
                dependency: RuleConfiguration(severity: .error)
            ),
            include: ["Sources/", "Tests/"],
            exclude: ["**/.build/**", "**/*.generated.swift"]
        )
    }
}