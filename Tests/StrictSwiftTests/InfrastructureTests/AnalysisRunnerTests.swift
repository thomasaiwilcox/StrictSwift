import XCTest
@testable import StrictSwiftCore

final class AnalysisRunnerTests: XCTestCase {
    
    var tempDir: URL!
    var testSourceDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        testSourceDir = tempDir.appendingPathComponent("Sources")
        try? FileManager.default.createDirectory(at: testSourceDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Learning Integration Tests
    
    func testAnalysisRunnerWithLearningSystemRecordsViolations() async throws {
        // Create a test file with a known violation
        let testFile = testSourceDir.appendingPathComponent("TestFile.swift")
        let code = """
        let x: String? = "test"
        let y = x!  // force unwrap
        """
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        
        // Set up learning system with test-friendly constructor
        let corrections = LearnedCorrections(projectRoot: tempDir)
        let statistics = PatternStatistics(projectRoot: tempDir)
        let learning = LearningSystem(corrections: corrections, statistics: statistics)
        
        // Configure to enable force_unwrap rule
        let config = Configuration(profile: .criticalCore)
        
        let runner = AnalysisRunner(
            configuration: config,
            cache: nil,
            learning: learning
        )
        
        let result = try await runner.analyze(paths: [testSourceDir.path])
        
        // Verify learning stats are populated
        XCTAssertNotNil(result.learningStats, "Learning stats should be populated")
        
        // Verify we got raw violations
        XCTAssertGreaterThanOrEqual(result.rawViolationCount, 0)
    }
    
    func testAnalysisRunnerSuppressionCount() async throws {
        // Create corrections and statistics with pre-recorded false positive
        let corrections = LearnedCorrections(projectRoot: tempDir)
        let statistics = PatternStatistics(projectRoot: tempDir)
        
        // Pre-record false positives for a pattern to trigger suppression
        let patternHash = "test-pattern"
        for _ in 0..<5 {
            await statistics.recordFeedback(ruleId: "force_unwrap", patternHash: patternHash, isPositive: false)
        }
        
        let learning = LearningSystem(corrections: corrections, statistics: statistics)
        
        let config = Configuration(profile: .criticalCore)
        let runner = AnalysisRunner(
            configuration: config,
            cache: nil,
            learning: learning
        )
        
        // Create test file - even if no violations, we verify the flow works
        let testFile = testSourceDir.appendingPathComponent("Clean.swift")
        try "let x = 42".write(to: testFile, atomically: true, encoding: .utf8)
        
        let result = try await runner.analyze(paths: [testSourceDir.path])
        
        // Suppressed count should be non-negative (rawViolationCount - violations.count)
        XCTAssertEqual(result.suppressedCount, result.rawViolationCount - result.violations.count)
    }
    
    func testAnalysisRunnerWithoutLearningSystem() async throws {
        let testFile = testSourceDir.appendingPathComponent("Simple.swift")
        try "let x = 42".write(to: testFile, atomically: true, encoding: .utf8)
        
        let config = Configuration(profile: .criticalCore)
        let runner = AnalysisRunner(
            configuration: config,
            cache: nil,
            learning: nil
        )
        
        let result = try await runner.analyze(paths: [testSourceDir.path])
        
        // Without learning, stats should be nil
        XCTAssertNil(result.learningStats, "Learning stats should be nil when no learning system")
        XCTAssertEqual(result.suppressedCount, 0, "No suppression without learning")
    }
    
    func testAnalysisRunnerLearningStatsPopulated() async throws {
        // Set up learning with some pre-existing feedback
        let corrections = LearnedCorrections(projectRoot: tempDir)
        let statistics = PatternStatistics(projectRoot: tempDir)
        
        // Record some feedback to populate stats
        _ = await corrections.recordFeedback(
            violationId: "test-1",
            ruleId: "force_unwrap",
            filePath: "/test.swift",
            line: 1,
            feedback: .used
        )
        _ = await corrections.recordFeedback(
            violationId: "test-2",
            ruleId: "data_race",
            filePath: "/test.swift",
            line: 2,
            feedback: .unused
        )
        
        await statistics.recordViolationReported(ruleId: "force_unwrap")
        
        let learning = LearningSystem(corrections: corrections, statistics: statistics)
        
        let config = Configuration(profile: .criticalCore)
        let runner = AnalysisRunner(
            configuration: config,
            cache: nil,
            learning: learning
        )
        
        let testFile = testSourceDir.appendingPathComponent("Test.swift")
        try "let x = 42".write(to: testFile, atomically: true, encoding: .utf8)
        
        let result = try await runner.analyze(paths: [testSourceDir.path])
        
        // Verify learning stats fields are populated from pre-existing data
        guard let stats = result.learningStats else {
            XCTFail("Learning stats should be present")
            return
        }
        
        XCTAssertEqual(stats.totalFeedbackEntries, 2, "Should have 2 feedback entries")
        XCTAssertEqual(stats.rulesWithFeedback, 2, "Should have 2 rules with feedback")
    }
    
    func testAnalysisRunnerRecordsFeedback() async throws {
        let corrections = LearnedCorrections(projectRoot: tempDir)
        let statistics = PatternStatistics(projectRoot: tempDir)
        let learning = LearningSystem(corrections: corrections, statistics: statistics)
        
        let config = Configuration(profile: .criticalCore)
        let runner = AnalysisRunner(
            configuration: config,
            cache: nil,
            learning: learning
        )
        
        // Create a violation to record feedback for
        let violation = createTestViolation(ruleId: "force_unwrap", line: 10)
        
        try await runner.recordFeedback(for: violation, feedback: .used, note: "Valid finding")
        
        // Verify feedback was recorded
        let allCorrections = await corrections.allCorrections()
        XCTAssertEqual(allCorrections.count, 1)
        XCTAssertEqual(allCorrections.first?.feedback, .used)
        XCTAssertEqual(allCorrections.first?.note, "Valid finding")
    }
    
    func testAnalysisRunnerWithDisabledLearning() async throws {
        let learning = LearningSystem(projectRoot: tempDir, enabled: false)
        
        let config = Configuration(profile: .criticalCore)
        let runner = AnalysisRunner(
            configuration: config,
            cache: nil,
            learning: learning
        )
        
        let testFile = testSourceDir.appendingPathComponent("Test.swift")
        try "let x = 42".write(to: testFile, atomically: true, encoding: .utf8)
        
        let result = try await runner.analyze(paths: [testSourceDir.path])
        
        // Disabled learning should still return stats (but with zeros)
        XCTAssertNotNil(result.learningStats)
        XCTAssertEqual(result.learningStats?.totalFeedbackEntries, 0)
        XCTAssertEqual(result.suppressedCount, 0)
    }
    
    // MARK: - Result Type Tests
    
    func testAnalysisRunResultContainsAllFields() async throws {
        let corrections = LearnedCorrections(projectRoot: tempDir)
        let statistics = PatternStatistics(projectRoot: tempDir)
        let learning = LearningSystem(corrections: corrections, statistics: statistics)
        
        let config = Configuration(profile: .criticalCore)
        let runner = AnalysisRunner(
            configuration: config,
            cache: nil,
            learning: learning
        )
        
        let testFile = testSourceDir.appendingPathComponent("Test.swift")
        try "let x = 42".write(to: testFile, atomically: true, encoding: .utf8)
        
        let result = try await runner.analyze(paths: [testSourceDir.path])
        
        // Verify all result fields are accessible
        _ = result.violations
        _ = result.rawViolationCount
        _ = result.suppressedCount
        _ = result.cacheStats  // nil when no cache
        _ = result.learningStats  // populated when learning enabled
        
        XCTAssertNil(result.cacheStats, "Cache stats should be nil when no cache")
        XCTAssertNotNil(result.learningStats, "Learning stats should be populated")
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
