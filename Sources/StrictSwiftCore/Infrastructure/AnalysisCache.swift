import Foundation

/// Fingerprint for identifying a source file's state
public struct FileFingerprint: Codable, Hashable, Sendable {
    /// Absolute path to the file
    public let path: String
    /// FNV-1a hash of the file contents
    public let contentHash: UInt64
    /// File modification date
    public let modificationDate: Date
    /// Size in bytes
    public let size: Int64
    
    public init(path: String, contentHash: UInt64, modificationDate: Date, size: Int64) {
        self.path = path
        self.contentHash = contentHash
        self.modificationDate = modificationDate
        self.size = size
    }
    
    /// Create a fingerprint from a file URL
    public init(url: URL) throws {
        self.path = url.path
        
        // Get file attributes
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        self.modificationDate = attributes[.modificationDate] as? Date ?? Date()
        self.size = attributes[.size] as? Int64 ?? 0
        
        // Compute content hash
        let content = try String(contentsOf: url, encoding: .utf8)
        self.contentHash = Self.fnv1aHash(content)
    }
    
    /// Create a fingerprint from source content (for testing)
    public init(path: String, content: String, modificationDate: Date = Date()) {
        self.path = path
        self.contentHash = Self.fnv1aHash(content)
        self.modificationDate = modificationDate
        self.size = Int64(content.utf8.count)
    }
    
    /// FNV-1a hash algorithm (fast, good distribution)
    public static func fnv1aHash(_ string: String) -> UInt64 {
        let fnvPrime: UInt64 = 1099511628211
        let fnvOffset: UInt64 = 14695981039346656037
        
        var hash = fnvOffset
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }
        return hash
    }
}

/// Cached analysis result for a single file
public struct CachedFileResult: Codable, Sendable {
    /// Fingerprint of the file when analyzed
    public let fingerprint: FileFingerprint
    /// Violations found in this file
    public let violations: [Violation]
    /// When the analysis was performed
    public let analyzedAt: Date
    /// Version of StrictSwift used for analysis
    public let analyzerVersion: String
    
    public init(fingerprint: FileFingerprint, violations: [Violation], analyzerVersion: String) {
        self.fingerprint = fingerprint
        self.violations = violations
        self.analyzedAt = Date()
        self.analyzerVersion = analyzerVersion
    }
}

/// Cache metadata for invalidation
public struct CacheMetadata: Codable, Sendable {
    /// Hash of the configuration used
    public let configurationHash: UInt64
    /// Version of the cache format
    public let formatVersion: Int
    /// When the cache was created
    public let createdAt: Date
    /// StrictSwift version
    public let analyzerVersion: String
    
    public static let currentFormatVersion = 1
    public static let currentAnalyzerVersion = "0.9.0"
    
    public init(configurationHash: UInt64) {
        self.configurationHash = configurationHash
        self.formatVersion = Self.currentFormatVersion
        self.createdAt = Date()
        self.analyzerVersion = Self.currentAnalyzerVersion
    }
    
    /// Check if cache is valid for given configuration
    public func isValid(for configHash: UInt64) -> Bool {
        return formatVersion == Self.currentFormatVersion &&
               analyzerVersion == Self.currentAnalyzerVersion &&
               configurationHash == configHash
    }
}

