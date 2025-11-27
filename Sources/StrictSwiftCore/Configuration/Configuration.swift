import Foundation
import Yams
import SystemPackage

/// Main configuration for StrictSwift analysis
public struct Configuration: Equatable, Sendable {
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
    /// Advanced configuration with granular control
    public let advanced: AdvancedConfiguration
    /// Whether to use enhanced graph-based rules (requires cross-file analysis)
    public let useEnhancedRules: Bool
    /// Semantic analysis mode for type resolution
    public let semanticMode: SemanticMode?
    /// Whether to fail if semantic mode can't be satisfied (CI gate)
    public let semanticStrict: Bool?
    /// Per-rule semantic mode overrides
    public let perRuleSemanticModes: [String: SemanticMode]?
    /// Per-rule semantic strict overrides
    public let perRuleSemanticStrict: [String: Bool]?

    public init(
        profile: Profile = .criticalCore,
        rules: RulesConfiguration = RulesConfiguration.default,
        baseline: BaselineConfiguration? = nil,
        include: [String] = [],
        exclude: [String] = [],
        maxJobs: Int = ProcessInfo.processInfo.processorCount,
        advanced: AdvancedConfiguration = AdvancedConfiguration(),
        useEnhancedRules: Bool = false,
        semanticMode: SemanticMode? = nil,
        semanticStrict: Bool? = nil,
        perRuleSemanticModes: [String: SemanticMode]? = nil,
        perRuleSemanticStrict: [String: Bool]? = nil
    ) {
        self.profile = profile
        self.rules = rules
        self.baseline = baseline
        self.include = include
        self.exclude = exclude
        self.maxJobs = maxJobs
        self.advanced = advanced
        self.useEnhancedRules = useEnhancedRules
        self.semanticMode = semanticMode
        self.semanticStrict = semanticStrict
        self.perRuleSemanticModes = perRuleSemanticModes
        self.perRuleSemanticStrict = perRuleSemanticStrict
    }
}

// Custom Codable implementation to use defaults for missing keys
extension Configuration: Codable {
    private enum CodingKeys: String, CodingKey {
        case profile, rules, baseline, include, exclude, maxJobs, advanced, useEnhancedRules
        case semanticMode, semanticStrict, perRuleSemanticModes, perRuleSemanticStrict
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.profile = try container.decodeIfPresent(Profile.self, forKey: .profile) ?? .criticalCore
        self.rules = try container.decodeIfPresent(RulesConfiguration.self, forKey: .rules) ?? .default
        self.baseline = try container.decodeIfPresent(BaselineConfiguration.self, forKey: .baseline)
        self.include = try container.decodeIfPresent([String].self, forKey: .include) ?? []
        self.exclude = try container.decodeIfPresent([String].self, forKey: .exclude) ?? []
        self.maxJobs = try container.decodeIfPresent(Int.self, forKey: .maxJobs) ?? ProcessInfo.processInfo.processorCount
        self.advanced = try container.decodeIfPresent(AdvancedConfiguration.self, forKey: .advanced) ?? AdvancedConfiguration()
        self.useEnhancedRules = try container.decodeIfPresent(Bool.self, forKey: .useEnhancedRules) ?? false
        self.semanticMode = try container.decodeIfPresent(SemanticMode.self, forKey: .semanticMode)
        self.semanticStrict = try container.decodeIfPresent(Bool.self, forKey: .semanticStrict)
        self.perRuleSemanticModes = try container.decodeIfPresent([String: SemanticMode].self, forKey: .perRuleSemanticModes)
        self.perRuleSemanticStrict = try container.decodeIfPresent([String: Bool].self, forKey: .perRuleSemanticStrict)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encode(rules, forKey: .rules)
        try container.encodeIfPresent(baseline, forKey: .baseline)
        try container.encode(include, forKey: .include)
        try container.encode(exclude, forKey: .exclude)
        try container.encode(maxJobs, forKey: .maxJobs)
        try container.encode(advanced, forKey: .advanced)
        try container.encode(useEnhancedRules, forKey: .useEnhancedRules)
        try container.encodeIfPresent(semanticMode, forKey: .semanticMode)
        try container.encodeIfPresent(semanticStrict, forKey: .semanticStrict)
        try container.encodeIfPresent(perRuleSemanticModes, forKey: .perRuleSemanticModes)
        try container.encodeIfPresent(perRuleSemanticStrict, forKey: .perRuleSemanticStrict)
    }
}

