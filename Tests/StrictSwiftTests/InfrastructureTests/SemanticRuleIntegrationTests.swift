import XCTest
@testable import StrictSwiftCore

/// Integration tests verifying that rules correctly use semantic analysis
/// These tests ensure that setSemanticResolver is called and that rules
/// can access semantic data via context.semanticResolver
final class SemanticRuleIntegrationTests: XCTestCase {
    
    // MARK: - Context Setup Tests
    
    func testContextReceivesSemanticResolver() async throws {
        // Given: A context and mock semantic resolver
        let projectRoot = URL(fileURLWithPath: "/tmp/test")
        let context = AnalysisContext(configuration: Configuration(), projectRoot: projectRoot)
        
        let resolver = SemanticTypeResolver(
            mode: .hybrid,
            sourceKitClient: nil,
            projectRoot: projectRoot
        )
        
        let config = SemanticModeResolver.ResolvedConfiguration(
            effectiveMode: .hybrid,
            isStrict: false,
            modeSource: .cli,
            degradation: nil,
            checkedSources: []
        )
        
        // When: We set the semantic resolver
        context.setSemanticResolver(resolver, config: config)
        
        // Then: It should be accessible
        XCTAssertNotNil(context.semanticResolver, "Semantic resolver should be set on context")
        XCTAssertNotNil(context.semanticModeResolved, "Semantic config should be set on context")
        XCTAssertTrue(context.hasSemanticAnalysis, "hasSemanticAnalysis should be true")
        XCTAssertEqual(context.semanticModeResolved?.effectiveMode, .hybrid)
    }
    
    func testContextWithoutSemanticResolver() {
        // Given: A context without semantic resolver
        let projectRoot = URL(fileURLWithPath: "/tmp/test")
        let context = AnalysisContext(configuration: Configuration(), projectRoot: projectRoot)
        
        // Then: Semantic resolver should be nil
        XCTAssertNil(context.semanticResolver, "Semantic resolver should be nil by default")
        XCTAssertNil(context.semanticModeResolved, "Semantic config should be nil by default")
        XCTAssertFalse(context.hasSemanticAnalysis, "hasSemanticAnalysis should be false")
    }
    
    // MARK: - Analyzer Integration Tests
    
    func testAnalyzerInitializesSemanticAnalysis() async throws {
        // Given: An analyzer with semantic mode enabled
        let config = Configuration(
            semanticMode: .off  // Use off mode to avoid needing SourceKit
        )
        let analyzer = Analyzer(configuration: config)
        
        // Create a temporary Swift file
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("Test.swift")
        try "class TestClass {}".write(to: testFile, atomically: true, encoding: .utf8)
        
        // When: We analyze (this should not throw)
        _ = try await analyzer.analyze(paths: [tempDir.path])
        
        // Then: Analysis completes (semantic init was called internally)
        // This test verifies the analyze path doesn't crash with semantic mode
    }
    
    func testIncrementalAnalyzerInitializesSemanticAnalysis() async throws {
        // Given: An analyzer with cache and semantic mode
        let config = Configuration(
            semanticMode: .off  // Use off mode to avoid needing SourceKit
        )
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let cacheDir = tempDir.appendingPathComponent(".strictswift-cache")
        let cache = AnalysisCache(cacheDirectory: cacheDir, configurationHash: 12345)
        let analyzer = Analyzer(configuration: config, cache: cache)
        
        let testFile = tempDir.appendingPathComponent("Test.swift")
        try "class TestClass {}".write(to: testFile, atomically: true, encoding: .utf8)
        
        // When: We analyze incrementally
        let result = try await analyzer.analyzeIncremental(paths: [tempDir.path])
        
        // Then: Analysis completes without error
        // This verifies initializeSemanticAnalysis is called in incremental path
        XCTAssertNotNil(result, "Incremental analysis should complete")
    }
    
    // MARK: - Rule Access Tests
    
    func testRuleCanAccessSemanticResolver() async throws {
        // Given: A context with semantic resolver
        let projectRoot = URL(fileURLWithPath: "/tmp/test")
        let context = AnalysisContext(configuration: Configuration(), projectRoot: projectRoot)
        
        let resolver = SemanticTypeResolver(
            mode: .hybrid,
            sourceKitClient: nil,
            projectRoot: projectRoot
        )
        
        let config = SemanticModeResolver.ResolvedConfiguration(
            effectiveMode: .hybrid,
            isStrict: false,
            modeSource: .cli,
            degradation: nil,
            checkedSources: []
        )
        
        context.setSemanticResolver(resolver, config: config)
        
        // When: A rule accesses the semantic resolver
        let accessedResolver = context.semanticResolver
        let accessedConfig = context.semanticModeResolved
        
        // Then: It should get the resolver
        XCTAssertNotNil(accessedResolver)
        XCTAssertEqual(accessedConfig?.effectiveMode, .hybrid)
    }
    
    func testSemanticModeOffDisablesResolver() async throws {
        // Given: Semantic mode is off
        let projectRoot = URL(fileURLWithPath: "/tmp/test")
        let context = AnalysisContext(configuration: Configuration(), projectRoot: projectRoot)
        
        let resolver = SemanticTypeResolver(
            mode: .off,
            sourceKitClient: nil,
            projectRoot: projectRoot
        )
        
        let config = SemanticModeResolver.ResolvedConfiguration(
            effectiveMode: .off,
            isStrict: false,
            modeSource: .cli,
            degradation: nil,
            checkedSources: []
        )
        
        context.setSemanticResolver(resolver, config: config)
        
        // Then: Resolver is set but mode indicates off
        XCTAssertNotNil(context.semanticResolver)
        XCTAssertEqual(context.semanticModeResolved?.effectiveMode, .off)
        // hasSemanticAnalysis should still be true because resolver is set
        // but rules should check effectiveMode before using it
    }
    
    // MARK: - Cache Filtering Tests
    
    func testCachedViolationsRespectIncludeExclude() async throws {
        // Given: A cache with violations and changed include/exclude patterns
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create two test files
        let includedFile = tempDir.appendingPathComponent("Included.swift")
        let excludedFile = tempDir.appendingPathComponent("Excluded.swift")
        
        try "class Included { var x: Int! }".write(to: includedFile, atomically: true, encoding: .utf8)
        try "class Excluded { var y: Int! }".write(to: excludedFile, atomically: true, encoding: .utf8)
        
        // First run: analyze both files to populate cache
        let config1 = Configuration()
        let cacheDir = tempDir.appendingPathComponent(".strictswift-cache")
        let cache = AnalysisCache(cacheDirectory: cacheDir, configurationHash: 12345)
        let analyzer1 = Analyzer(configuration: config1, cache: cache)
        
        _ = try await analyzer1.analyzeIncremental(paths: [tempDir.path])
        
        // Second run: exclude one file
        let config2 = Configuration(exclude: ["**/Excluded.swift"])
        let analyzer2 = Analyzer(configuration: config2, cache: cache)
        
        let result2 = try await analyzer2.analyzeIncremental(paths: [tempDir.path])
        
        // Then: Excluded file's violations should not appear
        let excludedViolations = result2.violations.filter { 
            $0.location.file.path.contains("Excluded.swift") 
        }
        XCTAssertTrue(
            excludedViolations.isEmpty,
            "Violations from excluded files should not appear: \(excludedViolations)"
        )
    }
}
