import Foundation

/// Cached violation data for lookup by stable ID
public struct CachedViolation: Codable, Sendable {
    public let stableId: String
    public let ruleId: String
    public let category: String
    public let severity: String
    public let message: String
    public let filePath: String
    public let line: Int
    public let column: Int
    public let timestamp: Date
    
    public init(from violation: Violation) {
        self.stableId = violation.stableId
        self.ruleId = violation.ruleId
        self.category = violation.category.rawValue
        self.severity = violation.severity.rawValue
        self.message = violation.message
        self.filePath = violation.location.file.path
        self.line = violation.location.line
        self.column = violation.location.column
        self.timestamp = Date()
    }
}

/// Data structure stored in the cache file
struct ViolationCacheData: Codable {
    var version: Int = 1
    var lastRunDate: Date
    var violations: [String: CachedViolation] // indexed by stableId
    
    init() {
        self.lastRunDate = Date()
        self.violations = [:]
    }
}

/// Actor for thread-safe caching of violations from the last analysis run.
/// This enables the feedback command to look up violation details by stable ID.
public actor ViolationCache {
    /// Shared instance for the current process
    public static let shared = ViolationCache()
    
    /// Default maximum number of violations to cache (prevents unbounded growth)
    public static let defaultMaxEntries = 5000
    
    private var data: ViolationCacheData
    private var cacheDirectory: String
    private let cacheFileName = ".strictswift-last-run.json"
    
    private init() {
        self.data = ViolationCacheData()
        self.cacheDirectory = FileManager.default.currentDirectoryPath
    }
    
    /// Set the cache directory (defaults to current directory)
    public func setCacheDirectory(_ directory: String) {
        self.cacheDirectory = directory
    }
    
    /// Get the path to the cache file
    private var cacheFilePath: String {
        return URL(fileURLWithPath: cacheDirectory).appendingPathComponent(cacheFileName).path
    }
    
    /// Store violations from an analysis run
    /// - Parameters:
    ///   - violations: Array of violations to cache
    ///   - maxEntries: Maximum entries to store (default: 5000). Oldest entries are dropped when exceeded.
    public func storeViolations(_ violations: [Violation], maxEntries: Int = ViolationCache.defaultMaxEntries) {
        data = ViolationCacheData()
        data.lastRunDate = Date()
        
        // Take only the most recent violations if over limit
        let violationsToStore = violations.count > maxEntries 
            ? Array(violations.suffix(maxEntries)) 
            : violations
        
        for violation in violationsToStore {
            let cached = CachedViolation(from: violation)
            data.violations[cached.stableId] = cached
        }
        
        // Persist to disk
        save()
    }
    
    /// Look up a violation by its stable ID
    public func lookup(_ stableId: String) -> CachedViolation? {
        // Try in-memory first
        if let cached = data.violations[stableId] {
            return cached
        }
        
        // Try loading from disk if not found
        if data.violations.isEmpty {
            load()
            return data.violations[stableId]
        }
        
        return nil
    }
    
    /// Get all cached violations
    public func allViolations() -> [CachedViolation] {
        if data.violations.isEmpty {
            load()
        }
        return Array(data.violations.values)
    }
    
    /// Get count of cached violations
    public func count() -> Int {
        if data.violations.isEmpty {
            load()
        }
        return data.violations.count
    }
    
    /// Get the date of the last run
    public func lastRunDate() -> Date? {
        if data.violations.isEmpty {
            load()
        }
        return data.lastRunDate
    }
    
    /// Clear the cache
    public func clear() {
        data = ViolationCacheData()
        try? FileManager.default.removeItem(atPath: cacheFilePath)
    }
    
    // MARK: - Persistence
    
    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: URL(fileURLWithPath: cacheFilePath))
        } catch {
            // Cache is best-effort, log for debugging
            StrictSwiftLogger.debug("Failed to save violation cache: \(error)")
        }
    }
    
    private func load() {
        let path = cacheFilePath
        guard FileManager.default.fileExists(atPath: path) else { return }
        
        do {
            let jsonData = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            data = try decoder.decode(ViolationCacheData.self, from: jsonData)
        } catch {
            // Cache is best-effort, log for debugging and start with empty cache
            StrictSwiftLogger.debug("Failed to load violation cache: \(error)")
            data = ViolationCacheData()
        }
    }
}
