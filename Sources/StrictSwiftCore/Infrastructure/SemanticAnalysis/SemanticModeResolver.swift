import Foundation

// MARK: - Semantic Mode Resolver

/// Resolves the effective semantic mode from layered configuration sources
/// 
/// Configuration precedence (highest to lowest):
/// 1. CLI flags (--semantic, --semantic-strict)
/// 2. Environment variables (STRICTSWIFT_SEMANTIC_MODE, STRICTSWIFT_SEMANTIC_STRICT)
/// 3. VS Code extension settings (passed via environment or file)
/// 4. Per-rule YAML configuration (rules.dead_code.semantic_mode)
/// 5. Project YAML configuration (semantic_mode at root level)
/// 6. Auto-detection based on environment capabilities
public final class SemanticModeResolver: Sendable {
    private let capabilities: SemanticCapabilities
    private let projectRoot: URL
    
    /// Configuration sources with their resolved values
    public struct ResolvedConfiguration: Sendable {
        /// The final resolved mode after layering
        public let effectiveMode: SemanticMode
        
        /// Whether strict mode is enabled (fail on degradation)
        public let isStrict: Bool
        
        /// The source that determined the mode
        public let modeSource: ConfigurationSource
        
        /// Any degradation that occurred
        public let degradation: Degradation?
        
        /// All sources that were checked
        public let checkedSources: [SourceResult]
        
        public struct Degradation: Sendable {
            public let requestedMode: SemanticMode
            public let actualMode: SemanticMode
            public let reason: String
        }
        
        public struct SourceResult: Sendable {
            public let source: ConfigurationSource
            public let value: SemanticMode?
            public let isStrict: Bool?
        }
    }
    
    /// Where a configuration value came from
    public enum ConfigurationSource: String, Sendable, CaseIterable {
        case cli = "CLI"
        case environment = "Environment"
        case vsCodeSettings = "VS Code Settings"
        case perRuleYAML = "Per-rule YAML"
        case projectYAML = "Project YAML"
        case autoDetected = "Auto-detected"
        
        public var priority: Int {
            switch self {
            case .cli: return 100
            case .environment: return 90
            case .vsCodeSettings: return 80
            case .perRuleYAML: return 70
            case .projectYAML: return 60
            case .autoDetected: return 0
            }
        }
    }
    
    public init(capabilities: SemanticCapabilities, projectRoot: URL) {
        self.capabilities = capabilities
        self.projectRoot = projectRoot
    }
    
    // MARK: - Resolution
    
    /// Resolve the effective semantic mode from all configuration sources
    /// - Parameters:
    ///   - cliMode: Mode specified on CLI (--semantic flag)
    ///   - cliStrict: Whether --semantic-strict was specified
    ///   - ruleName: Optional rule name for per-rule configuration
    ///   - yamlConfig: The project's YAML configuration
    /// - Returns: The resolved configuration with source tracking
    public func resolve(
        cliMode: SemanticMode? = nil,
        cliStrict: Bool = false,
        ruleName: String? = nil,
        yamlConfig: SemanticModeYAMLConfig? = nil
    ) -> ResolvedConfiguration {
        var checkedSources: [ResolvedConfiguration.SourceResult] = []
        
        // 1. Check CLI (highest priority)
        let cliResult = checkCLI(mode: cliMode, strict: cliStrict)
        checkedSources.append(cliResult)
        
        // 2. Check environment variables
        let envResult = checkEnvironment()
        checkedSources.append(envResult)
        
        // 3. Check VS Code settings
        let vsCodeResult = checkVSCodeSettings()
        checkedSources.append(vsCodeResult)
        
        // 4. Check per-rule YAML (if rule name provided)
        if let ruleName = ruleName {
            let perRuleResult = checkPerRuleYAML(ruleName: ruleName, config: yamlConfig)
            checkedSources.append(perRuleResult)
        }
        
        // 5. Check project YAML
        let yamlResult = checkProjectYAML(config: yamlConfig)
        checkedSources.append(yamlResult)
        
        // 6. Auto-detect
        let autoResult = ResolvedConfiguration.SourceResult(
            source: .autoDetected,
            value: capabilities.bestAvailableMode,
            isStrict: false
        )
        checkedSources.append(autoResult)
        
        // Find the highest-priority source with a value
        let sortedSources = checkedSources
            .filter { $0.value != nil }
            .sorted { $0.source.priority > $1.source.priority }
        
        let winningSouce = sortedSources.first ?? autoResult
        let requestedMode = winningSouce.value ?? .auto
        
        // Determine strict mode (also layered)
        let isStrict = sortedSources
            .first { $0.isStrict == true }
            .map { _ in true } ?? false
        
        // Apply degradation if necessary
        let (effectiveMode, degradationReason) = capabilities.degrade(requestedMode)
        
        let degradation: ResolvedConfiguration.Degradation?
        if let reason = degradationReason {
            degradation = ResolvedConfiguration.Degradation(
                requestedMode: requestedMode,
                actualMode: effectiveMode,
                reason: reason
            )
        } else {
            degradation = nil
        }
        
        return ResolvedConfiguration(
            effectiveMode: effectiveMode,
            isStrict: isStrict,
            modeSource: winningSouce.source,
            degradation: degradation,
            checkedSources: checkedSources
        )
    }
    
