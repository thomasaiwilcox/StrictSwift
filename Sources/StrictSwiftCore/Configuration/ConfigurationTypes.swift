import Foundation

/// Configuration use cases for different development scenarios
public enum ConfigurationUseCase: String, CaseIterable, Codable, Sendable {
    case production = "production"
    case development = "development"
    case openSource = "open_source"
    case educational = "educational"

    public var description: String {
        switch self {
        case .production:
            return "Production environment with strictest rules"
        case .development:
            return "Development environment with balanced rules"
        case .openSource:
            return "Open source project with community-friendly rules"
        case .educational:
            return "Educational projects with lenient rules"
        }
    }
}

/// Extension for scope configuration file analysis
extension ScopeConfiguration {
    /// Check if a file should be analyzed based on scope settings
    public func shouldAnalyze(file: String) -> Bool {
        let url = URL(fileURLWithPath: file)

        // Check if it's a test file
        if !analyzeTests {
            let fileName = url.lastPathComponent.lowercased()
            let filePath = url.path.lowercased()

            if fileName.contains("test") ||
               filePath.contains("/test/") ||
               filePath.contains("/tests/") ||
               fileName.hasSuffix("test.swift") ||
               fileName.hasSuffix("tests.swift") {
                return false
            }
        }

        // Check if it's a generated file
        if !analyzeGeneratedCode {
            let fileName = url.lastPathComponent.lowercased()

            if fileName.hasSuffix(".generated.swift") ||
               fileName.contains("+") ||
               fileName.hasSuffix(".pb.swift") ||
               fileName.hasSuffix(".api.swift") {
                return false
            }
        }

        // Check vendor code
        if excludeVendorCode {
            let path = url.path.lowercased()
            if path.contains("/vendor/") ||
               path.contains("/third_party/") ||
               path.contains("/thirdparty/") ||
               path.contains("/pods/") ||
               path.contains("/carthage/") ||
               path.contains("/spm/") {
                return false
            }
        }

        return true
    }

    /// Check if file meets size requirements
    public func meetsSizeRequirements(lineCount: Int) -> Bool {
        if excludeEmptyFiles && lineCount == 0 {
            return false
        }

        if lineCount < minFileSizeLines {
            return false
        }

        if lineCount > maxFileSizeLines {
            return false
        }

        return true
    }
}

/// Predefined rule configurations for common rules
extension RuleSpecificConfiguration {
    /// Configuration for complexity-related rules
    public static func complexity(
        enabled: Bool = true,
        severity: DiagnosticSeverity = .warning,
        maxComplexity: Int = 10
    ) -> RuleSpecificConfiguration {
        return RuleSpecificConfiguration(
            ruleId: "complexity",
            enabled: enabled,
            severity: severity,
            parameters: [
                "maxCyclomaticComplexity": .integerValue(maxComplexity),
                "maxNestingDepth": .integerValue(4),
                "maxParameterCount": .integerValue(5)
            ]
        )
    }

    /// Configuration for memory-related rules
    public static func memory(
        enabled: Bool = true,
        severity: DiagnosticSeverity = .error,
        allowForceUnwraps: Bool = false
    ) -> RuleSpecificConfiguration {
        return RuleSpecificConfiguration(
            ruleId: "memory",
            enabled: enabled,
            severity: severity,
            parameters: [
                "allowForceUnwraps": .booleanValue(allowForceUnwraps),
                "allowForceTry": .booleanValue(false),
                "allowImplicitUnwraps": .booleanValue(false)
            ]
        )
    }

    /// Configuration for concurrency rules
    public static func concurrency(
        enabled: Bool = true,
        severity: DiagnosticSeverity = .error,
        allowUnstructuredTasks: Bool = false
    ) -> RuleSpecificConfiguration {
        return RuleSpecificConfiguration(
            ruleId: "concurrency",
            enabled: enabled,
            severity: severity,
            parameters: [
                "allowUnstructuredTasks": .booleanValue(allowUnstructuredTasks),
                "requireAsyncAwait": .booleanValue(true),
                "checkDataRaces": .booleanValue(true)
            ]
        )
    }

