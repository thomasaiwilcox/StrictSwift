import Foundation
import SwiftSyntax

/// Base protocol for all analysis rules
public protocol Rule: Sendable {
    /// Unique identifier for this rule
    var id: String { get }

    /// Human-readable name
    var name: String { get }

    /// Description of what this rule checks
    var description: String { get }

    /// Category of this rule
    var category: RuleCategory { get }

    /// Default severity for violations
    var defaultSeverity: DiagnosticSeverity { get }

    /// Whether this rule is enabled by default
    var enabledByDefault: Bool { get }

    /// Analyze a source file for violations
    func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation]

    /// Check if a file should be analyzed by this rule
    func shouldAnalyze(_ sourceFile: SourceFile) -> Bool
}

/// Extension providing default implementation
public extension Rule {
    var defaultSeverity: DiagnosticSeverity { .warning }
    var enabledByDefault: Bool { true }

    func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        // By default, analyze all .swift files
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Context information for analysis
/// SAFETY: @unchecked Sendable is safe because all mutable state (_sourceFiles, _globalGraph) is protected
/// by NSLock for thread-safe access. Consider migrating to actor in future versions.
public final class AnalysisContext: @unchecked Sendable {
    /// Configuration for the analysis
    public let configuration: Configuration
    /// Project root directory
    public let projectRoot: URL
    /// All source files being analyzed
    private var _sourceFiles: [URL: SourceFile] = [:]
    private let lock = NSLock()
    
    /// Lazily-built global reference graph for cross-file analysis
    /// Only built when first accessed by a graph-requiring rule
    private var _globalGraph: GlobalReferenceGraph?
    private let graphLock = NSLock()
    
    /// Semantic analysis configuration
    private var _semanticResolver: SemanticTypeResolver?
    private var _semanticModeResolved: SemanticModeResolver.ResolvedConfiguration?
    private var _semanticModeResolver: SemanticModeResolver?
    private var _semanticYAMLConfig: SemanticModeYAMLConfig?
    private let semanticLock = NSLock()
    
    /// Track reported cycles to avoid duplicate violations across files
    /// Key is a set of type names (order-independent) representing the cycle
    private var _reportedCycles: Set<Set<String>> = []
    private let cycleLock = NSLock()

    public init(configuration: Configuration, projectRoot: URL) {
        self.configuration = configuration
        self.projectRoot = projectRoot
    }

    /// Backwards-compatible initializer used by legacy tests/utilities that still pass source files & workspace.
    public convenience init(sourceFiles: [SourceFile], workspace: URL, configuration: Configuration) {
        self.init(configuration: configuration, projectRoot: workspace)
        sourceFiles.forEach { addSourceFile($0) }
    }

    /// Get or add a source file
    public func sourceFile(at url: URL) -> SourceFile? {
        lock.lock()
        defer { lock.unlock() }
        return _sourceFiles[url]
    }

    /// Add a source file to the context
    public func addSourceFile(_ sourceFile: SourceFile) {
        lock.lock()
        defer { lock.unlock() }
        _sourceFiles[sourceFile.url] = sourceFile
    }

    /// Get all source files
    public var allSourceFiles: [SourceFile] {
        lock.lock()
        defer { lock.unlock() }
        return Array(_sourceFiles.values)
    }
    
    /// Get or build the global reference graph for cross-file analysis
    /// The graph is lazily built on first access and cached for reuse
    public func globalGraph() -> GlobalReferenceGraph {
        graphLock.lock()
        defer { graphLock.unlock() }
        
        if let existing = _globalGraph {
            return existing
        }
        
        // Build the graph from all source files
        let files = allSourceFiles
        let graph = GlobalReferenceGraph()
        graph.build(from: files)
        _globalGraph = graph
        return graph
    }
    
    // MARK: - Cycle Tracking
    
    /// Check if a cycle has already been reported and register it if not.
    /// Returns true if this is a new cycle that should be reported.
    /// Thread-safe for concurrent analysis.
    public func shouldReportCycle(withTypes types: Set<String>) -> Bool {
        cycleLock.lock()
        defer { cycleLock.unlock() }
        
        if _reportedCycles.contains(types) {
            return false
        }
        _reportedCycles.insert(types)
        return true
    }
    
    // MARK: - Semantic Analysis
    