    // MARK: - Source Checking
    
    private func checkCLI(mode: SemanticMode?, strict: Bool) -> ResolvedConfiguration.SourceResult {
        return ResolvedConfiguration.SourceResult(
            source: .cli,
            value: mode,
            isStrict: strict ? true : nil
        )
    }
    
    private func checkEnvironment() -> ResolvedConfiguration.SourceResult {
        let env = ProcessInfo.processInfo.environment
        
        let mode: SemanticMode?
        if let modeStr = env["STRICTSWIFT_SEMANTIC_MODE"]?.lowercased() {
            mode = SemanticMode(rawValue: modeStr)
        } else {
            mode = nil
        }
        
        let isStrict: Bool?
        if let strictStr = env["STRICTSWIFT_SEMANTIC_STRICT"]?.lowercased() {
            isStrict = ["1", "true", "yes"].contains(strictStr)
        } else {
            isStrict = nil
        }
        
        return ResolvedConfiguration.SourceResult(
            source: .environment,
            value: mode,
            isStrict: isStrict
        )
    }
    
    private func checkVSCodeSettings() -> ResolvedConfiguration.SourceResult {
        // VS Code extension can pass settings via:
        // 1. Environment variables prefixed with VSCODE_
        // 2. A settings file in .vscode/ directory
        
        let env = ProcessInfo.processInfo.environment
        
        // Check VS Code-specific environment variables
        let mode: SemanticMode?
        if let modeStr = env["VSCODE_STRICTSWIFT_SEMANTIC_MODE"]?.lowercased() {
            mode = SemanticMode(rawValue: modeStr)
        } else {
            mode = nil
        }
        
        let isStrict: Bool?
        if let strictStr = env["VSCODE_STRICTSWIFT_SEMANTIC_STRICT"]?.lowercased() {
            isStrict = ["1", "true", "yes"].contains(strictStr)
        } else {
            isStrict = nil
        }
        
        // If not in env, check VS Code settings file
        if mode == nil && isStrict == nil {
            if let settings = loadVSCodeSettings() {
                return ResolvedConfiguration.SourceResult(
                    source: .vsCodeSettings,
                    value: settings.mode,
                    isStrict: settings.strict
                )
            }
        }
        
        return ResolvedConfiguration.SourceResult(
            source: .vsCodeSettings,
            value: mode,
            isStrict: isStrict
        )
    }
    
    private func checkPerRuleYAML(ruleName: String, config: SemanticModeYAMLConfig?) -> ResolvedConfiguration.SourceResult {
        guard let config = config else {
            return ResolvedConfiguration.SourceResult(
                source: .perRuleYAML,
                value: nil,
                isStrict: nil
            )
        }
        
        let mode = config.perRuleModes[ruleName]
        let isStrict = config.perRuleStrict[ruleName]
        
        return ResolvedConfiguration.SourceResult(
            source: .perRuleYAML,
            value: mode,
            isStrict: isStrict
        )
    }
    
    private func checkProjectYAML(config: SemanticModeYAMLConfig?) -> ResolvedConfiguration.SourceResult {
        return ResolvedConfiguration.SourceResult(
            source: .projectYAML,
            value: config?.projectMode,
            isStrict: config?.projectStrict
        )
    }
    
    // MARK: - VS Code Settings Parsing
    
    private struct VSCodeStrictSwiftSettings {
        let mode: SemanticMode?
        let strict: Bool?
    }
    
