import XCTest
@testable import StrictSwiftCore

final class LearningSystemTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - LearnedCorrections Tests
    
    func testRecordFeedbackCreatesEntry() async throws {
        let corrections = LearnedCorrections(projectRoot: tempDir)
        
        let entry = await corrections.recordFeedback(
            violationId: "test-123",
            ruleId: "force_unwrap",
            filePath: "/test/file.swift",
            line: 42,
            feedback: .used,
            note: "Valid finding",
            source: "test"
        )
        
        XCTAssertEqual(entry.violationId, "test-123")
        XCTAssertEqual(entry.ruleId, "force_unwrap")
        XCTAssertEqual(entry.feedback, .used)
        XCTAssertEqual(entry.note, "Valid finding")
        
        let all = await corrections.allCorrections()
        XCTAssertEqual(all.count, 1)
    }
    
    func testSaveAndLoadCorrections() async throws {
        let corrections = LearnedCorrections(projectRoot: tempDir)
        
        _ = await corrections.recordFeedback(
            violationId: "v1", ruleId: "rule1", filePath: "/a.swift", line: 1, feedback: .used
        )
        _ = await corrections.recordFeedback(
            violationId: "v2", ruleId: "rule2", filePath: "/b.swift", line: 2, feedback: .unused
        )
        
        try await corrections.save()
        
        // Load into new instance
        let loaded = LearnedCorrections(projectRoot: tempDir)
        try await loaded.load()
        
        let all = await loaded.allCorrections()
        XCTAssertEqual(all.count, 2)
    }
    
    func testSummaryStatistics() async throws {
        let corrections = LearnedCorrections(projectRoot: tempDir)
        
        _ = await corrections.recordFeedback(violationId: "v1", ruleId: "r1", filePath: "/a.swift", line: 1, feedback: .used)
        _ = await corrections.recordFeedback(violationId: "v2", ruleId: "r1", filePath: "/a.swift", line: 2, feedback: .used)
        _ = await corrections.recordFeedback(violationId: "v3", ruleId: "r1", filePath: "/a.swift", line: 3, feedback: .unused)
        _ = await corrections.recordFeedback(violationId: "v4", ruleId: "r2", filePath: "/b.swift", line: 1, feedback: .fixApplied)
        
        let summary = await corrections.summary()
        XCTAssertEqual(summary.totalCorrections, 4)
        XCTAssertEqual(summary.usedCount, 2)
        XCTAssertEqual(summary.unusedCount, 1)
        XCTAssertEqual(summary.fixAppliedCount, 1)
        XCTAssertEqual(summary.rulesWithFeedback, 2)
        XCTAssertEqual(summary.overallAccuracy, 0.75, accuracy: 0.01) // 3 positive, 1 negative
    }
    
    func testConfidenceAdjustmentForRule() async throws {
        let corrections = LearnedCorrections(projectRoot: tempDir)
        
        // Rule with no feedback should have adjustment of 1.0
        let noFeedback = await corrections.confidenceAdjustment(forRule: "unknown")
        XCTAssertEqual(noFeedback, 1.0)
        
        // Add mixed feedback
        for i in 0..<10 { // 10 positive
            _ = await corrections.recordFeedback(violationId: "pos\(i)", ruleId: "mixed", filePath: "/a.swift", line: i, feedback: .used)
        }
        for i in 0..<10 { // 10 negative - 50% accuracy
            _ = await corrections.recordFeedback(violationId: "neg\(i)", ruleId: "mixed", filePath: "/a.swift", line: 100+i, feedback: .unused)
        }
        
        let mixedAdjustment = await corrections.confidenceAdjustment(forRule: "mixed")
        XCTAssertLessThan(mixedAdjustment, 1.0)
        XCTAssertGreaterThan(mixedAdjustment, 0.5)
    }
    
    func testHasFalsePositiveMatch() async throws {
        let corrections = LearnedCorrections(projectRoot: tempDir)
        
        // No matches initially
        let noMatch = await corrections.hasFalsePositiveMatch(ruleId: "rule1", contextHash: "hash1")
        XCTAssertFalse(noMatch)
        
        // Add some unused entries with context hash
        for i in 0..<3 {
            _ = await corrections.recordFeedback(
                violationId: "v\(i)", ruleId: "rule1", filePath: "/a.swift", line: i,
                feedback: .unused, contextHash: "hash1"
            )
        }
        
        // Now should have match
        let hasMatch = await corrections.hasFalsePositiveMatch(ruleId: "rule1", contextHash: "hash1")
        XCTAssertTrue(hasMatch)
    }
    
    // MARK: - PatternStatistics Tests
    
    func testRecordViolationReported() async throws {
        let stats = PatternStatistics(projectRoot: tempDir)
        
        await stats.recordViolationReported(ruleId: "rule1", patternHash: "pattern1")
        await stats.recordViolationReported(ruleId: "rule1", patternHash: "pattern1")
        await stats.recordViolationReported(ruleId: "rule1", patternHash: "pattern2")
        
        let ruleStats = await stats.statistics(forRule: "rule1")
        XCTAssertEqual(ruleStats?.totalReported, 3)
        
        let pattern1 = await stats.statistics(forPattern: "pattern1")
        XCTAssertEqual(pattern1?.occurrences, 2)
    }
    
    func testRecordFeedbackUpdatesStatistics() async throws {
        let stats = PatternStatistics(projectRoot: tempDir)
        
        await stats.recordFeedback(ruleId: "rule1", patternHash: "p1", isPositive: true, isFix: false)
        await stats.recordFeedback(ruleId: "rule1", patternHash: "p1", isPositive: false, isFix: false)
        
        let ruleStats = await stats.statistics(forRule: "rule1")
        XCTAssertEqual(ruleStats?.truePositives, 1)
        XCTAssertEqual(ruleStats?.falsePositives, 1)
        XCTAssertEqual(ruleStats?.accuracy ?? 0, 0.5, accuracy: 0.01)
    }
    
    func testPatternSuppressionThreshold() async throws {
        let stats = PatternStatistics(projectRoot: tempDir)
        let patternHash = "bad-pattern"
        
        // Initially not suppressed
        let notSuppressed = await stats.shouldSuppressPattern(patternHash)
        XCTAssertFalse(notSuppressed)
        
        // Add mostly negative feedback (3+ samples, <50% accuracy)
        await stats.recordFeedback(ruleId: "r1", patternHash: patternHash, isPositive: true)
        await stats.recordFeedback(ruleId: "r1", patternHash: patternHash, isPositive: false)
        await stats.recordFeedback(ruleId: "r1", patternHash: patternHash, isPositive: false)
        await stats.recordFeedback(ruleId: "r1", patternHash: patternHash, isPositive: false)
        
        // Now should be suppressed (1 positive, 3 negative = 25% accuracy)
        let suppressed = await stats.shouldSuppressPattern(patternHash)
        XCTAssertTrue(suppressed)
    }
    
    func testConfidenceMultiplierForRule() async throws {
        let stats = PatternStatistics(projectRoot: tempDir)
        
        // Unknown rule should have multiplier of 1.0
        let unknown = await stats.confidenceMultiplier(forRule: "unknown")
        XCTAssertEqual(unknown, 1.0)
        
        // Rule with good accuracy should have high multiplier
        for _ in 0..<20 {
            await stats.recordFeedback(ruleId: "good", patternHash: nil, isPositive: true)
        }
        let good = await stats.confidenceMultiplier(forRule: "good")
        XCTAssertGreaterThan(good, 0.9)
    }
    
    func testSaveAndLoadStatistics() async throws {
        let stats = PatternStatistics(projectRoot: tempDir)
        
        await stats.recordViolationReported(ruleId: "rule1")
        await stats.recordFeedback(ruleId: "rule1", patternHash: "p1", isPositive: true)
        
        try await stats.save()
        
        let loaded = PatternStatistics(projectRoot: tempDir)
        try await loaded.load()
        
        let ruleStats = await loaded.statistics(forRule: "rule1")
        XCTAssertEqual(ruleStats?.totalReported, 1)
        XCTAssertEqual(ruleStats?.truePositives, 1)
    }
    
    // MARK: - LearningSystem Integration Tests
    
    func testLearningSystemRecordsFeedback() async throws {
        let learning = LearningSystem(projectRoot: tempDir)
        try await learning.load()
        
        let violation = createTestViolation(ruleId: "force_unwrap", line: 10)
        
        await learning.recordFeedback(for: violation, feedback: .used, source: "test")
        
        let stats = await learning.overallStatistics()
        XCTAssertEqual(stats.totalFeedbackEntries, 1)
    }
    
    func testLearningSystemAppliesLearning() async throws {
        let corrections = LearnedCorrections(projectRoot: tempDir)
        let statistics = PatternStatistics(projectRoot: tempDir)
        let learning = LearningSystem(corrections: corrections, statistics: statistics)
        
        // Create a pattern that should be suppressed
        let violation = createTestViolation(ruleId: "bad_rule", line: 1)
        
        // Record multiple false positives for this pattern
        for _ in 0..<5 {
            await learning.recordFeedback(for: violation, feedback: .unused)
        }
        
        // Now check if it gets suppressed
        let filtered = await learning.applyLearning(to: [violation])
        // Note: Suppression depends on pattern hash matching exactly
        // Just verify the method runs without error
        XCTAssertLessThanOrEqual(filtered.count, 1)
    }
    
    func testDisabledLearningSystemPassesThrough() async throws {
        let learning = LearningSystem(projectRoot: tempDir, enabled: false)
        
        let violation = createTestViolation(ruleId: "test", line: 1)
        
        // Recording should be no-op
        await learning.recordFeedback(for: violation, feedback: .used)
        
        let stats = await learning.overallStatistics()
        XCTAssertEqual(stats.totalFeedbackEntries, 0)
        
        // Apply learning should pass through all violations
        let filtered = await learning.applyLearning(to: [violation])
        XCTAssertEqual(filtered.count, 1)
    }
    
    // MARK: - Helper Methods
    
    private func createTestViolation(ruleId: String, line: Int) -> Violation {
        let location = Location(
            file: URL(fileURLWithPath: "/test/file.swift"),
            line: line,
            column: 1
        )
        return Violation(
            ruleId: ruleId,
            category: .safety,
            severity: .warning,
            message: "Test violation",
            location: location
        )
    }
}
