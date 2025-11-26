import Foundation
import SystemPackage

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
        
        // Add all source files to context
        for file in sourceFiles {
            context.addSourceFile(file)
        }
        
        // Filter files based on include/exclude patterns
        let filteredFiles = sourceFiles.filter { file in
            context.isIncluded(file.path)
        }
        
        // Separate files into cached and uncached
        var cachedViolations: [Violation] = []
        var filesToAnalyze: [SourceFile] = []
        
        for file in filteredFiles {
            if let cached = await cache.getCachedResult(for: file.url) {
                cachedViolations.append(contentsOf: cached.violations)
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
    private var crossFileRuleIdentifiers: Set<String> {
        return [
            "circular-dependency",
            "layered-dependencies",
            "unused-public-declaration",
            "orphan-protocol",
            "dependency-inversion",
            "module-boundary",
            "dead-code"
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
    
    /// Compute a hash representing the current rule configuration
    private func computeRuleVersionHash() -> UInt64 {
        var hash: UInt64 = 14695981039346656037 // FNV-1a offset basis
        let fnvPrime: UInt64 = 1099511628211
        
        // Include enabled categories in hash
        let categories: [(String, RuleConfiguration)] = [
            ("safety", configuration.rules.safety),
            ("concurrency", configuration.rules.concurrency),
            ("memory", configuration.rules.memory),
            ("architecture", configuration.rules.architecture),
            ("complexity", configuration.rules.complexity),
            ("performance", configuration.rules.performance)
        ]
        
        for (name, config) in categories where config.enabled {
            for byte in name.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* fnvPrime
            }
            let severityString = config.severity.rawValue
            for byte in severityString.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* fnvPrime
            }
        }
        
        return hash
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