/// Disk-persisted cache for analysis results
public actor AnalysisCache {
    /// Directory where cache files are stored
    private let cacheDirectory: URL
    /// In-memory cache for fast access
    private var memoryCache: [String: CachedFileResult] = [:]
    /// Cache metadata
    private var metadata: CacheMetadata?
    /// Configuration hash for invalidation
    private let configurationHash: UInt64
    /// Whether cache is enabled
    private let isEnabled: Bool
    
    /// Default cache directory name
    public static let defaultCacheDirectoryName = ".strictswift-cache"
    
    /// Initialize cache with configuration
    public init(projectRoot: URL, configuration: Configuration, enabled: Bool = true) {
        self.cacheDirectory = projectRoot.appendingPathComponent(Self.defaultCacheDirectoryName)
        self.configurationHash = Self.hashConfiguration(configuration)
        self.isEnabled = enabled
    }
    
    /// Initialize cache for a specific directory (for testing)
    public init(cacheDirectory: URL, configurationHash: UInt64, enabled: Bool = true) {
        self.cacheDirectory = cacheDirectory
        self.configurationHash = configurationHash
        self.isEnabled = enabled
    }
    
    // MARK: - Public API
    
    /// Load cache from disk
    public func load() async throws {
        guard isEnabled else { return }
        
        let metadataURL = cacheDirectory.appendingPathComponent("metadata.json")
        
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            // No cache exists yet
            return
        }
        
        // Load and validate metadata
        let metadataData = try Data(contentsOf: metadataURL)
        let loadedMetadata = try JSONDecoder().decode(CacheMetadata.self, from: metadataData)
        
        guard loadedMetadata.isValid(for: configurationHash) else {
            // Configuration changed, invalidate cache
            try await clear()
            return
        }
        
        self.metadata = loadedMetadata
        
        // Load cached results
        let resultsURL = cacheDirectory.appendingPathComponent("results.json")
        if FileManager.default.fileExists(atPath: resultsURL.path) {
            let resultsData = try Data(contentsOf: resultsURL)
            let results = try JSONDecoder().decode([CachedFileResult].self, from: resultsData)
            
            for result in results {
                memoryCache[result.fingerprint.path] = result
            }
        }
    }
    
    /// Save cache to disk
    public func save() async throws {
        guard isEnabled else { return }
        
        // Create cache directory if needed
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Save metadata
        let metadata = CacheMetadata(configurationHash: configurationHash)
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: cacheDirectory.appendingPathComponent("metadata.json"))
        
        // Save results
        let results = Array(memoryCache.values)
        let resultsData = try JSONEncoder().encode(results)
        try resultsData.write(to: cacheDirectory.appendingPathComponent("results.json"))
        
        self.metadata = metadata
    }
    
    /// Get cached result for a file if valid
    public func getCachedResult(for url: URL) async -> CachedFileResult? {
        guard isEnabled else { return nil }
        
        guard let cached = memoryCache[url.path] else {
            return nil
        }
        
        // Validate fingerprint is still current
        do {
            let currentFingerprint = try FileFingerprint(url: url)
            if cached.fingerprint == currentFingerprint {
                return cached
            }
        } catch {
            // File may have been deleted or is unreadable
        }
        
        // Fingerprint doesn't match, remove stale cache
        memoryCache.removeValue(forKey: url.path)
        return nil
    }
    
    /// Cache analysis result for a file
    public func cacheResult(for url: URL, violations: [Violation]) async {
        guard isEnabled else { return }
        
        do {
            let fingerprint = try FileFingerprint(url: url)
            let result = CachedFileResult(
                fingerprint: fingerprint,
                violations: violations,
                analyzerVersion: CacheMetadata.currentAnalyzerVersion
            )
            memoryCache[url.path] = result
        } catch {
            // Failed to create fingerprint, skip caching
            StrictSwiftLogger.debug("Failed to cache result for \(url.path): \(error)")
        }
    }
    
    /// Clear the cache
    public func clear() async throws {
        memoryCache.removeAll()
        metadata = nil
        
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
        }
    }
    
    /// Get cache statistics
    public var statistics: CacheStatistics {
        return CacheStatistics(
            cachedFileCount: memoryCache.count,
            cacheDirectory: cacheDirectory,
            isEnabled: isEnabled,
            configurationHash: configurationHash
        )
    }
    
    // MARK: - Private Helpers
    
    /// Hash configuration for cache invalidation
    /// IMPORTANT: This hash must include ALL configuration that affects analysis results
    private static func hashConfiguration(_ config: Configuration) -> UInt64 {
        var hashString = ""
        
        // 1. Basic configuration
        hashString += config.profile.rawValue
        hashString += String(config.maxJobs)
        hashString += config.include.joined(separator: "|")
        hashString += config.exclude.joined(separator: "|")
        
        // 2. Rule categories - full details including options
        let categories: [(String, RuleConfiguration)] = [
            ("safety", config.rules.safety),
            ("concurrency", config.rules.concurrency),
            ("memory", config.rules.memory),
            ("architecture", config.rules.architecture),
            ("complexity", config.rules.complexity),
            ("performance", config.rules.performance),
            ("monolith", config.rules.monolith),
            ("dependency", config.rules.dependency)
        ]
        
        for (name, ruleConfig) in categories {
            hashString += "\(name):\(ruleConfig.enabled):\(ruleConfig.severity.rawValue)"
            // Include all options
            let sortedOptions = ruleConfig.options.sorted(by: { $0.key < $1.key })
            for (key, value) in sortedOptions {
                hashString += ":\(key)=\(value)"
            }
        }
        
        // 3. Advanced thresholds - ALL fields
        let t = config.advanced.thresholds
        hashString += "thresholds:\(t.maxCyclomaticComplexity):\(t.maxMethodLength):\(t.maxTypeComplexity)"
        hashString += ":\(t.maxNestingDepth):\(t.maxParameterCount):\(t.maxPropertyCount):\(t.maxFileLength)"
        
        // 4. Rule-specific settings - full details including parameters and file patterns
        let sortedRuleSettings = config.advanced.ruleSettings.sorted(by: { $0.key < $1.key })
        for (ruleId, settings) in sortedRuleSettings {
            hashString += "rule:\(ruleId):\(settings.enabled):\(settings.severity.rawValue)"
            
            // Include all parameters
            let sortedParams = settings.parameters.sorted(by: { $0.key < $1.key })
            for (key, value) in sortedParams {
                hashString += ":\(key)=\(value.stringValue)"
            }
            
            // Include file patterns
            let fp = settings.filePatterns
            hashString += ":inc=\(fp.include.joined(separator: ","))"
            hashString += ":exc=\(fp.exclude.joined(separator: ","))"
            hashString += ":noTest=\(fp.excludeTestFiles):noGen=\(fp.excludeGeneratedFiles)"
        }
        
        // 5. Conditional settings
        let sortedConditionals = config.advanced.conditionalSettings.sorted(by: { $0.name < $1.name })
        for conditional in sortedConditionals {
            hashString += "cond:\(conditional.name):\(conditional.priority)"
            hashString += ":condition=\(hashCondition(conditional.condition))"
            
            // Include rule overrides
            let sortedOverrides = conditional.ruleOverrides.sorted(by: { $0.key < $1.key })
            for (ruleId, override) in sortedOverrides {
                hashString += ":override:\(ruleId):\(override.enabled):\(override.severity.rawValue)"
                let sortedParams = override.parameters.sorted(by: { $0.key < $1.key })
                for (key, value) in sortedParams {
                    hashString += ":\(key)=\(value.stringValue)"
                }
            }
        }
        
        // 6. Scope settings - all fields
        let s = config.advanced.scopeSettings
        hashString += "scope:\(s.analyzeTests):\(s.analyzeExtensions):\(s.analyzeGeneratedCode)"
        hashString += ":\(s.minFileSizeLines):\(s.maxFileSizeLines):\(s.excludeEmptyFiles):\(s.excludeVendorCode)"
        
        // 7. Performance settings that affect analysis behavior
        let p = config.advanced.performanceSettings
        hashString += "perf:\(p.enableParallelAnalysis):\(p.enableIncrementalAnalysis)"
        hashString += ":\(p.analysisTimeoutSeconds)"
        
        return FileFingerprint.fnv1aHash(hashString)
    }
    
    /// Hash a configuration condition recursively
    private static func hashCondition(_ condition: ConfigurationCondition) -> String {
        switch condition {
        case .pathPattern(let pattern):
            return "path:\(pattern)"
        case .fileName(let name):
            return "file:\(name)"
        case .fileExtension(let ext):
            return "ext:\(ext)"
        case .directory(let dir):
            return "dir:\(dir)"
        case .any(let conditions):
            return "any:[\(conditions.map { hashCondition($0) }.joined(separator: ","))]"
        case .all(let conditions):
            return "all:[\(conditions.map { hashCondition($0) }.joined(separator: ","))]"
        case .not(let condition):
            return "not:\(hashCondition(condition))"
        case .custom(let expr):
            return "custom:\(expr)"
        }
    }
}

/// Statistics about cache state
public struct CacheStatistics: Sendable {
    public let cachedFileCount: Int
    public let cacheDirectory: URL
    public let isEnabled: Bool
    public let configurationHash: UInt64
    
    public var description: String {
        if isEnabled {
            return "Cache: \(cachedFileCount) files cached at \(cacheDirectory.path)"
        } else {
            return "Cache: disabled"
        }
    }
}
