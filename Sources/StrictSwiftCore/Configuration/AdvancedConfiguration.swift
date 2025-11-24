import Foundation

/// Enhanced configuration system with granular rule control
public struct AdvancedConfiguration: Codable, Equatable, Sendable {
    /// Rule-specific configurations
    public var ruleSettings: [String: RuleSpecificConfiguration]
    /// File pattern-based conditional configurations
    public var conditionalSettings: [ConditionalConfiguration]
    /// Global thresholds for numeric rules
    public var thresholds: ThresholdConfiguration
    /// Performance settings
    public var performanceSettings: PerformanceConfiguration
    /// Analysis scope settings
    public var scopeSettings: ScopeConfiguration

    public init(
        ruleSettings: [String: RuleSpecificConfiguration] = [:],
        conditionalSettings: [ConditionalConfiguration] = [],
        thresholds: ThresholdConfiguration = ThresholdConfiguration(),
        performanceSettings: PerformanceConfiguration = PerformanceConfiguration(),
        scopeSettings: ScopeConfiguration = ScopeConfiguration()
    ) {
        self.ruleSettings = ruleSettings
        self.conditionalSettings = conditionalSettings
        self.thresholds = thresholds
        self.performanceSettings = performanceSettings
        self.scopeSettings = scopeSettings
    }

    /// Get configuration for a specific rule
    public func configuration(for ruleId: String) -> RuleSpecificConfiguration? {
        return ruleSettings[ruleId]
    }

    /// Get conditional configurations that apply to a file
    public func conditionalConfigurations(for file: String) -> [ConditionalConfiguration] {
        return conditionalSettings.filter { $0.matches(file: file) }
    }

    /// Check if a rule should analyze a specific file
    public func shouldAnalyze(ruleId: String, file: String) -> Bool {
        let ruleConfig = configuration(for: ruleId)
        let conditionals = conditionalConfigurations(for: file)

        // Check if rule is explicitly disabled in conditional config
        for conditional in conditionals {
            if let override = conditional.ruleOverrides[ruleId], !override.enabled {
                return false
            }
        }

        // Fall back to rule-specific config
        return ruleConfig?.enabled ?? true
    }

    /// Get effective configuration for a rule analyzing a specific file
    public func effectiveConfiguration(for ruleId: String, file: String) -> RuleSpecificConfiguration {
        let baseConfig = configuration(for: ruleId) ?? RuleSpecificConfiguration(ruleId: ruleId)
        let conditionals = conditionalConfigurations(for: file)

        var effectiveConfig = baseConfig

        // Apply conditional overrides
        for conditional in conditionals {
            if let override = conditional.ruleOverrides[ruleId] {
                effectiveConfig = effectiveConfig.merged(with: override)
            }
        }

        return effectiveConfig
    }
}

/// Configuration specific to individual rules
public struct RuleSpecificConfiguration: Codable, Equatable, Sendable {
    public let ruleId: String
    public let enabled: Bool
    public let severity: DiagnosticSeverity
    public let parameters: [String: ConfigurationValue]
    public let filePatterns: FilePatternConfiguration

    public init(
        ruleId: String,
        enabled: Bool = true,
        severity: DiagnosticSeverity = .warning,
        parameters: [String: ConfigurationValue] = [:],
        filePatterns: FilePatternConfiguration = FilePatternConfiguration()
    ) {
        self.ruleId = ruleId
        self.enabled = enabled
        self.severity = severity
        self.parameters = parameters
        self.filePatterns = filePatterns
    }

    /// Get typed parameter value
    public func parameter<T: ConfigurationValueRepresentable>(_ key: String, defaultValue: T) -> T {
        guard let value = parameters[key] else { return defaultValue }
        return T(from: value) ?? defaultValue
    }

