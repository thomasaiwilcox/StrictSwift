import Foundation
import SystemPackage

// strictswift:ignore-file circular_dependency_graph -- Configuration↔Profile is intentional

/// Thread-safe holder for cached RuleEngine
private actor RuleEngineCache {
    private var engine: RuleEngine?
    
    func getOrCreate() async -> RuleEngine {
        if let engine = engine {
            return engine
        }
        let newEngine = await RuleEngine()
        engine = newEngine
        return newEngine
    }
}

/// Main analyzer that orchestrates StrictSwift analysis
public final class Analyzer: Sendable {
    private let configuration: Configuration
    private let cache: AnalysisCache?
    private let ruleEngineCache = RuleEngineCache()

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.cache = nil
    }
    
    /// Initialize with optional caching for incremental analysis
    public init(configuration: Configuration, cache: AnalysisCache?) {
        self.configuration = configuration
        self.cache = cache
    }

    /// Analyze the given paths for violations
    public func analyze(paths: [String]) async throws -> [Violation] {
        // Find all Swift files
        let swiftFiles = try findSwiftFiles(in: paths)

        // Parse source files
        let sourceFiles = try await parseFiles(swiftFiles)

        // Analyze with rule engine
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let context = AnalysisContext(configuration: configuration, projectRoot: projectRoot)

        // Filter files based on include/exclude patterns BEFORE adding to context
        // This ensures cross-file rules (DeadCodeRule, graph-enhanced rules) only see included files
        let filteredFiles = sourceFiles.filter { file in
            context.isIncluded(file.path)
        }

        // Only add filtered files to context - this populates allSourceFiles and globalGraph
        for file in filteredFiles {
            context.addSourceFile(file)
        }
        
        // Initialize semantic analysis if configured
        try await initializeSemanticAnalysis(context: context)

        // Run analysis - use cached RuleEngine for performance
        let ruleEngine = await ruleEngineCache.getOrCreate()
        let violations = await ruleEngine.analyze(filteredFiles, in: context, configuration: configuration)

        // Apply baseline filtering if configured
        if let baseline = configuration.baseline {
            return filterWithBaseline(violations, baseline: baseline, projectRoot: projectRoot)
        }

        return violations
    }
    
    /// Analyze with incremental caching support
    /// Returns violations and statistics about cache hits/misses
    public func analyzeIncremental(paths: [String]) async throws -> IncrementalAnalysisResult {
        guard let cache = cache else {
            // Fall back to regular analysis if no cache
            let violations = try await analyze(paths: paths)
            return IncrementalAnalysisResult(
                violations: violations,
                cachedFileCount: 0,
                analyzedFileCount: violations.isEmpty ? 0 : 1,
                cacheHitRate: 0.0
            )
        }
        
        // Load cache from disk
        try await cache.load()
        
        // Find all Swift files
        let swiftFiles = try findSwiftFiles(in: paths)
        
        // Parse source files
        let sourceFiles = try await parseFiles(swiftFiles)
        
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let context = AnalysisContext(configuration: configuration, projectRoot: projectRoot)
        
        // Filter files based on include/exclude patterns BEFORE adding to context
        // This ensures cross-file rules (DeadCodeRule, graph-enhanced rules) only see included files
        let filteredFiles = sourceFiles.filter { file in
            context.isIncluded(file.path)
        }
        
        // Only add filtered files to context - this populates allSourceFiles and globalGraph
        for file in filteredFiles {
            context.addSourceFile(file)
        }
        
        // Initialize semantic analysis if configured
        // This must happen before rule analysis so context.semanticResolver is available
        try await initializeSemanticAnalysis(context: context)
        
        // Separate files into cached and uncached
        var cachedViolations: [Violation] = []
        var filesToAnalyze: [SourceFile] = []
        
        // Build set of included file paths for filtering cached violations
        let includedPaths = Set(filteredFiles.map { $0.url.path })
        
        for file in filteredFiles {
            if let cached = await cache.getCachedResult(for: file.url) {
                // Only include cached violations for files that are still included
                // This handles the case where include/exclude patterns changed
                let validViolations = cached.violations.filter { violation in
                    includedPaths.contains(violation.location.file.path)
                }
                cachedViolations.append(contentsOf: validViolations)
            } else {
                filesToAnalyze.append(file)
            }
        }
        
        // Analyze uncached files
        var newViolations: [Violation] = []
        if !filesToAnalyze.isEmpty {
            let ruleEngine = await ruleEngineCache.getOrCreate()
            newViolations = await ruleEngine.analyze(filesToAnalyze, in: context, configuration: configuration)
            
            // Cache the results per file
            for file in filesToAnalyze {
                let fileViolations = newViolations.filter { $0.location.file.path == file.url.path }
                await cache.cacheResult(for: file.url, violations: fileViolations)
            }
        }
        
        // Handle cross-file rules that need full project context
        // These rules need to be re-run if any file changed
        if !filesToAnalyze.isEmpty {
            let crossFileViolations = await analyzeCrossFileRules(
                files: filteredFiles,
                context: context
            )
            // Remove any cached cross-file violations and add fresh ones
            let crossFileRuleIds = crossFileRuleIdentifiers
            cachedViolations.removeAll { crossFileRuleIds.contains($0.ruleId) }
            newViolations.append(contentsOf: crossFileViolations)
        }
        
        let allViolations = cachedViolations + newViolations
        
        // Apply baseline filtering if configured
        let finalViolations: [Violation]
        if let baseline = configuration.baseline {
            finalViolations = filterWithBaseline(allViolations, baseline: baseline, projectRoot: projectRoot)
        } else {
            finalViolations = allViolations
        }
        
        // Persist cache
        try await cache.save()
        
        // Log semantic resolution statistics
        await logSemanticStats(context: context)
        
        let totalFiles = filteredFiles.count
        let cachedFiles = totalFiles - filesToAnalyze.count
        let hitRate = totalFiles > 0 ? Double(cachedFiles) / Double(totalFiles) : 0.0
        
        return IncrementalAnalysisResult(
            violations: finalViolations,
            cachedFileCount: cachedFiles,
            analyzedFileCount: filesToAnalyze.count,
            cacheHitRate: hitRate
        )
    }
    
    /// Rules that require cross-file analysis and can't be cached per-file
    /// NOTE: These must match the actual rule IDs (hyphenated format for dead-code)
    private var crossFileRuleIdentifiers: Set<String> {
        return [
            "circular_dependency",
            "circular_dependency_graph",
            "layered_dependencies",
            "unused_public_declaration",
            "orphan_protocol",
            "dependency_inversion",
            "module_boundary",
            "dead-code",
            // Graph-enhanced rules
            "enhanced_god_class",
            "coupling_metrics",
            "enhanced_non_sendable_capture"
        ]
    }
    
    /// Analyze only cross-file rules that require full project context
    private func analyzeCrossFileRules(
        files: [SourceFile],
        context: AnalysisContext
    ) async -> [Violation] {
        let ruleEngine = await ruleEngineCache.getOrCreate()
        let allViolations = await ruleEngine.analyze(files, in: context, configuration: configuration)
        
        // Filter to only cross-file rule violations
        return allViolations.filter { crossFileRuleIdentifiers.contains($0.ruleId) }
    }

    /// Find all Swift files in the given paths
    private func findSwiftFiles(in paths: [String]) throws -> [URL] {
        var allFiles: [URL] = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false

            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Recursively find Swift files
                    allFiles.append(contentsOf: try findSwiftFilesInDirectory(url))
                } else if url.pathExtension == "swift" {
                    allFiles.append(url)
                }
            }
        }

        return allFiles.removingDuplicates()
    }

    /// Find all Swift files in a directory recursively
    private func findSwiftFilesInDirectory(_ directory: URL) throws -> [URL] {
        var files: [URL] = []

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let directoryEnumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys
        ) else {
            return files
        }

        for case let fileURL as URL in directoryEnumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))

            if resourceValues.isDirectory == true {
                // Skip .build and other hidden directories
                let name = resourceValues.name ?? ""
                if name.hasPrefix(".") || name == "build" || name == "DerivedData" {
                    directoryEnumerator.skipDescendants()
                }
            } else if fileURL.pathExtension == "swift" {
                files.append(fileURL)
            }
        }

        return files
    }

    /// Parse Swift files into SourceFile objects
    private func parseFiles(_ urls: [URL]) async throws -> [SourceFile] {
        return try await withThrowingTaskGroup(of: SourceFile.self, returning: [SourceFile].self) { group in
            var files: [SourceFile] = []

            for url in urls {
                group.addTask {
                    return try SourceFile(url: url)
                }
            }

            while let file = try await group.next() {
                files.append(file)
            }

            return files
        }
    }

    /// Filter violations using baseline
    private func filterWithBaseline(
        _ violations: [Violation],
        baseline: BaselineConfiguration,
        projectRoot: URL
    ) -> [Violation] {
        // Check if baseline has expired
        if baseline.isExpired {
            let expiryDescription = baseline.expires?.description ?? "unknown date"
            StrictSwiftLogger.warning("Baseline expired on \(expiryDescription)")
            return violations
        }

        // Create set of baseline fingerprints for fast lookup
        let baselineFingerprints = Set(baseline.violations)

        // Filter out violations that are in the baseline
        return violations.filter { violation in
            let fingerprint = ViolationFingerprint(violation: violation, projectRoot: projectRoot)
            return !baselineFingerprints.contains(fingerprint)
        }
    }
    
    // MARK: - Semantic Analysis
    
    /// Initialize semantic analysis based on configuration
    private func initializeSemanticAnalysis(context: AnalysisContext) async throws {
        let projectRoot = context.projectRoot
        
        // Detect semantic capabilities
        let detector = SemanticCapabilityDetector(projectRoot: projectRoot)
        let capabilities = detector.detect()
        
        // Resolve semantic mode from layered configuration
        let resolver = SemanticModeResolver(capabilities: capabilities, projectRoot: projectRoot)
        let yamlConfig = SemanticModeYAMLConfig.from(configuration)
        
        // Parse CLI mode - already in configuration
        let resolved = resolver.resolve(
            cliMode: configuration.semanticMode,
            cliStrict: configuration.semanticStrict ?? false,
            yamlConfig: yamlConfig
        )
        
        // IMPORTANT: Compute the maximum mode required across ALL rules.
        // Even if global mode is .off, per-rule overrides may request .hybrid or .full.
        // The resolver must be created with a mode capable of satisfying the maximum need.
        // This also checks per-rule strict requirements and throws if any cannot be satisfied.
        let effectiveModeForResolver = try computeMaxRequiredMode(
            globalResolved: resolved,
            yamlConfig: yamlConfig,
            capabilities: capabilities
        )
        
        // Log resolution for debugging
        resolved.logResolution()
        if effectiveModeForResolver != resolved.effectiveMode {
            StrictSwiftLogger.info(
                "Semantic resolver created with '\(effectiveModeForResolver.displayName)' mode " +
                "(elevated from '\(resolved.effectiveMode.displayName)' due to per-rule overrides)"
            )
        }
        
        // Check strict mode requirements
        if let error = resolved.checkStrictRequirements() {
            throw SemanticAnalysisError.strictModeUnsatisfied(error)
        }
        
        // Log degradation warnings - always visible for user awareness
        if let degradation = resolved.degradation {
            // Use warning level which always outputs to stderr
            StrictSwiftLogger.warning(
                "Semantic mode degraded from '\(degradation.requestedMode.rawValue)' to '\(degradation.actualMode.rawValue)': \(degradation.reason)"
            )
            // Provide actionable guidance
            if degradation.actualMode == .off {
                StrictSwiftLogger.warning(
                    "Analysis continues with syntactic-only mode. For full semantic analysis, ensure SourceKit is available (Xcode installed)."
                )
            } else if degradation.actualMode == .hybrid && degradation.requestedMode == .full {
                StrictSwiftLogger.warning(
                    "Analysis continues in hybrid mode. Build indexes may improve results."
                )
            }
        }
        
        // Create semantic resolver if ANY mode requires semantic analysis (global or per-rule)
        // The resolver is created with the maximum required mode so it can satisfy all rules
        let needsSemantic = effectiveModeForResolver != .off && effectiveModeForResolver != .auto
        
        if needsSemantic {
            // Create a resolved config with the elevated mode for the resolver
            let resolverConfig = SemanticModeResolver.ResolvedConfiguration(
                effectiveMode: effectiveModeForResolver,
                isStrict: resolved.isStrict,
                modeSource: resolved.modeSource,
                degradation: resolved.degradation,
                checkedSources: resolved.checkedSources
            )
            
            let semanticResolver = try await SemanticTypeResolver.create(
                config: resolverConfig,
                capabilities: capabilities,
                projectRoot: projectRoot
            )
            
            context.setSemanticResolver(
                semanticResolver,
                config: resolved,  // Store the original global resolved config for reporting
                modeResolver: resolver,
                yamlConfig: yamlConfig
            )
            
            // Enhance global graph with semantic info if resolver supports full mode
            if effectiveModeForResolver == .full {
                let graph = context.globalGraph()
                let files = context.allSourceFiles
                let result = await graph.enhanceWithSemantics(using: semanticResolver, for: files)
                
                // Get resolver stats after enhancement
                let stats = await semanticResolver.getStatistics()
                
                StrictSwiftLogger.info(
                    "Semantic enhancement [\(effectiveModeForResolver.displayName)]: " +
                    "\(result.newlyResolved) resolved via SourceKit, " +
                    "\(result.edgesAdded) edges added, " +
                    "\(stats.sourceKitQueries) queries made"
                )
            } else if effectiveModeForResolver == .hybrid {
                // In hybrid mode, log that we're ready for on-demand queries
                StrictSwiftLogger.info(
                    "Semantic analysis [Hybrid]: SourceKit enabled for ambiguous references"
                )
            }
        } else {
            // Set resolved config even in off mode for consistency
            context.setSemanticResolver(
                SemanticTypeResolver(mode: .off, sourceKitClient: nil, projectRoot: projectRoot),
                config: resolved,
                modeResolver: resolver,
                yamlConfig: yamlConfig
            )
        }
    }
    
    /// Compute the maximum semantic mode required across global config and all per-rule overrides.
    /// This ensures the SemanticTypeResolver is created with sufficient capability to satisfy
    /// any rule that requests a higher mode via per-rule configuration.
    /// - Returns: The effective mode for the resolver, after applying capability constraints
    /// - Throws: SemanticAnalysisError if a per-rule strict override cannot be satisfied
    private func computeMaxRequiredMode(
        globalResolved: SemanticModeResolver.ResolvedConfiguration,
        yamlConfig: SemanticModeYAMLConfig?,
        capabilities: SemanticCapabilities
    ) throws -> SemanticMode {
        var maxMode = globalResolved.effectiveMode
        
        // Check all per-rule mode overrides
        if let perRuleModes = yamlConfig?.perRuleModes {
            for (_, mode) in perRuleModes {
                maxMode = higherSemanticMode(maxMode, mode)
            }
        }
        
        // Calculate what mode we can actually provide after capability constraints
        var effectiveMode = maxMode
        
        if maxMode.requiresSourceKit && !capabilities.sourceKitAvailable {
            // Degrade to off (no SourceKit available)
            effectiveMode = .off
        } else if maxMode == .full && !capabilities.buildArtifactsExist {
            // Full mode requires build artifacts; degrade to hybrid if possible
            if capabilities.sourceKitAvailable {
                effectiveMode = .hybrid
            } else {
                effectiveMode = .off
            }
        } else if maxMode == .auto {
            effectiveMode = capabilities.bestAvailableMode
        }
        
        // CRITICAL: Check if any per-rule STRICT overrides cannot be satisfied
        // This is what makes perRuleSemanticStrict actually work
        try checkPerRuleStrictRequirements(
            globalResolved: globalResolved,
            yamlConfig: yamlConfig,
            effectiveMode: effectiveMode,
            capabilities: capabilities
        )
        
        return effectiveMode
    }
    
    /// Check if any per-rule strict requirements cannot be satisfied.
    /// Throws an error if a rule has semantic-strict enabled but its requested mode can't be provided.
    ///
    /// IMPORTANT: When a rule has `perRuleSemanticStrict: true` but no explicit `perRuleSemanticModes`,
    /// we must use the ORIGINAL requested mode (before capability degradation), not the degraded effective mode.
    /// This ensures that a config like:
    /// ```yaml
    /// semanticMode: full
    /// perRuleSemanticStrict:
    ///   dead-code: true
    /// ```
    /// will properly fail if SourceKit is unavailable, rather than silently degrading.
    private func checkPerRuleStrictRequirements(
        globalResolved: SemanticModeResolver.ResolvedConfiguration,
        yamlConfig: SemanticModeYAMLConfig?,
        effectiveMode: SemanticMode,
        capabilities: SemanticCapabilities
    ) throws {
        guard let yamlConfig = yamlConfig else { return }
        
        // Determine the original requested mode (before any capability degradation).
        // Priority: degradation.requestedMode (if degraded) > projectMode from YAML > CLI mode that resolved
        let originalRequestedMode: SemanticMode = {
            // If degradation occurred, use what was originally requested
            if let degradation = globalResolved.degradation {
                return degradation.requestedMode
            }
            // Otherwise use project mode from YAML if set
            if let projectMode = yamlConfig.projectMode {
                return projectMode
            }
            // Fall back to the effective mode (no degradation occurred)
            return globalResolved.effectiveMode
        }()
        
        // For each rule with strict=true, verify its mode can be satisfied
        for (ruleId, isStrict) in yamlConfig.perRuleStrict where isStrict {
            // Get the mode requested for this rule:
            // - If per-rule mode is explicitly set, use that
            // - Otherwise, inherit the original global requested mode (NOT the degraded effectiveMode)
            let requestedMode = yamlConfig.perRuleModes[ruleId] ?? originalRequestedMode
            
            // Check if the requested mode can be satisfied given current capabilities
            let canSatisfy = canSatisfyMode(requestedMode, effectiveMode: effectiveMode, capabilities: capabilities)
            
            if !canSatisfy {
                let reason: String
                if requestedMode == .full && !capabilities.buildArtifactsExist {
                    reason = "Full semantic mode requires build artifacts (run 'swift build' first)"
                } else if requestedMode.requiresSourceKit && !capabilities.sourceKitAvailable {
                    reason = "Mode '\(requestedMode.rawValue)' requires SourceKit which is not available"
                } else {
                    reason = "Cannot satisfy semantic mode '\(requestedMode.rawValue)' for rule '\(ruleId)'"
                }
                
                throw SemanticAnalysisError.strictModeUnsatisfied(
                    "Per-rule strict requirement failed for '\(ruleId)': \(reason). " +
                    "Either satisfy the requirement or remove 'perRuleSemanticStrict.\(ruleId): true' from configuration."
                )
            }
        }
    }
    
    /// Check if a requested mode can be satisfied given the effective mode and capabilities
    private func canSatisfyMode(
        _ requested: SemanticMode,
        effectiveMode: SemanticMode,
        capabilities: SemanticCapabilities
    ) -> Bool {
        switch requested {
        case .off, .auto:
            // These can always be satisfied
            return true
        case .hybrid:
            // Hybrid needs SourceKit and effective mode >= hybrid
            return capabilities.sourceKitAvailable && 
                   (effectiveMode == .hybrid || effectiveMode == .full)
        case .full:
            // Full needs SourceKit + build artifacts and effective mode == full
            return capabilities.sourceKitAvailable && 
                   capabilities.buildArtifactsExist && 
                   effectiveMode == .full
        }
    }
    
    /// Returns the "higher" of two semantic modes based on capability requirements.
    /// full > hybrid > off (auto resolves to best available)
    private func higherSemanticMode(_ a: SemanticMode, _ b: SemanticMode) -> SemanticMode {
        func modeRank(_ mode: SemanticMode) -> Int {
            switch mode {
            case .off: return 0
            case .auto: return 1  // auto could resolve to anything, treat as hybrid-ish
            case .hybrid: return 2
            case .full: return 3
            }
        }
        return modeRank(a) >= modeRank(b) ? a : b
    }
    
    /// Log semantic resolution statistics
    private func logSemanticStats(context: AnalysisContext) async {
        guard let resolver = context.semanticResolver,
              let modeConfig = context.semanticModeResolved else {
            return
        }
        
        let stats = await resolver.getStatistics()
        
        // Only log if any semantic work was done
        if stats.totalReferences > 0 || stats.sourceKitQueries > 0 {
            let mode = modeConfig.effectiveMode
            let sourceKitUsed = stats.resolvedFromSourceKit > 0 || stats.sourceKitQueries > 0
            
            StrictSwiftLogger.info(
                "Semantic analysis [\(mode.displayName)]: " +
                "\(stats.totalReferences) refs, " +
                "\(stats.resolvedFromSourceKit) via SourceKit, " +
                "\(stats.resolvedFromAnnotation) from syntax, " +
                "\(stats.sourceKitQueries) queries"
            )
            
            if sourceKitUsed {
                StrictSwiftLogger.debug(
                    "SourceKit usage: \(stats.sourceKitQueries) queries, " +
                    "\(stats.cacheHits) cache hits (\(String(format: "%.1f", stats.cacheHitRate * 100))%)"
                )
            }
        }
    }
}

/// Errors related to semantic analysis
public enum SemanticAnalysisError: Error, LocalizedError {
    case strictModeUnsatisfied(String)
    
    public var errorDescription: String? {
        switch self {
        case .strictModeUnsatisfied(let message):
            return "Semantic analysis requirement not met: \(message)"
        }
    }
}

/// Result of incremental analysis with cache statistics
public struct IncrementalAnalysisResult: Sendable {
    /// All violations found
    public let violations: [Violation]
    /// Number of files retrieved from cache
    public let cachedFileCount: Int
    /// Number of files that were analyzed fresh
    public let analyzedFileCount: Int
    /// Cache hit rate (0.0 - 1.0)
    public let cacheHitRate: Double
    
    public var totalFileCount: Int {
        cachedFileCount + analyzedFileCount
    }
}

/// Extension for removing duplicates
private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}