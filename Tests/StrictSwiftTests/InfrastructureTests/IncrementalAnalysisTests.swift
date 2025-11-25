import XCTest
@testable import StrictSwiftCore

final class IncrementalAnalysisTests: XCTestCase {
    
    // MARK: - FileFingerprint Tests
    
    func testFileFingerprintHashConsistency() {
        let content = "let x = 1"
        let fingerprint1 = FileFingerprint(path: "/test.swift", content: content)
        let fingerprint2 = FileFingerprint(path: "/test.swift", content: content)
        
        XCTAssertEqual(fingerprint1.contentHash, fingerprint2.contentHash)
        XCTAssertEqual(fingerprint1.path, fingerprint2.path)
    }
    
    func testFileFingerprintHashDifference() {
        let fingerprint1 = FileFingerprint(path: "/test.swift", content: "let x = 1")
        let fingerprint2 = FileFingerprint(path: "/test.swift", content: "let x = 2")
        
        XCTAssertNotEqual(fingerprint1.contentHash, fingerprint2.contentHash)
    }
    
    func testFileFingerprintFNV1a() {
        // Test known FNV-1a hash values
        let hash1 = FileFingerprint.fnv1aHash("hello")
        let hash2 = FileFingerprint.fnv1aHash("hello")
        let hash3 = FileFingerprint.fnv1aHash("world")
        
        XCTAssertEqual(hash1, hash2, "Same input should produce same hash")
        XCTAssertNotEqual(hash1, hash3, "Different input should produce different hash")
    }
    
    func testFileFingerprintEquality() {
        let date = Date()
        let fp1 = FileFingerprint(path: "/test.swift", contentHash: 12345, modificationDate: date, size: 100)
        let fp2 = FileFingerprint(path: "/test.swift", contentHash: 12345, modificationDate: date, size: 100)
        let fp3 = FileFingerprint(path: "/other.swift", contentHash: 12345, modificationDate: date, size: 100)
        
        XCTAssertEqual(fp1, fp2)
        XCTAssertNotEqual(fp1, fp3)
    }
    
    // MARK: - CachedFileResult Tests
    
    func testCachedFileResultCreation() {
        let fingerprint = FileFingerprint(path: "/test.swift", content: "let x = 1")
        let violations: [Violation] = []
        
        let result = CachedFileResult(fingerprint: fingerprint, violations: violations, analyzerVersion: "0.9.0")
        
        XCTAssertEqual(result.fingerprint, fingerprint)
        XCTAssertEqual(result.violations.count, 0)
        XCTAssertEqual(result.analyzerVersion, "0.9.0")
    }
    
    // MARK: - CacheMetadata Tests
    
    func testCacheMetadataValidity() {
        let configHash: UInt64 = 12345
        let metadata = CacheMetadata(configurationHash: configHash)
        
        XCTAssertTrue(metadata.isValid(for: configHash))
        XCTAssertFalse(metadata.isValid(for: 54321))
    }
    
    // MARK: - AnalysisCache Tests
    
    func testAnalysisCacheCreation() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = Configuration.default
        
        let cache = AnalysisCache(projectRoot: tempDir, configuration: config, enabled: true)
        