extension Configuration {
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
                maxJobs: config.maxJobs > 0 ? config.maxJobs : profile.configuration.maxJobs,
                advanced: config.advanced,
                useEnhancedRules: config.useEnhancedRules
            )
        } catch {
            StrictSwiftLogger.warning("Failed to load configuration from \(url.path): \(error)")
            StrictSwiftLogger.info("Using profile defaults instead")
            return profile.configuration
        }
    }

    /// Save configuration to file
    public func save(to url: URL) throws {
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(self)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Auto-discover configuration file in a directory
    /// Searches for configuration files in the following order:
    /// 1. .strictswift.yml / .strictswift.yaml (hidden config)
    /// 2. strictswift.yml / strictswift.yaml (visible config)
    /// 3. .strictswift/config.yml / .strictswift/config.yaml (directory config)
    /// - Parameter directory: The directory to search in
    /// - Returns: URL to the found configuration file, or nil if not found
    public static func discover(in directory: URL) -> URL? {
        let configNames = [
            ".strictswift.yml",
            ".strictswift.yaml",
            "strictswift.yml",
            "strictswift.yaml",
            ".strictswift/config.yml",
            ".strictswift/config.yaml"
        ]
        
        for name in configNames {
            let configURL = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: configURL.path) {
                return configURL
            }
        }
        
        return nil
    }
    
    /// Auto-discover and load configuration from a directory
    /// - Parameters:
    ///   - directory: The directory to search in
    ///   - fallbackProfile: Profile to use if no configuration is found
    /// - Returns: Loaded configuration or profile defaults
    public static func discoverAndLoad(
        in directory: URL,
        fallbackProfile: Profile = .criticalCore
    ) -> Configuration {
        guard let configURL = discover(in: directory) else {
            StrictSwiftLogger.info("No configuration file found, using \(fallbackProfile) profile")
            return fallbackProfile.configuration
        }
        
        StrictSwiftLogger.info("Found configuration at \(configURL.path)")
        return load(from: configURL, profile: fallbackProfile)
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

        // Validate advanced configuration
        try validateAdvancedConfiguration()
    }

    /// Validate advanced configuration settings
    private func validateAdvancedConfiguration() throws {
        let thresholds = advanced.thresholds

        guard thresholds.maxCyclomaticComplexity > 0 else {
            throw ConfigurationError.invalidThreshold("maxCyclomaticComplexity must be > 0")
        }

        guard thresholds.maxMethodLength > 0 else {
            throw ConfigurationError.invalidThreshold("maxMethodLength must be > 0")
        }

        guard thresholds.maxTypeComplexity > 0 else {
            throw ConfigurationError.invalidThreshold("maxTypeComplexity must be > 0")
        }

        guard thresholds.maxNestingDepth > 0 else {
            throw ConfigurationError.invalidThreshold("maxNestingDepth must be > 0")
        }

        guard thresholds.maxParameterCount >= 0 else {
            throw ConfigurationError.invalidThreshold("maxParameterCount must be >= 0")
        }

        guard thresholds.maxPropertyCount >= 0 else {
            throw ConfigurationError.invalidThreshold("maxPropertyCount must be >= 0")
        }

        guard thresholds.maxFileLength > 0 else {
            throw ConfigurationError.invalidThreshold("maxFileLength must be > 0")
        }
    }

    /// Get effective configuration for a specific rule and file
    public func configuration(for ruleId: String, file: String? = nil) -> RuleSpecificConfiguration {
        let file = file ?? ""

        // Get rule-specific configuration from advanced config
        let ruleConfig = advanced.effectiveConfiguration(for: ruleId, file: file)

        // Get category-level configuration as fallback
        let category = RuleEngine.ruleCategory(for: ruleId)
        let categoryConfig = rules.configuration(for: category)

        // Start with global thresholds as default parameters
        var mergedParameters = ruleConfig.parameters
        let thresholds = advanced.thresholds
        
        // Apply global thresholds as defaults (rule-specific params take precedence)
        if mergedParameters["maxCyclomaticComplexity"] == nil {
            mergedParameters["maxCyclomaticComplexity"] = .integerValue(thresholds.maxCyclomaticComplexity)
        }
        if mergedParameters["maxLines"] == nil && mergedParameters["maxFileLines"] == nil {
            mergedParameters["maxLines"] = .integerValue(thresholds.maxFileLength)
            mergedParameters["maxFileLines"] = .integerValue(thresholds.maxFileLength)
        }
        if mergedParameters["maxFunctionLines"] == nil && mergedParameters["maxMethodLength"] == nil {
            mergedParameters["maxFunctionLines"] = .integerValue(thresholds.maxMethodLength)
            mergedParameters["maxMethodLength"] = .integerValue(thresholds.maxMethodLength)
        }
        if mergedParameters["maxNestingDepth"] == nil {
            mergedParameters["maxNestingDepth"] = .integerValue(thresholds.maxNestingDepth)
        }
        if mergedParameters["maxPropertyCount"] == nil {
            mergedParameters["maxPropertyCount"] = .integerValue(thresholds.maxPropertyCount)
        }
        if mergedParameters["maxParameterCount"] == nil {
            mergedParameters["maxParameterCount"] = .integerValue(thresholds.maxParameterCount)
        }

        // Merge configurations with rule config taking precedence
        // Rule configuration always overrides category configuration for severity
        // This allows users to downgrade rules from error to warning or info
        return RuleSpecificConfiguration(
            ruleId: ruleId,
            enabled: ruleConfig.enabled && categoryConfig.enabled,
            severity: ruleConfig.severity,
            parameters: mergedParameters,
            filePatterns: ruleConfig.filePatterns
        )
    }

    /// Check if a rule should analyze a specific file
    public func shouldAnalyze(ruleId: String, file: String) -> Bool {
        // Check advanced configuration first
        if !advanced.shouldAnalyze(ruleId: ruleId, file: file) {
            return false
        }

        // Check scope settings
        return advanced.scopeSettings.shouldAnalyze(file: file)
    }

      /// Set a parameter for a specific rule
    public mutating func setRuleParameter(_ ruleId: String, _ parameter: String, value: Any) {
        var ruleConfig = advanced.configuration(for: ruleId) ?? RuleSpecificConfiguration(ruleId: ruleId)
        var newParameters = ruleConfig.parameters
        newParameters[parameter] = ConfigurationValue.create(value)

        ruleConfig.parameters = newParameters
        var newRuleSettings = advanced.ruleSettings
        newRuleSettings[ruleId] = ruleConfig

        // Create new advanced configuration with updated rule settings while preserving all other state
        let newAdvanced = AdvancedConfiguration(
            ruleSettings: newRuleSettings,
            conditionalSettings: advanced.conditionalSettings,
            thresholds: advanced.thresholds,
            performanceSettings: advanced.performanceSettings,
            scopeSettings: advanced.scopeSettings
        )

        // Update only the advanced configuration, preserving all other fields
        self = Configuration(
            profile: profile,
            rules: rules,
            baseline: baseline,
            include: include,
            exclude: exclude,
            maxJobs: maxJobs,
            advanced: newAdvanced
        )
    }

    /// Enable or disable a specific rule
    public mutating func enableRule(_ ruleId: String, enabled: Bool) {
        let existingConfig = advanced.configuration(for: ruleId)
        let ruleConfig = RuleSpecificConfiguration(
            ruleId: ruleId,
            enabled: enabled,
            severity: existingConfig?.severity ?? .warning,
            parameters: existingConfig?.parameters ?? [:],
            filePatterns: existingConfig?.filePatterns ?? FilePatternConfiguration()
        )

        var newRuleSettings = advanced.ruleSettings
        newRuleSettings[ruleId] = ruleConfig

        // Create new advanced configuration with updated rule settings while preserving all other state
        let newAdvanced = AdvancedConfiguration(
            ruleSettings: newRuleSettings,
            conditionalSettings: advanced.conditionalSettings,
            thresholds: advanced.thresholds,
            performanceSettings: advanced.performanceSettings,
            scopeSettings: advanced.scopeSettings
        )

        // Update only the advanced configuration, preserving all other fields
        self = Configuration(
            profile: profile,
            rules: rules,
            baseline: baseline,
            include: include,
            exclude: exclude,
            maxJobs: maxJobs,
            advanced: newAdvanced
        )
    }

    /// Create a copy of the configuration with modified rule settings (immutable approach)
    public func withRuleParameter(_ ruleId: String, _ parameter: String, value: Any) -> Configuration {
        var copy = self
        copy.setRuleParameter(ruleId, parameter, value: value)
        return copy
    }

    /// Create a copy of the configuration with modified rule enabled state (immutable approach)
    public func withRuleEnabled(_ ruleId: String, enabled: Bool) -> Configuration {
        var copy = self
        copy.enableRule(ruleId, enabled: enabled)
        return copy
    }

    /// Export configuration as YAML
    public func exportYAML() throws -> String {
        let encoder = YAMLEncoder()
        return try encoder.encode(self)
    }

    /// Create configuration for specific use case
    public static func forUseCase(_ useCase: ConfigurationUseCase) -> Configuration {
        switch useCase {
        case .production:
            return Configuration(
                profile: .criticalCore,
                advanced: .strict
            )
        case .development:
            return Configuration(
                profile: .serverDefault,
                advanced: AdvancedConfiguration(
                    scopeSettings: ScopeConfiguration(
                        analyzeTests: true,
                        maxFileSizeLines: 5000
                    )
                )
            )
        case .openSource:
            return Configuration(
                profile: .libraryStrict,
                advanced: AdvancedConfiguration(
                    thresholds: ThresholdConfiguration(
                        maxCyclomaticComplexity: 15,
                        maxMethodLength: 75
                    )
                )
            )
        case .educational:
            return Configuration(
                profile: .appRelaxed,
                advanced: .lenient
            )
        }
    }
}

