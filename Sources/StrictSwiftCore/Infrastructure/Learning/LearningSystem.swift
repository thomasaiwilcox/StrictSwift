import Foundation

// MARK: - Learning System Coordinator

/// Coordinates the learning subsystems (corrections + statistics) with the analyzer
/// Provides a unified interface for recording feedback and adjusting analysis confidence
/// SAFETY: @unchecked Sendable is safe because all mutable state is managed through
/// actor-based subsystems (LearnedCorrections and PatternStatistics actors), ensuring
/// safe concurrent access. The LearningSystem class itself only holds immutable references.
// strictswift:ignore god_class - Coordinator pattern necessarily has multiple dependencies
public final class LearningSystem: @unchecked Sendable {
    
    /// The learned corrections storage (actor)
    public let corrections: LearnedCorrections
    
    /// The pattern statistics tracker (actor)
    public let statistics: PatternStatistics
    
    /// Whether the learning system is enabled
    public let isEnabled: Bool
    
    // MARK: - Initialization
    
    public init(projectRoot: URL, enabled: Bool = true) {
        self.corrections = LearnedCorrections(projectRoot: projectRoot)
        self.statistics = PatternStatistics(projectRoot: projectRoot)
        self.isEnabled = enabled
    }
    
    /// Initialize with custom storage locations (for testing)
    public init(
        corrections: LearnedCorrections,
        statistics: PatternStatistics,
        enabled: Bool = true
    ) {
        self.corrections = corrections
        self.statistics = statistics
        self.isEnabled = enabled
    }
    
    // MARK: - Loading and Saving
    
    /// Load learning data from disk
    public func load() async throws {
        guard isEnabled else { return }
        
        try await corrections.load()
        try await statistics.load()
    }
    
    /// Save learning data to disk
    public func save() async throws {
        guard isEnabled else { return }
        
        try await corrections.save()
        try await statistics.save()
    }
    
    // MARK: - Recording
    
    /// Record that violations were reported (for statistics tracking)
    public func recordViolationsReported(_ violations: [Violation]) async {
        guard isEnabled else { return }
        
        for violation in violations {
            let patternHash = computePatternHash(violation)
            await statistics.recordViolationReported(
                ruleId: violation.ruleId,
                patternHash: patternHash
            )
        }
    }
    
    /// Record feedback for a violation
    public func recordFeedback(
        for violation: Violation,
        feedback: LearnedCorrections.FeedbackType,
        note: String? = nil,
        source: String = "user"
    ) async {
        guard isEnabled else { return }
        
        // Record in corrections
        _ = await corrections.recordFeedback(
            for: violation,
            feedback: feedback,
            note: note,
            source: source
        )
        
        // Record in statistics
        let isPositive = feedback == .used || feedback == .fixApplied
        let isFix = feedback == .fixApplied || feedback == .fixRejected
        let patternHash = computePatternHash(violation)
        
        await statistics.recordFeedback(
            ruleId: violation.ruleId,
            patternHash: patternHash,
            isPositive: isPositive,
            isFix: isFix
        )
    }
    
    // MARK: - Confidence Adjustment
    
    /// Get confidence adjustment for a violation
    /// Returns a multiplier (0.0 - 1.0) to apply to the violation's confidence
    public func confidenceAdjustment(for violation: Violation) async -> Double {
        guard isEnabled else { return 1.0 }
        
        let patternHash = computePatternHash(violation)
        
        // Check if this specific pattern should be suppressed
        if await statistics.shouldSuppressPattern(patternHash) {
            return 0.3 // Heavy penalty for suppressed patterns
        }
        
        // Get pattern-level adjustment if available
        let patternMultiplier = await statistics.confidenceMultiplier(forPattern: patternHash)
        
        // Get rule-level adjustment
        let ruleMultiplier = await statistics.confidenceMultiplier(forRule: violation.ruleId)
        
        // Also check corrections for this pattern
        let correctionMultiplier = await corrections.confidenceAdjustment(forRule: violation.ruleId)
        
        // Combine adjustments (use geometric mean for balanced combination)
        return cbrt(patternMultiplier * ruleMultiplier * correctionMultiplier)
    }
    
