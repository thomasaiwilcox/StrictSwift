import Foundation

// MARK: - Analysis Runner

/// High-level analysis runner that coordinates analyzer, caching, and learning
/// Use this for full analysis workflows instead of Analyzer directly
/// SAFETY: @unchecked Sendable is safe because all mutable state is managed through
/// actor-based subsystems (AnalysisCache, LearningSystem) ensuring safe concurrent access.
public final class AnalysisRunner: @unchecked Sendable {
    
    private let configuration: Configuration
    private let cache: AnalysisCache?
    private let learning: LearningSystem?
    private let analyzer: Analyzer
    
    /// Initialize with configuration and optional subsystems
    public init(configuration: Configuration, cache: AnalysisCache? = nil, learning: LearningSystem? = nil) {
        self.configuration = configuration
        self.cache = cache
        self.learning = learning
        self.analyzer = Analyzer(configuration: configuration, cache: cache)
    }
    
    /// Initialize with project root (creates default subsystems)
    public init(configuration: Configuration, projectRoot: URL, enableLearning: Bool = false) {
        self.configuration = configuration
        self.cache = nil
        self.learning = enableLearning ? LearningSystem(projectRoot: projectRoot) : nil
        self.analyzer = Analyzer(configuration: configuration, cache: nil)
    }
    
    // MARK: - Analysis
    
    /// Analyze paths with learning system integration
    public func analyze(paths: [String]) async throws -> AnalysisRunResult {
        if let learning = learning { try await learning.load() }
        
        let (rawViolations, cacheStats) = try await runAnalysis(paths: paths)
        
        if let learning = learning { await learning.recordViolationsReported(rawViolations) }
        
        let (finalViolations, learningStats) = await applyLearning(to: rawViolations)
        
        // Cache violations for feedback lookup
        await ViolationCache.shared.storeViolations(finalViolations)
        
        return AnalysisRunResult(violations: finalViolations, rawViolationCount: rawViolations.count,
                                  suppressedCount: rawViolations.count - finalViolations.count,
                                  cacheStats: cacheStats, learningStats: learningStats)
    }
    
    private func runAnalysis(paths: [String]) async throws -> ([Violation], RunCacheStats?) {
        if cache != nil {
            let result = try await analyzer.analyzeIncremental(paths: paths)
            return (result.violations, RunCacheStats(cachedFiles: result.cachedFileCount,
                                                      analyzedFiles: result.analyzedFileCount,
                                                      hitRate: result.cacheHitRate))
        }
        return (try await analyzer.analyze(paths: paths), nil)
    }
    
    private func applyLearning(to violations: [Violation]) async -> ([Violation], LearningStatisticsSummary?) {
        guard let learning = learning else { return (violations, nil) }
        let filtered = await learning.applyLearning(to: violations)
        let stats = await learning.overallStatistics()
        try? await learning.save()
        return (filtered, stats)
    }
    
    /// Record feedback for a violation
    public func recordFeedback(for violation: Violation, feedback: LearnedCorrections.FeedbackType,
                               note: String? = nil, source: String = "user") async throws {
        guard let learning = learning else { return }
        try await learning.load()
        await learning.recordFeedback(for: violation, feedback: feedback, note: note, source: source)
        try await learning.save()
    }
}

// MARK: - Result Types

/// Result from an analysis run including learning statistics
public struct AnalysisRunResult: Sendable {
    public let violations: [Violation]
    public let rawViolationCount: Int
    public let suppressedCount: Int
    public let cacheStats: RunCacheStats?
    public let learningStats: LearningStatisticsSummary?
}

/// Cache hit/miss statistics for a run
public struct RunCacheStats: Sendable {
    public let cachedFiles: Int
    public let analyzedFiles: Int
    public let hitRate: Double
}
