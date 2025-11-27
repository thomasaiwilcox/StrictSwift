import Foundation

// MARK: - Learned Corrections Storage

/// Storage for explicit feedback on violations from agents and users
/// This implements Phase 1 of the learning system - explicit corrections
public actor LearnedCorrections {
    
    /// Default filename for corrections storage
    public static let defaultFileName = ".strictswift-corrections.json"
    
    /// The feedback type for a violation
    public enum FeedbackType: String, Codable, Sendable {
        /// The violation was useful/accurate - a true positive
        case used
        /// The violation was not useful/inaccurate - a false positive
        case unused
        /// The fix was applied successfully
        case fixApplied
        case fixRejected
    }
    
    /// A recorded correction/feedback entry
    public struct CorrectionEntry: Codable, Sendable, Equatable {
        public let id: UUID, violationId: String, ruleId: String, filePath: String
        public let line: Int
        public let feedback: FeedbackType
        public let note: String?, contextHash: String?
        public let timestamp: Date
        public let source: String
        
        public init(id: UUID = UUID(), violationId: String, ruleId: String, filePath: String,
                    line: Int, feedback: FeedbackType, note: String? = nil,
                    timestamp: Date = Date(), source: String = "user", contextHash: String? = nil) {
            self.id = id; self.violationId = violationId; self.ruleId = ruleId
            self.filePath = filePath; self.line = line; self.feedback = feedback
            self.note = note; self.timestamp = timestamp; self.source = source
            self.contextHash = contextHash
        }
    }
    
    private var corrections: [CorrectionEntry] = []
    private var byRuleId: [String: [CorrectionEntry]] = [:]
    private var byFilePath: [String: [CorrectionEntry]] = [:]
    private var byContextHash: [String: [CorrectionEntry]] = [:]
    private let storageURL: URL
    private var isDirty: Bool = false
    
    // MARK: - Initialization
    
    public init(projectRoot: URL) { self.storageURL = projectRoot.appendingPathComponent(Self.defaultFileName) }
    public init(storageURL: URL) { self.storageURL = storageURL }
    
    // MARK: - Loading and Saving
    
    /// Load corrections from disk
    public func load() throws {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let storage = try decoder.decode(CorrectionStorage.self, from: data)
        self.corrections = storage.corrections
        
        // Rebuild indexes
        rebuildIndexes()
        isDirty = false
    }
    
    /// Save corrections to disk
    public func save() throws {
        guard isDirty else { return }
        
        let storage = CorrectionStorage(
            version: 1,
            lastUpdated: Date(),
            corrections: corrections
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(storage)
        try data.write(to: storageURL, options: .atomic)
        isDirty = false
    }
    
    // MARK: - Recording Feedback
    
    /// Record feedback for a violation
    public func recordFeedback(
        violationId: String,
        ruleId: String,
        filePath: String,
        line: Int,
        feedback: FeedbackType,
        note: String? = nil,
        source: String = "user",
        contextHash: String? = nil
    ) -> CorrectionEntry {
        let entry = CorrectionEntry(
            violationId: violationId,
            ruleId: ruleId,
            filePath: filePath,
            line: line,
            feedback: feedback,
            note: note,
            source: source,
            contextHash: contextHash
        )
        
        corrections.append(entry)
        
        // Update indexes
        byRuleId[ruleId, default: []].append(entry)
        byFilePath[filePath, default: []].append(entry)
        if let hash = contextHash {
            byContextHash[hash, default: []].append(entry)
        }
        
        isDirty = true
        return entry
    }
    
    /// Record feedback from a Violation object
    public func recordFeedback(
        for violation: Violation,
        feedback: FeedbackType,
        note: String? = nil,
        source: String = "user"
    ) -> CorrectionEntry {
        let contextHash = computeContextHash(violation: violation)
        let violationId = generateViolationId(violation: violation)
        
        return recordFeedback(
            violationId: violationId,
            ruleId: violation.ruleId,
            filePath: violation.location.file.path,
            line: violation.location.line,
            feedback: feedback,
            note: note,
            source: source,
            contextHash: contextHash
        )
    }
    
    // MARK: - Querying
    
    /// Get all corrections for a rule
    public func corrections(forRule ruleId: String) -> [CorrectionEntry] {
        return byRuleId[ruleId] ?? []
    }
    
    /// Get all corrections for a file
    public func corrections(forFile filePath: String) -> [CorrectionEntry] {
        return byFilePath[filePath] ?? []
    }
    
    /// Get corrections matching a context hash
    public func corrections(matchingContext contextHash: String) -> [CorrectionEntry] {
        return byContextHash[contextHash] ?? []
    }
    
    /// Get all corrections
    public func allCorrections() -> [CorrectionEntry] {
        return corrections
    }
    
    /// Get corrections within a time range
    public func corrections(from startDate: Date, to endDate: Date) -> [CorrectionEntry] {
        return corrections.filter { entry in
            entry.timestamp >= startDate && entry.timestamp <= endDate
        }
    }
    
    /// Check if a similar violation has been marked as unused (false positive)
    public func hasFalsePositiveMatch(
        ruleId: String,
        contextHash: String?
    ) -> Bool {
        // First check by context hash for exact pattern match
        if let hash = contextHash {
            let hashMatches = byContextHash[hash] ?? []
            if hashMatches.contains(where: { $0.feedback == .unused }) {
                return true
            }
        }
        
        // Fall back to rule-level statistics
        let ruleCorrections = byRuleId[ruleId] ?? []
        let recentUnused = ruleCorrections.filter { 
            $0.feedback == .unused && 
            $0.timestamp > Date().addingTimeInterval(-30 * 24 * 60 * 60) // Last 30 days
        }
        
        return recentUnused.count >= 3 // Threshold for suppression
    }
    
    /// Get confidence adjustment for a rule based on feedback
    /// Returns a multiplier (0.0 - 1.0) to apply to the rule's confidence
    public func confidenceAdjustment(forRule ruleId: String) -> Double {
        let ruleCorrections = byRuleId[ruleId] ?? []
        guard !ruleCorrections.isEmpty else { return 1.0 }
        
        let used = ruleCorrections.filter { $0.feedback == .used || $0.feedback == .fixApplied }.count
        let unused = ruleCorrections.filter { $0.feedback == .unused || $0.feedback == .fixRejected }.count
        
        let total = used + unused
        guard total > 0 else { return 1.0 }
        
        // Calculate accuracy rate
        let accuracy = Double(used) / Double(total)
        
        // Apply a smoothed adjustment (don't go below 0.5 unless very confident)
        // More samples = more confident adjustment
        let sampleWeight = min(1.0, Double(total) / 20.0) // Full weight at 20+ samples
        return 1.0 - (sampleWeight * (1.0 - accuracy) * 0.5)
    }
    
    // MARK: - Statistics
    
    /// Summary statistics for learned corrections
    public struct Summary: Sendable {
        public let totalCorrections, usedCount, unusedCount, fixAppliedCount, fixRejectedCount, rulesWithFeedback: Int
        public let overallAccuracy: Double
    }
    
    /// Statistics for a single rule
    public struct RuleStats: Sendable {
        public let totalFeedback, positiveCount, negativeCount: Int
        public let accuracy, confidenceAdjustment: Double
    }
    
    /// Get summary statistics
    public func summary() -> Summary {
        var used = 0, unused = 0, fixApplied = 0, fixRejected = 0
        for c in corrections {
            switch c.feedback {
            case .used: used += 1
            case .unused: unused += 1
            case .fixApplied: fixApplied += 1
            case .fixRejected: fixRejected += 1
            }
        }
        let positive = used + fixApplied, negative = unused + fixRejected
        let accuracy = (positive + negative) > 0 ? Double(positive) / Double(positive + negative) : 1.0
        return Summary(totalCorrections: corrections.count, usedCount: used, unusedCount: unused,
                       fixAppliedCount: fixApplied, fixRejectedCount: fixRejected,
                       rulesWithFeedback: byRuleId.count, overallAccuracy: accuracy)
    }
    
    /// Get per-rule statistics
    public func ruleStatistics() -> [String: RuleStats] {
        var stats: [String: RuleStats] = [:]
        for (ruleId, entries) in byRuleId {
            var positive = 0, negative = 0
            for e in entries {
                if e.feedback == .used || e.feedback == .fixApplied { positive += 1 }
                else { negative += 1 }
            }
            let accuracy = (positive + negative) > 0 ? Double(positive) / Double(positive + negative) : 1.0
            stats[ruleId] = RuleStats(totalFeedback: entries.count, positiveCount: positive, negativeCount: negative,
                                      accuracy: accuracy, confidenceAdjustment: confidenceAdjustment(forRule: ruleId))
        }
        return stats
    }
    
    // MARK: - Maintenance
    
    /// Remove old corrections beyond retention period
    public func pruneOldCorrections(olderThan days: Int = 90) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let originalCount = corrections.count
        corrections.removeAll { $0.timestamp < cutoff }
        if corrections.count != originalCount { rebuildIndexes(); isDirty = true }
    }
    
    /// Clear all corrections
    public func clear() {
        corrections.removeAll()
        byRuleId.removeAll()
        byFilePath.removeAll()
        byContextHash.removeAll()
        isDirty = true
    }
    
    // MARK: - Private Helpers
    
    private func rebuildIndexes() {
        byRuleId.removeAll()
        byFilePath.removeAll()
        byContextHash.removeAll()
        
        for entry in corrections {
            byRuleId[entry.ruleId, default: []].append(entry)
            byFilePath[entry.filePath, default: []].append(entry)
            if let hash = entry.contextHash {
                byContextHash[hash, default: []].append(entry)
            }
        }
    }
    
    private func generateViolationId(violation: Violation) -> String {
        // Generate a stable ID from violation properties
        var hasher = Hasher()
        hasher.combine(violation.ruleId)
        hasher.combine(violation.location.file.path)
        hasher.combine(violation.location.line)
        hasher.combine(violation.location.column)
        hasher.combine(violation.message)
        return String(format: "%08x", hasher.finalize() & 0xFFFFFFFF)
    }
    
    private func computeContextHash(violation: Violation) -> String {
        // Create a hash from the violation's context for pattern matching
        // This allows us to recognize similar code patterns across files
        var hasher = Hasher()
        hasher.combine(violation.ruleId)
        hasher.combine(violation.message)
        return String(format: "%08x", hasher.finalize() & 0xFFFFFFFF)
    }
}

// MARK: - Storage Format

/// On-disk storage format for corrections
private struct CorrectionStorage: Codable {
    let version: Int
    let lastUpdated: Date
    let corrections: [LearnedCorrections.CorrectionEntry]
}