/// Merge rules with profile defaults
/// - If category is disabled in YAML, keep it disabled
/// - If severity was explicitly set in YAML, use YAML severity
/// - Otherwise, use profile's severity (preserving profile defaults)
private func mergeWithProfile(_ rules: RulesConfiguration, profile: Profile) -> RulesConfiguration {
    let profileRules = profile.configuration.rules

    return RulesConfiguration(
        memory: mergeCategory(yaml: rules.memory, profile: profileRules.memory),
        concurrency: mergeCategory(yaml: rules.concurrency, profile: profileRules.concurrency),
        architecture: mergeCategory(yaml: rules.architecture, profile: profileRules.architecture),
        safety: mergeCategory(yaml: rules.safety, profile: profileRules.safety),
        performance: mergeCategory(yaml: rules.performance, profile: profileRules.performance),
        complexity: mergeCategory(yaml: rules.complexity, profile: profileRules.complexity),
        monolith: mergeCategory(yaml: rules.monolith, profile: profileRules.monolith),
        dependency: mergeCategory(yaml: rules.dependency, profile: profileRules.dependency),
        security: mergeCategory(yaml: rules.security, profile: profileRules.security),
        testing: mergeCategory(yaml: rules.testing, profile: profileRules.testing)
    )
}

/// Merge a single category with profile defaults
private func mergeCategory(yaml: RuleConfiguration, profile: RuleConfiguration) -> RuleConfiguration {
    // If user explicitly disabled the category, honor that
    // Preserve their severity/options settings so re-enabling doesn't lose them
    if !yaml.enabled {
        // Use YAML severity if explicitly set, otherwise use profile severity
        let effectiveSeverity = yaml.hasSeverityOverride ? yaml.severity : profile.severity
        
        return RuleConfiguration(
            severity: effectiveSeverity,
            enabled: false,
            options: yaml.options,
            severityExplicitlySet: yaml.hasSeverityOverride,
            optionsExplicitlySet: yaml.hasOptionsOverride
        )
    }
    
    // Use YAML severity if explicitly set, otherwise use profile severity
    let effectiveSeverity = yaml.hasSeverityOverride ? yaml.severity : profile.severity
    
    // Use YAML options if explicitly set (even if empty), otherwise use profile options
    let effectiveOptions = yaml.hasOptionsOverride ? yaml.options : profile.options
    
    return RuleConfiguration(
        severity: effectiveSeverity,
        enabled: true,
        options: effectiveOptions,
        severityExplicitlySet: yaml.hasSeverityOverride,
        optionsExplicitlySet: yaml.hasOptionsOverride
    )
}

