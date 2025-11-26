import Foundation

// MARK: - Pattern Statistics

/// Tracks accuracy statistics per rule and pattern over time
/// This implements Phase 2 of the learning system - pattern-based learning
public actor PatternStatistics {
    
    /// Default filename for statistics storage
    public static let defaultFileName = ".strictswift-statistics.json"
    
    /// Time-windowed statistics for a rule
    public struct RuleStatistics: Codable, Sendable {
        /// The rule identifier
        public let ruleId: String
        
        /// Total violations reported
        public var totalReported: Int
        
        /// Violations marked as true positives
        public var truePositives: Int
        
        /// Violations marked as false positives
        public var falsePositives: Int
        
        /// Fixes that were applied
        public var fixesApplied: Int
        
        /// Fixes that were rejected
        public var fixesRejected: Int
        
        /// Rolling windows of accuracy (last 7, 30, 90 days)
        public var windowedAccuracy: WindowedAccuracy
        
        /// Last time statistics were updated
        public var lastUpdated: Date
        
        /// Computed accuracy (0.0 - 1.0)
        public var accuracy: Double {
            let positive = truePositives + fixesApplied
            let negative = falsePositives + fixesRejected
            let total = positive + negative
            return total > 0 ? Double(positive) / Double(total) : 1.0
        }
        
        /// Feedback rate (% of violations that received feedback)
        public var feedbackRate: Double {
            let withFeedback = truePositives + falsePositives + fixesApplied + fixesRejected
            return totalReported > 0 ? Double(withFeedback) / Double(totalReported) : 0.0
        }
        
        public init(ruleId: String) {
            self.ruleId = ruleId
            self.totalReported = 0
            self.truePositives = 0
            self.falsePositives = 0
            self.fixesApplied = 0
            self.fixesRejected = 0
            self.windowedAccuracy = WindowedAccuracy()
            self.lastUpdated = Date()
        }
    }
    
    /// Rolling window accuracy tracking
    public struct WindowedAccuracy: Codable, Sendable {
        /// Daily buckets for rolling window calculation
        public var dailyBuckets: [DailyBucket]
        
        /// Accuracy over last 7 days
        public var last7Days: Double {
            calculateAccuracy(days: 7)
        }
        
        /// Accuracy over last 30 days
        public var last30Days: Double {
            calculateAccuracy(days: 30)
        }
        
        /// Accuracy over last 90 days
        public var last90Days: Double {
            calculateAccuracy(days: 90)
        }
        
        public init() {
            self.dailyBuckets = []
        }
        
        mutating func recordFeedback(positive: Bool, date: Date = Date()) {
            let dayKey = Self.dayKey(for: date)
            
            if let index = dailyBuckets.firstIndex(where: { $0.dayKey == dayKey }) {
                if positive {
                    dailyBuckets[index].positiveCount += 1
                } else {
                    dailyBuckets[index].negativeCount += 1
                }
            } else {
                dailyBuckets.append(DailyBucket(
                    dayKey: dayKey,
                    positiveCount: positive ? 1 : 0,
                    negativeCount: positive ? 0 : 1
                ))
            }
            
            // Prune old buckets (keep 90 days)
            pruneOldBuckets()
        }
        
        private mutating func pruneOldBuckets() {
            let cutoffKey = Self.dayKey(for: Date().addingTimeInterval(-91 * 24 * 60 * 60))
            dailyBuckets.removeAll { $0.dayKey < cutoffKey }
        }
        
        private func calculateAccuracy(days: Int) -> Double {
            let cutoffKey = Self.dayKey(for: Date().addingTimeInterval(-Double(days) * 24 * 60 * 60))
            let relevantBuckets = dailyBuckets.filter { $0.dayKey >= cutoffKey }
            
            let positive = relevantBuckets.reduce(0) { $0 + $1.positiveCount }
            let negative = relevantBuckets.reduce(0) { $0 + $1.negativeCount }
            let total = positive + negative
            
            return total > 0 ? Double(positive) / Double(total) : 1.0
        }
        
        private static func dayKey(for date: Date) -> Int {
            // Days since epoch
            return Int(date.timeIntervalSince1970 / (24 * 60 * 60))
        }
    }
    
    /// A single day's feedback counts
    public struct DailyBucket: Codable, Sendable {
        public let dayKey: Int
        public var positiveCount: Int
        public var negativeCount: Int
    }
    
    /// Pattern-level statistics
    public struct PatternStats: Codable, Sendable {
        /// Hash of the code pattern
        public let patternHash: String
        
        /// The rule this pattern belongs to
        public let ruleId: String
        
        /// Number of times this pattern was seen
        public var occurrences: Int
        
        /// Positive feedback count
        public var positiveCount: Int
        
        /// Negative feedback count
        public var negativeCount: Int
        
        /// Last occurrence
        public var lastSeen: Date
        
        /// Computed accuracy for this pattern
        public var accuracy: Double {
            let total = positiveCount + negativeCount
            return total > 0 ? Double(positiveCount) / Double(total) : 1.0
        }
        
        /// Whether this pattern should be suppressed (too many false positives)
        public var shouldSuppress: Bool {
            // Suppress if accuracy < 50% with at least 3 samples
            let total = positiveCount + negativeCount
            return total >= 3 && accuracy < 0.5
        }
        
        public init(patternHash: String, ruleId: String) {
            self.patternHash = patternHash
            self.ruleId = ruleId
            self.occurrences = 0
            self.positiveCount = 0
            self.negativeCount = 0
            self.lastSeen = Date()
        }
    }
    
    // MARK: - Storage
    
    private var ruleStats: [String: RuleStatistics] = [:]
    private var patternStats: [String: PatternStats] = [:]
    private let storageURL: URL
    private var isDirty: Bool = false
    
    // MARK: - Initialization
    
    public init(projectRoot: URL) {
        self.storageURL = projectRoot.appendingPathComponent(Self.defaultFileName)
    }
    
    public init(storageURL: URL) {
        self.storageURL = storageURL
    }
    
    // MARK: - Loading and Saving
    
    /// Load statistics from disk
    public func load() throws {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return
        }
        
        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let storage = try decoder.decode(StatisticsStorage.self, from: data)
        
        self.ruleStats = Dictionary(uniqueKeysWithValues: storage.ruleStatistics.map { ($0.ruleId, $0) })
        self.patternStats = Dictionary(uniqueKeysWithValues: storage.patternStatistics.map { ($0.patternHash, $0) })
        isDirty = false
    }
    
    /// Save statistics to disk
    public func save() throws {
        guard isDirty else { return }
        
        let storage = StatisticsStorage(
            version: 1,
            lastUpdated: Date(),
            ruleStatistics: Array(ruleStats.values),
            patternStatistics: Array(patternStats.values)
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(storage)
        try data.write(to: storageURL, options: .atomic)
        isDirty = false
    }
    
    // MARK: - Recording
    
    /// Record that a violation was reported
    public func recordViolationReported(ruleId: String, patternHash: String? = nil) {
        ensureRuleStats(ruleId)
        ruleStats[ruleId]?.totalReported += 1
        ruleStats[ruleId]?.lastUpdated = Date()
        
        if let hash = patternHash {
            ensurePatternStats(hash, ruleId: ruleId)
            patternStats[hash]?.occurrences += 1
            patternStats[hash]?.lastSeen = Date()
        }
        
        isDirty = true
    }
    
    /// Record feedback for a violation
    public func recordFeedback(
        ruleId: String,
        patternHash: String?,
        isPositive: Bool,
        isFix: Bool = false
    ) {
        ensureRuleStats(ruleId)
        
        if isFix {
            if isPositive {
                ruleStats[ruleId]?.fixesApplied += 1
            } else {
                ruleStats[ruleId]?.fixesRejected += 1
            }
        } else {
            if isPositive {
                ruleStats[ruleId]?.truePositives += 1
            } else {
                ruleStats[ruleId]?.falsePositives += 1
            }
        }
        
        ruleStats[ruleId]?.windowedAccuracy.recordFeedback(positive: isPositive)
        ruleStats[ruleId]?.lastUpdated = Date()
        
        if let hash = patternHash {
            ensurePatternStats(hash, ruleId: ruleId)
            if isPositive {
                patternStats[hash]?.positiveCount += 1
            } else {
                patternStats[hash]?.negativeCount += 1
            }
            patternStats[hash]?.lastSeen = Date()
        }
        
        isDirty = true
    }
    
    // MARK: - Querying
    
    /// Get statistics for a rule
    public func statistics(forRule ruleId: String) -> RuleStatistics? {
        return ruleStats[ruleId]
    }
    
    /// Get statistics for a pattern
    public func statistics(forPattern patternHash: String) -> PatternStats? {
        return patternStats[patternHash]
    }
    
    /// Get all rule statistics
    public func allRuleStatistics() -> [RuleStatistics] {
        return Array(ruleStats.values)
    }
    
    /// Check if a pattern should be suppressed
    public func shouldSuppressPattern(_ patternHash: String) -> Bool {
        return patternStats[patternHash]?.shouldSuppress ?? false
    }
    
    /// Get confidence multiplier for a rule (based on historical accuracy)
    public func confidenceMultiplier(forRule ruleId: String) -> Double {
        guard let stats = ruleStats[ruleId] else { return 1.0 }
        
        // Use 30-day window for confidence adjustment
        let accuracy = stats.windowedAccuracy.last30Days
        
        // Apply smoothed adjustment based on feedback volume
        let feedbackCount = stats.truePositives + stats.falsePositives + 
                           stats.fixesApplied + stats.fixesRejected
        let volumeWeight = min(1.0, Double(feedbackCount) / 20.0)
        
        // Adjust confidence: low accuracy = lower confidence
        // Range: 0.5 (50% accuracy) to 1.0 (100% accuracy)
        return 0.5 + (0.5 * accuracy * volumeWeight) + (0.5 * (1.0 - volumeWeight))
    }
    
    /// Get confidence multiplier for a specific pattern
    public func confidenceMultiplier(forPattern patternHash: String) -> Double {
        guard let stats = patternStats[patternHash] else { return 1.0 }
        
        let total = stats.positiveCount + stats.negativeCount
        guard total > 0 else { return 1.0 }
        
        // Weight by sample size
        let sampleWeight = min(1.0, Double(total) / 5.0)
        
        // If pattern is very inaccurate, significantly reduce confidence
        if stats.shouldSuppress {
            return 0.3 // Heavily penalize suppressed patterns
        }
        
        return 0.5 + (0.5 * stats.accuracy * sampleWeight) + (0.5 * (1.0 - sampleWeight))
    }
    
    // MARK: - Reports
    
    /// Summary of all statistics
    public struct Summary: Sendable {
        public let totalRules: Int
        public let totalPatterns: Int
        public let totalViolationsReported: Int
        public let totalFeedbackReceived: Int
        public let overallAccuracy: Double
        public let rulesWithLowAccuracy: [String]
        public let suppressedPatterns: Int
    }
    
    /// Get summary statistics
    public func summary() -> Summary {
        let totalViolations = ruleStats.values.reduce(0) { $0 + $1.totalReported }
        let positive = ruleStats.values.reduce(0) { $0 + $1.truePositives + $1.fixesApplied }
        let negative = ruleStats.values.reduce(0) { $0 + $1.falsePositives + $1.fixesRejected }
        let totalFeedback = positive + negative
        let accuracy = totalFeedback > 0 ? Double(positive) / Double(totalFeedback) : 1.0
        
        let lowAccuracyRules = ruleStats.values
            .filter { $0.accuracy < 0.7 && ($0.truePositives + $0.falsePositives) >= 5 }
            .map { $0.ruleId }
        
        let suppressed = patternStats.values.filter { $0.shouldSuppress }.count
        
        return Summary(
            totalRules: ruleStats.count,
            totalPatterns: patternStats.count,
            totalViolationsReported: totalViolations,
            totalFeedbackReceived: totalFeedback,
            overallAccuracy: accuracy,
            rulesWithLowAccuracy: lowAccuracyRules,
            suppressedPatterns: suppressed
        )
    }
    
    // MARK: - Maintenance
    
    /// Remove patterns that haven't been seen recently
    public func pruneStalePatterns(olderThan days: Int = 90) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let originalCount = patternStats.count
        
        patternStats = patternStats.filter { $0.value.lastSeen >= cutoff }
        
        if patternStats.count != originalCount {
            isDirty = true
        }
    }
    
    /// Clear all statistics
    public func clear() {
        ruleStats.removeAll()
        patternStats.removeAll()
        isDirty = true
    }
    
    // MARK: - Private Helpers
    
    private func ensureRuleStats(_ ruleId: String) {
        if ruleStats[ruleId] == nil {
            ruleStats[ruleId] = RuleStatistics(ruleId: ruleId)
        }
    }
    
    private func ensurePatternStats(_ hash: String, ruleId: String) {
        if patternStats[hash] == nil {
            patternStats[hash] = PatternStats(patternHash: hash, ruleId: ruleId)
        }
    }
}

// MARK: - Storage Format

private struct StatisticsStorage: Codable {
    let version: Int
    let lastUpdated: Date
    let ruleStatistics: [PatternStatistics.RuleStatistics]
    let patternStatistics: [PatternStatistics.PatternStats]
}