    private func loadVSCodeSettings() -> VSCodeStrictSwiftSettings? {
        let settingsPath = projectRoot.appendingPathComponent(".vscode/settings.json")
        
        guard FileManager.default.fileExists(atPath: settingsPath.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: settingsPath)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Look for strictswift.semanticMode and strictswift.semanticStrict
                let mode: SemanticMode?
                if let modeStr = json["strictswift.semanticMode"] as? String {
                    mode = SemanticMode(rawValue: modeStr.lowercased())
                } else {
                    mode = nil
                }
                
                let strict = json["strictswift.semanticStrict"] as? Bool
                
                if mode != nil || strict != nil {
                    return VSCodeStrictSwiftSettings(mode: mode, strict: strict)
                }
            }
        } catch {
            // Silently fail - VS Code settings are optional
        }
        
        return nil
    }
}

// MARK: - YAML Configuration Container

/// Container for semantic mode configuration from YAML
public struct SemanticModeYAMLConfig: Sendable {
    /// Project-level semantic mode
    public let projectMode: SemanticMode?
    
    /// Project-level strict setting
    public let projectStrict: Bool?
    
    /// Per-rule semantic modes (rule name -> mode)
    public let perRuleModes: [String: SemanticMode]
    
    /// Per-rule strict settings (rule name -> strict)
    public let perRuleStrict: [String: Bool]
    
    public init(
        projectMode: SemanticMode? = nil,
        projectStrict: Bool? = nil,
        perRuleModes: [String: SemanticMode] = [:],
        perRuleStrict: [String: Bool] = [:]
    ) {
        self.projectMode = projectMode
        self.projectStrict = projectStrict
        self.perRuleModes = perRuleModes
        self.perRuleStrict = perRuleStrict
    }
    
    /// Parse from the main Configuration object
    public static func from(_ config: SemanticConfigurable?) -> SemanticModeYAMLConfig? {
        guard let config = config else { return nil }
        
        return SemanticModeYAMLConfig(
            projectMode: config.semanticMode,
            projectStrict: config.semanticStrict,
            perRuleModes: config.perRuleSemanticModes ?? [:],
            perRuleStrict: config.perRuleSemanticStrict ?? [:]
        )
    }
}

/// Protocol for types that can provide semantic configuration
public protocol SemanticConfigurable: Sendable {
    var semanticMode: SemanticMode? { get }
    var semanticStrict: Bool? { get }
    var perRuleSemanticModes: [String: SemanticMode]? { get }
    var perRuleSemanticStrict: [String: Bool]? { get }
}

// MARK: - Resolution Helpers

extension SemanticModeResolver.ResolvedConfiguration {
    /// Whether the effective mode provides semantic analysis
    public var hasSemantic: Bool {
        effectiveMode == .hybrid || effectiveMode == .full
    }
    
    /// Whether full type information is available
    public var hasFullTypeInfo: Bool {
        effectiveMode == .full
    }
    
    /// Human-readable description of the resolution
    public var description: String {
        var parts: [String] = []
        
        parts.append("Semantic mode: \(effectiveMode.displayName)")
        parts.append("Source: \(modeSource.rawValue)")
        
        if isStrict {
            parts.append("Strict: enabled")
        }
        
        if let degradation = degradation {
            parts.append("Degraded from \(degradation.requestedMode.rawValue): \(degradation.reason)")
        }
        
        return parts.joined(separator: "\n")
    }
    
    /// Check if strict mode requirements are met
    /// - Returns: nil if requirements met, error message if not
    public func checkStrictRequirements() -> String? {
        guard isStrict, let degradation = degradation else {
            return nil
        }
        
        return "Strict semantic mode enabled but \(degradation.requestedMode.rawValue) mode unavailable: \(degradation.reason)"
    }
}

// MARK: - Logging Support

extension SemanticModeResolver.ResolvedConfiguration {
    /// Log the resolution result for debugging
    public func logResolution() {
        StrictSwiftLogger.debug("Semantic mode resolution:")
        StrictSwiftLogger.debug("  Effective: \(effectiveMode.rawValue)")
        StrictSwiftLogger.debug("  Source: \(modeSource.rawValue)")
        StrictSwiftLogger.debug("  Strict: \(isStrict)")
        
        if let degradation = degradation {
            StrictSwiftLogger.warning("  Degraded from \(degradation.requestedMode.rawValue): \(degradation.reason)")
        }
        
        StrictSwiftLogger.debug("  Checked sources:")
        for source in checkedSources {
            let valueStr = source.value?.rawValue ?? "not set"
            let strictStr = source.isStrict.map { $0 ? "strict" : "" } ?? ""
            StrictSwiftLogger.debug("    \(source.source.rawValue): \(valueStr) \(strictStr)")
        }
    }
}