    /// Merge with another configuration (conditional overrides take precedence)
    public func merged(with other: RuleSpecificConfiguration) -> RuleSpecificConfiguration {
        return RuleSpecificConfiguration(
            ruleId: ruleId,
            enabled: other.enabled != enabled ? other.enabled : enabled,
            severity: other.severity != severity ? other.severity : severity,
            parameters: parameters.merging(other.parameters) { _, new in new },
            filePatterns: filePatterns.merged(with: other.filePatterns)
        )
    }
}

/// File pattern configuration for rules
public struct FilePatternConfiguration: Codable, Equatable, Sendable {
    public let include: [String]
    public let exclude: [String]
    public let excludeTestFiles: Bool
    public let excludeGeneratedFiles: Bool

    public init(
        include: [String] = [],
        exclude: [String] = [],
        excludeTestFiles: Bool = false,
        excludeGeneratedFiles: Bool = true
    ) {
        self.include = include
        self.exclude = exclude
        self.excludeTestFiles = excludeTestFiles
        self.excludeGeneratedFiles = excludeGeneratedFiles
    }

    public func merged(with other: FilePatternConfiguration) -> FilePatternConfiguration {
        return FilePatternConfiguration(
            include: include + other.include,
            exclude: exclude + other.exclude,
            excludeTestFiles: other.excludeTestFiles || excludeTestFiles,
            excludeGeneratedFiles: other.excludeGeneratedFiles || excludeGeneratedFiles
        )
    }

    public func shouldInclude(file: String) -> Bool {
        let path = URL(fileURLWithPath: file).path

        // Check if it's a test file
        if excludeTestFiles && (path.contains("Test") || path.contains("test")) {
            return false
        }

        // Check if it's a generated file
        if excludeGeneratedFiles && (
            path.contains(".generated") ||
            path.contains("+") ||
            path.hasSuffix(".pb.swift") ||
            path.hasSuffix(".api.swift")
        ) {
            return false
        }

        // Check explicit excludes
        for pattern in exclude {
            if path.contains(pattern) {
                return false
            }
        }

        // If no includes specified, include everything else
        if include.isEmpty {
            return true
        }

        // Check explicit includes
        for pattern in include {
            if path.contains(pattern) {
                return true
            }
        }

        return false
    }
}

/// Conditional configuration based on file patterns
public struct ConditionalConfiguration: Codable, Equatable, Sendable {
    public let name: String
    public let condition: ConfigurationCondition
    public let ruleOverrides: [String: RuleSpecificConfiguration]
    public let priority: Int

    public init(
        name: String,
        condition: ConfigurationCondition,
        ruleOverrides: [String: RuleSpecificConfiguration] = [:],
        priority: Int = 0
    ) {
        self.name = name
        self.condition = condition
        self.ruleOverrides = ruleOverrides
        self.priority = priority
    }

    public func matches(file: String) -> Bool {
        return condition.matches(file: file)
    }
}

/// Conditions for applying configuration
public indirect enum ConfigurationCondition: Codable, Equatable, Sendable {
    case pathPattern(String)
    case fileName(String)
    case fileExtension(String)
    case directory(String)
    case any([ConfigurationCondition])
    case all([ConfigurationCondition])
    case not(ConfigurationCondition)
    case custom(String) // Custom expression

    public func matches(file: String) -> Bool {
        let url = URL(fileURLWithPath: file)

        switch self {
        case .pathPattern(let pattern):
            return file.contains(pattern) || url.path.contains(pattern)
        case .fileName(let name):
            return url.lastPathComponent == name
        case .fileExtension(let ext):
            return url.pathExtension == ext
        case .directory(let dir):
            return file.contains(dir)
        case .any(let conditions):
            return conditions.contains { $0.matches(file: file) }
        case .all(let conditions):
            return conditions.allSatisfy { $0.matches(file: file) }
        case .not(let condition):
            return !condition.matches(file: file)
        case .custom:
            // For now, return false for custom conditions
            // In the future, this could support expression evaluation
            return false
        }
    }
}