    /// Check if a violation should be suppressed based on learning
    public func shouldSuppress(violation: Violation) async -> Bool {
        guard isEnabled else { return false }
        
        let patternHash = computePatternHash(violation)
        
        // Check if pattern has too many false positives
        if await statistics.shouldSuppressPattern(patternHash) {
            return true
        }
        
        // Check if there's a direct false positive match in corrections
        if await corrections.hasFalsePositiveMatch(
            ruleId: violation.ruleId,
            contextHash: patternHash
        ) {
            return true
        }
        
        return false
    }
    
    /// Apply learning adjustments to a list of violations
    /// Returns violations with suppressed violations filtered out
    public func applyLearning(to violations: [Violation]) async -> [Violation] {
        guard isEnabled else { return violations }
        
        var result: [Violation] = []
        
        for violation in violations {
            // Check if should be suppressed
            if await shouldSuppress(violation: violation) {
                continue
            }
            
            result.append(violation)
        }
        
        return result
    }
    
    // MARK: - Statistics Access
    
    /// Get overall learning statistics
    public func overallStatistics() async -> LearningStatisticsSummary {
        let correctionsSummary = await corrections.summary()
        let statsSummary = await statistics.summary()
        
        return LearningStatisticsSummary(
            totalFeedbackEntries: correctionsSummary.totalCorrections,
            totalViolationsTracked: statsSummary.totalViolationsReported,
            overallAccuracy: statsSummary.overallAccuracy,
            rulesWithFeedback: correctionsSummary.rulesWithFeedback,
            patternsTracked: statsSummary.totalPatterns,
            suppressedPatterns: statsSummary.suppressedPatterns,
            lowAccuracyRules: statsSummary.rulesWithLowAccuracy
        )
    }
    
    /// Get rule-specific statistics
    public func ruleStatistics(forRule ruleId: String) async -> RuleLearningStatistics? {
        let ruleStats = await statistics.statistics(forRule: ruleId)
        let correctionStats = await corrections.ruleStatistics()[ruleId]
        
        guard ruleStats != nil || correctionStats != nil else { return nil }
        
        return RuleLearningStatistics(
            ruleId: ruleId,
            totalReported: ruleStats?.totalReported ?? 0,
            truePositives: (ruleStats?.truePositives ?? 0) + (correctionStats?.positiveCount ?? 0),
            falsePositives: (ruleStats?.falsePositives ?? 0) + (correctionStats?.negativeCount ?? 0),
            accuracy: ruleStats?.accuracy ?? correctionStats?.accuracy ?? 1.0,
            confidenceMultiplier: await statistics.confidenceMultiplier(forRule: ruleId),
            last7DayAccuracy: ruleStats?.windowedAccuracy.last7Days ?? 1.0,
            last30DayAccuracy: ruleStats?.windowedAccuracy.last30Days ?? 1.0
        )
    }
    
    // MARK: - Maintenance
    
    /// Prune old data
    public func pruneOldData(olderThan days: Int = 90) async {
        await corrections.pruneOldCorrections(olderThan: days)
        await statistics.pruneStalePatterns(olderThan: days)
    }
    
    /// Clear all learning data
    public func clear() async {
        await corrections.clear()
        await statistics.clear()
    }
    
    // MARK: - Private Helpers
    
    private func computePatternHash(_ violation: Violation) -> String {
        // Create a hash from the violation's context for pattern matching
        var hasher = Hasher()
        hasher.combine(violation.ruleId)
        hasher.combine(violation.message)
        return String(format: "%08x", hasher.finalize() & 0xFFFFFFFF)
    }
}

// MARK: - Statistics Types

/// Overall learning system statistics
public struct LearningStatisticsSummary: Sendable {
    public let totalFeedbackEntries: Int
    public let totalViolationsTracked: Int
    public let overallAccuracy: Double
    public let rulesWithFeedback: Int
    public let patternsTracked: Int
    public let suppressedPatterns: Int
    public let lowAccuracyRules: [String]
}

/// Per-rule learning statistics
public struct RuleLearningStatistics: Sendable {
    public let ruleId: String
    public let totalReported: Int
    public let truePositives: Int
    public let falsePositives: Int
    public let accuracy: Double
    public let confidenceMultiplier: Double
    public let last7DayAccuracy: Double
    public let last30DayAccuracy: Double
}