    /// Configuration for architecture rules
    public static func architecture(
        enabled: Bool = true,
        severity: DiagnosticSeverity = .warning,
        enforceLayering: Bool = true
    ) -> RuleSpecificConfiguration {
        return RuleSpecificConfiguration(
            ruleId: "architecture",
            enabled: enabled,
            severity: severity,
            parameters: [
                "enforceLayering": .booleanValue(enforceLayering),
                "allowCircularDependencies": .booleanValue(false),
                "maxDependencyDepth": .integerValue(5)
            ]
        )
    }

    /// Configuration for safety rules
    public static func safety(
        enabled: Bool = true,
        severity: DiagnosticSeverity = .error,
        allowFatalErrors: Bool = false
    ) -> RuleSpecificConfiguration {
        return RuleSpecificConfiguration(
            ruleId: "safety",
            enabled: enabled,
            severity: severity,
            parameters: [
                "allowFatalErrors": .booleanValue(allowFatalErrors),
                "allowAssertions": .booleanValue(true),
                "checkNilCoalescing": .booleanValue(true)
            ]
        )
    }
}

/// Convenience extensions for ConfigurationValue
extension ConfigurationValue {
    /// Create from Swift literal
    public static func string(_ value: String) -> ConfigurationValue {
        return .stringValue(value)
    }

    /// Create from Any value (for configuration API)
    public static func from(_ value: Any) -> ConfigurationValue {
        if let stringValue = value as? String {
            return .stringValue(stringValue)
        } else if let intValue = value as? Int {
            return .integerValue(intValue)
        } else if let doubleValue = value as? Double {
            return .doubleValue(doubleValue)
        } else if let boolValue = value as? Bool {
            return .booleanValue(boolValue)
        } else if let arrayValue = value as? [String] {
            return .stringArrayValue(arrayValue)
        } else if let arrayValue = value as? [ConfigurationValue] {
            return .arrayValue(arrayValue)
        } else {
            return .stringValue(String(describing: value))
        }
    }

    public static func integer(_ value: Int) -> ConfigurationValue {
        return .integerValue(value)
    }

    public static func double(_ value: Double) -> ConfigurationValue {
        return .doubleValue(value)
    }

    public static func boolean(_ value: Bool) -> ConfigurationValue {
        return .booleanValue(value)
    }

    public static func array(_ values: [ConfigurationValue]) -> ConfigurationValue {
        return .arrayValue(values)
    }

    public static func stringArray(_ values: [String]) -> ConfigurationValue {
        return .stringArrayValue(values)
    }
}

/// Predefined conditional configurations
public extension ConditionalConfiguration {
    /// Configuration for test files
    static let testFiles = ConditionalConfiguration(
        name: "Test Files",
        condition: .any([
            .pathPattern("Test"),
            .directory("Tests"),
            .fileExtension("xctest")
        ]),
        ruleOverrides: [
            "force_unwrap": RuleSpecificConfiguration(
                ruleId: "force_unwrap",
                enabled: true,
                severity: .warning // More lenient in tests
            ),
            "fatal_error": RuleSpecificConfiguration(
                ruleId: "fatal_error",
                enabled: true,
                severity: .warning
            )
        ]
    )

    /// Configuration for generated code
    static let generatedCode = ConditionalConfiguration(
        name: "Generated Code",
        condition: .any([
            .pathPattern(".generated"),
            .pathPattern("+"),
            .pathPattern(".pb"),
            .directory("Generated")
        ]),
        ruleOverrides: [:] // Disable most rules for generated code
    )

    /// Configuration for vendor/third party code
    static let vendorCode = ConditionalConfiguration(
        name: "Vendor Code",
        condition: .any([
            .directory("Vendor"),
            .directory("ThirdParty"),
            .directory("Pods"),
            .directory("Carthage")
        ]),
        ruleOverrides: [:] // Disable all rules for vendor code
    )
}