/// Threshold configuration for numeric rules
public struct ThresholdConfiguration: Codable, Equatable, Sendable {
    public let maxCyclomaticComplexity: Int
    public let maxMethodLength: Int
    public let maxTypeComplexity: Int
    public let maxNestingDepth: Int
    public let maxParameterCount: Int
    public let maxPropertyCount: Int
    public let maxFileLength: Int

    public init(
        maxCyclomaticComplexity: Int = 10,
        maxMethodLength: Int = 50,
        maxTypeComplexity: Int = 100,
        maxNestingDepth: Int = 4,
        maxParameterCount: Int = 5,
        maxPropertyCount: Int = 20,
        maxFileLength: Int = 400
    ) {
        self.maxCyclomaticComplexity = maxCyclomaticComplexity
        self.maxMethodLength = maxMethodLength
        self.maxTypeComplexity = maxTypeComplexity
        self.maxNestingDepth = maxNestingDepth
        self.maxParameterCount = maxParameterCount
        self.maxPropertyCount = maxPropertyCount
        self.maxFileLength = maxFileLength
    }
}

/// Performance-related configuration
public struct PerformanceConfiguration: Codable, Equatable, Sendable {
    public let enableParallelAnalysis: Bool
    public let maxParallelFiles: Int
    public let memoryThresholdMB: Int
    public let enableIncrementalAnalysis: Bool
    public let cacheAnalysisResults: Bool
    public let analysisTimeoutSeconds: Int

    public init(
        enableParallelAnalysis: Bool = true,
        maxParallelFiles: Int = 0, // 0 means auto-detect
        memoryThresholdMB: Int = 1024,
        enableIncrementalAnalysis: Bool = false,
        cacheAnalysisResults: Bool = true,
        analysisTimeoutSeconds: Int = 60
    ) {
        self.enableParallelAnalysis = enableParallelAnalysis
        self.maxParallelFiles = maxParallelFiles > 0 ? maxParallelFiles : ProcessInfo.processInfo.processorCount
        self.memoryThresholdMB = memoryThresholdMB
        self.enableIncrementalAnalysis = enableIncrementalAnalysis
        self.cacheAnalysisResults = cacheAnalysisResults
        self.analysisTimeoutSeconds = analysisTimeoutSeconds
    }
}

/// Analysis scope configuration
public struct ScopeConfiguration: Codable, Equatable, Sendable {
    public let analyzeTests: Bool
    public let analyzeExtensions: Bool
    public let analyzeGeneratedCode: Bool
    public let minFileSizeLines: Int
    public let maxFileSizeLines: Int
    public let excludeEmptyFiles: Bool
    public let excludeVendorCode: Bool

    public init(
        analyzeTests: Bool = false,
        analyzeExtensions: Bool = true,
        analyzeGeneratedCode: Bool = false,
        minFileSizeLines: Int = 1,
        maxFileSizeLines: Int = 10000,
        excludeEmptyFiles: Bool = true,
        excludeVendorCode: Bool = true
    ) {
        self.analyzeTests = analyzeTests
        self.analyzeExtensions = analyzeExtensions
        self.analyzeGeneratedCode = analyzeGeneratedCode
        self.minFileSizeLines = minFileSizeLines
        self.maxFileSizeLines = maxFileSizeLines
        self.excludeEmptyFiles = excludeEmptyFiles
        self.excludeVendorCode = excludeVendorCode
    }
}

/// Configuration value that can represent different types
public enum ConfigurationValue: Codable, Equatable, Sendable {
    case stringValue(String)
    case integerValue(Int)
    case doubleValue(Double)
    case booleanValue(Bool)
    case arrayValue([ConfigurationValue])
    case stringArrayValue([String])

    public var stringValue: String {
        switch self {
        case .stringValue(let value): return value
        case .integerValue(let value): return String(value)
        case .doubleValue(let value): return String(value)
        case .booleanValue(let value): return String(value)
        case .arrayValue(let values): return "[\(values.map(\.stringValue).joined(separator: ", "))]"
        case .stringArrayValue(let values): return "[\(values.joined(separator: ", "))]"
        }
    }