        let stats = await cache.statistics
        XCTAssertEqual(stats.cachedFileCount, 0)
        XCTAssertTrue(stats.isEnabled)
    }
    
    func testAnalysisCacheDisabled() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = Configuration.default
        
        let cache = AnalysisCache(projectRoot: tempDir, configuration: config, enabled: false)
        
        let stats = await cache.statistics
        XCTAssertFalse(stats.isEnabled)
    }
    
    // MARK: - Configuration Discovery Tests
    
    func testConfigurationDiscoveryNoConfig() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let discovered = Configuration.discover(in: tempDir)
        XCTAssertNil(discovered)
    }
    
    func testConfigurationDiscoveryFindsHiddenYml() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create .strictswift.yml
        let configPath = tempDir.appendingPathComponent(".strictswift.yml")
        try "profile: critical-core".write(to: configPath, atomically: true, encoding: .utf8)
        
        let discovered = Configuration.discover(in: tempDir)
        XCTAssertNotNil(discovered)
        XCTAssertEqual(discovered?.lastPathComponent, ".strictswift.yml")
    }
    
    func testConfigurationDiscoveryFindsYaml() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create strictswift.yaml (not hidden)
        let configPath = tempDir.appendingPathComponent("strictswift.yaml")
        try "profile: critical-core".write(to: configPath, atomically: true, encoding: .utf8)
        
        let discovered = Configuration.discover(in: tempDir)
        XCTAssertNotNil(discovered)
        XCTAssertEqual(discovered?.lastPathComponent, "strictswift.yaml")
    }
    
    func testConfigurationDiscoveryPriority() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create both hidden and non-hidden configs
        let hiddenConfig = tempDir.appendingPathComponent(".strictswift.yml")
        let visibleConfig = tempDir.appendingPathComponent("strictswift.yml")
        
        try "profile: critical-core".write(to: hiddenConfig, atomically: true, encoding: .utf8)
        try "profile: strict".write(to: visibleConfig, atomically: true, encoding: .utf8)
        
        // Hidden config should take priority
        let discovered = Configuration.discover(in: tempDir)
        XCTAssertNotNil(discovered)
        XCTAssertEqual(discovered?.lastPathComponent, ".strictswift.yml")
    }
    
    // MARK: - SourceFile Fingerprinting Tests
    
    func testSourceFileFingerprintGeneration() {
        let url = URL(fileURLWithPath: "/tmp/test.swift")
        let source = "let x = 1"
        
        let sourceFile = SourceFile(url: url, source: source)
        let fingerprint = sourceFile.fingerprint
        
        XCTAssertEqual(fingerprint.path, "/tmp/test.swift")
        XCTAssertEqual(fingerprint.size, Int64(source.utf8.count))
        XCTAssertEqual(fingerprint.contentHash, FileFingerprint.fnv1aHash(source))
    }
    
    func testSourceFileContentHashConsistency() {
        let url = URL(fileURLWithPath: "/tmp/test.swift")
        let source = "struct MyStruct { var value: Int }"
        
        let sourceFile1 = SourceFile(url: url, source: source)
        let sourceFile2 = SourceFile(url: url, source: source)
        
        XCTAssertEqual(sourceFile1.contentHash, sourceFile2.contentHash)
        XCTAssertEqual(sourceFile1.fingerprint.contentHash, sourceFile2.fingerprint.contentHash)
    }
    
    // MARK: - IncrementalAnalysisResult Tests
    
    func testIncrementalAnalysisResultStatistics() {
        let result = IncrementalAnalysisResult(
            violations: [],
            cachedFileCount: 8,
            analyzedFileCount: 2,
            cacheHitRate: 0.8
        )
        
        XCTAssertEqual(result.totalFileCount, 10)
        XCTAssertEqual(result.cachedFileCount, 8)
        XCTAssertEqual(result.analyzedFileCount, 2)
        XCTAssertEqual(result.cacheHitRate, 0.8, accuracy: 0.001)
    }
    
    func testIncrementalAnalysisResultWithViolations() {
        let location = Location(file: URL(fileURLWithPath: "/test.swift"), line: 1, column: 1)
        let violation = Violation(
            ruleId: "test-rule",
            category: .safety,
            severity: .warning,
            message: "Test violation",
            location: location
        )
        
        let result = IncrementalAnalysisResult(
            violations: [violation],
            cachedFileCount: 5,
            analyzedFileCount: 5,
            cacheHitRate: 0.5
        )
        
        XCTAssertEqual(result.violations.count, 1)
        XCTAssertEqual(result.violations.first?.ruleId, "test-rule")
    }
    
    // MARK: - Analyzer Incremental Init Tests
    
    func testAnalyzerWithCache() async {
        let config = Configuration.default
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = AnalysisCache(projectRoot: tempDir, configuration: config)
        
        let analyzer = Analyzer(configuration: config, cache: cache)
        
        // Analyzer should be created successfully with cache
        XCTAssertNotNil(analyzer)
    }
    
    func testAnalyzerWithoutCache() async throws {
        let config = Configuration.default
        let analyzer = Analyzer(configuration: config)
        
        // Should work without cache (falls back to regular analysis)
        XCTAssertNotNil(analyzer)
    }
}