    /// Set the semantic type resolver (called by Analyzer after initialization)
    public func setSemanticResolver(
        _ resolver: SemanticTypeResolver,
        config: SemanticModeResolver.ResolvedConfiguration,
        modeResolver: SemanticModeResolver? = nil,
        yamlConfig: SemanticModeYAMLConfig? = nil
    ) {
        semanticLock.lock()
        defer { semanticLock.unlock() }
        _semanticResolver = resolver
        _semanticModeResolved = config
        _semanticModeResolver = modeResolver
        _semanticYAMLConfig = yamlConfig
    }
    
    /// Get the semantic type resolver if available
    public var semanticResolver: SemanticTypeResolver? {
        semanticLock.lock()
        defer { semanticLock.unlock() }
        return _semanticResolver
    }
    
    /// Get the resolved semantic mode configuration
    public var semanticModeResolved: SemanticModeResolver.ResolvedConfiguration? {
        semanticLock.lock()
        defer { semanticLock.unlock() }
        return _semanticModeResolved
    }
    
    /// Get the resolved semantic mode configuration for a specific rule.
    /// This enables per-rule semantic mode overrides from configuration.
    /// Falls back to the global resolved configuration if no per-rule override exists.
    public func semanticModeForRule(_ ruleId: String) -> SemanticModeResolver.ResolvedConfiguration? {
        semanticLock.lock()
        defer { semanticLock.unlock() }
        
        // If we have a mode resolver and YAML config, resolve for this specific rule
        if let modeResolver = _semanticModeResolver, let yamlConfig = _semanticYAMLConfig {
            // Check if there's a per-rule override for this rule
            let hasOverride = yamlConfig.perRuleModes[ruleId] != nil || yamlConfig.perRuleStrict[ruleId] != nil
            
            if hasOverride {
                // Resolve with rule-specific configuration.
                // NOTE: We intentionally pass nil for cliMode/cliStrict here because:
                // 1. Per-rule YAML overrides are meant to override global settings for specific rules
                // 2. CLI settings apply globally and were already considered in the global resolution
                // 3. If we passed CLI mode here, it would always beat per-rule YAML due to priority
                return modeResolver.resolve(
                    cliMode: nil,
                    cliStrict: false,
                    ruleName: ruleId,
                    yamlConfig: yamlConfig
                )
            }
        }
        
        // Fall back to global resolved configuration
        return _semanticModeResolved
    }
    
    /// Whether semantic analysis is enabled (global check)
    public var hasSemanticAnalysis: Bool {
        semanticLock.lock()
        defer { semanticLock.unlock() }
        return _semanticModeResolved?.hasSemantic ?? false
    }
    
    /// Whether semantic analysis is enabled for a specific rule.
    /// This respects per-rule semantic mode overrides from configuration.
    public func hasSemanticAnalysis(forRule ruleId: String) -> Bool {
        if let resolved = semanticModeForRule(ruleId) {
            return resolved.hasSemantic
        }
        return hasSemanticAnalysis
    }
    
    /// The effective semantic mode (global)
    public var effectiveSemanticMode: SemanticMode {
        semanticLock.lock()
        defer { semanticLock.unlock() }
        return _semanticModeResolved?.effectiveMode ?? .off
    }
    
    /// The effective semantic mode for a specific rule.
    /// This respects per-rule semantic mode overrides from configuration.
    public func effectiveSemanticMode(forRule ruleId: String) -> SemanticMode {
        if let resolved = semanticModeForRule(ruleId) {
            return resolved.effectiveMode
        }
        return effectiveSemanticMode
    }
    
    /// Check if strict mode is enabled for a specific rule.
    /// When strict mode is enabled and the requested semantic mode can't be satisfied,
    /// analysis should fail rather than silently degrading.
    public func isSemanticStrict(forRule ruleId: String) -> Bool {
        if let resolved = semanticModeForRule(ruleId) {
            return resolved.isStrict
        }
        semanticLock.lock()
        defer { semanticLock.unlock() }
        return _semanticModeResolved?.isStrict ?? false
    }

    /// Check if a path is included in the analysis
    public func isIncluded(_ path: String) -> Bool {
        // Apply include patterns
        if !configuration.include.isEmpty {
            let included = configuration.include.contains { pattern in
                path.matchesGlob(pattern)
            }
            if !included {
                return false
            }
        }

        // Apply exclude patterns
        for pattern in configuration.exclude {
            if path.matchesGlob(pattern) {
                return false
            }
        }

        return true
    }
}

/// Helper for glob matching
private extension String {
    func matchesGlob(_ pattern: String) -> Bool {
        // Simple glob matching - in a real implementation, we'd use a more sophisticated library
        // For now, support * and ** wildcards
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }

        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
}