/// Configuration errors
public enum ConfigurationError: Error, LocalizedError, Equatable {
    case invalidMaxJobs
    case emptyPattern
    case invalidYAML(String)
    case fileNotFound
    case invalidThreshold(String)
    case invalidRuleConfiguration(String)
    case conflictingConfigurations

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
        case .invalidThreshold(let message):
            return "Invalid threshold: \(message)"
        case .invalidRuleConfiguration(let message):
            return "Invalid rule configuration: \(message)"
        case .conflictingConfigurations:
            return "Conflicting configuration settings detected"
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
                dependency: RuleConfiguration(severity: .error),
                security: RuleConfiguration(severity: .error),
                testing: RuleConfiguration(severity: .warning)
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
                dependency: RuleConfiguration(severity: .error),
                security: RuleConfiguration(severity: .error),
                testing: RuleConfiguration(severity: .warning)
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
                dependency: RuleConfiguration(severity: .warning),
                security: RuleConfiguration(severity: .error),
                testing: RuleConfiguration(severity: .warning)
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
                dependency: RuleConfiguration(severity: .warning),
                security: RuleConfiguration(severity: .warning),
                testing: RuleConfiguration(severity: .info)
            ),
            include: ["Sources/"],
            exclude: ["**/.build/**", "**/*.generated.swift"]
        )
    }

    /// Load rust-inspired profile defaults
    public static func loadRustInspired() -> Configuration {
        Configuration(
            profile: .rustInspired,
            rules: RulesConfiguration(
                memory: RuleConfiguration(severity: .error),
                concurrency: RuleConfiguration(severity: .error),
                architecture: RuleConfiguration(severity: .error),
                safety: RuleConfiguration(severity: .error),
                performance: RuleConfiguration(severity: .error),
                complexity: RuleConfiguration(severity: .error),
                monolith: RuleConfiguration(severity: .error),
                dependency: RuleConfiguration(severity: .error),
                security: RuleConfiguration(severity: .error),
                testing: RuleConfiguration(severity: .error)
            ),
            include: ["Sources/", "Tests/"],
            exclude: ["**/.build/**", "**/*.generated.swift"]
        )
    }
}

// MARK: - Semantic Configurable Conformance

extension Configuration: SemanticConfigurable {}