    public var integerValue: Int? {
        switch self {
        case .integerValue(let value): return value
        case .stringValue(let value): return Int(value)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .booleanValue(let value): return value
        case .stringValue(let value): return Bool(value.lowercased())
        default: return nil
        }
    }

    public var arrayValue: [ConfigurationValue]? {
        switch self {
        case .arrayValue(let values): return values
        case .stringArrayValue(let values): return values.map { .stringValue($0) }
        default: return nil
        }
    }
}

/// Protocol for types that can be created from ConfigurationValue
public protocol ConfigurationValueRepresentable {
    init?(from value: ConfigurationValue)
}

// Default implementations for common types
extension Int: ConfigurationValueRepresentable {
    public init?(from value: ConfigurationValue) {
        switch value {
        case .integerValue(let intValue): self = intValue
        case .stringValue(let stringValue):
            if let intValue = Int(stringValue) {
                self = intValue
            } else {
                return nil
            }
        default: return nil
        }
    }
}

extension Double: ConfigurationValueRepresentable {
    public init?(from value: ConfigurationValue) {
        switch value {
        case .doubleValue(let doubleValue): self = doubleValue
        case .integerValue(let intValue): self = Double(intValue)
        case .stringValue(let stringValue):
            if let doubleValue = Double(stringValue) {
                self = doubleValue
            } else {
                return nil
            }
        default: return nil
        }
    }
}

extension Bool: ConfigurationValueRepresentable {
    public init?(from value: ConfigurationValue) {
        switch value {
        case .booleanValue(let boolValue): self = boolValue
        case .stringValue(let stringValue):
            switch stringValue.lowercased() {
            case "true", "yes", "1", "on": self = true
            case "false", "no", "0", "off": self = false
            default: return nil
            }
        default: return nil
        }
    }
}

extension String: ConfigurationValueRepresentable {
    public init?(from value: ConfigurationValue) {
        switch value {
        case .stringValue(let stringValue): self = stringValue
        default: self = value.stringValue
        }
    }
}

extension Array: ConfigurationValueRepresentable where Element: ConfigurationValueRepresentable {
    public init?(from value: ConfigurationValue) {
        guard let configValues = value.arrayValue else { return nil }
        self = configValues.compactMap { Element(from: $0) }
    }
}

// MARK: - Convenience Extensions

extension AdvancedConfiguration {
    /// Create configuration for common scenarios
    public static let strict = AdvancedConfiguration(
        thresholds: ThresholdConfiguration(
            maxCyclomaticComplexity: 5,
            maxMethodLength: 30,
            maxTypeComplexity: 50,
            maxNestingDepth: 3,
            maxParameterCount: 4,
            maxPropertyCount: 15,
            maxFileLength: 300
        ),
        performanceSettings: PerformanceConfiguration(
            enableParallelAnalysis: true,
            maxParallelFiles: 8,
            memoryThresholdMB: 2048,
            enableIncrementalAnalysis: true
        ),
        scopeSettings: ScopeConfiguration(
            analyzeTests: true,
            analyzeGeneratedCode: false,
            maxFileSizeLines: 5000
        )
    )

    public static let lenient = AdvancedConfiguration(
        thresholds: ThresholdConfiguration(
            maxCyclomaticComplexity: 20,
            maxMethodLength: 100,
            maxTypeComplexity: 200,
            maxNestingDepth: 6,
            maxParameterCount: 8,
            maxPropertyCount: 30,
            maxFileLength: 1000
        ),
        performanceSettings: PerformanceConfiguration(
            enableParallelAnalysis: false,
            memoryThresholdMB: 512,
            enableIncrementalAnalysis: false
        ),
        scopeSettings: ScopeConfiguration(
            analyzeTests: false,
            analyzeGeneratedCode: true
        )
    )
}