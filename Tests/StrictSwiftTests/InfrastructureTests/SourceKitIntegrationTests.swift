import XCTest
@testable import StrictSwiftCore

/// Integration tests for SourceKit semantic analysis
/// These tests verify that SourceKit integration is working end-to-end
final class SourceKitIntegrationTests: XCTestCase {
    
    // MARK: - Target Detection
    
    /// Test that target triple is correctly detected from the system
    func testTargetTripleDetection() async throws {
        #if !os(macOS)
        throw XCTSkip("SourceKit tests only run on macOS")
        #endif
        
        // Create a temp file to analyze
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceKitIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("Test.swift")
        try "class TestClass {}".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Detect capabilities
        let detector = SemanticCapabilityDetector(projectRoot: tempDir)
        let capabilities = detector.detect()
        
        // Check that SourceKit is available on macOS
        XCTAssertTrue(capabilities.sourceKitAvailable, "SourceKit should be available on macOS")
        
        // Create client - this will use the new target detection
        let client = try SourceKitClient.create(for: tempDir, capabilities: capabilities)
        XCTAssertNotNil(client, "SourceKitClient should be created successfully")
    }
    
    // MARK: - Verbose Logging
    
    /// Test that verbose mode enables debug logging
    func testVerboseLogging() {
        // Save original level
        let originalLevel = StrictSwiftLogger.minLevel
        defer { StrictSwiftLogger.minLevel = originalLevel }
        
        // Enable verbose
        StrictSwiftLogger.enableVerbose()
        XCTAssertEqual(StrictSwiftLogger.minLevel, .debug, "Verbose mode should set level to debug")
        
        // Test explicit level setting
        StrictSwiftLogger.setMinLevel(.warning)
        XCTAssertEqual(StrictSwiftLogger.minLevel, .warning, "Level should be settable")
    }
    
    // MARK: - Semantic Mode Resolution
    
    /// Test that semantic mode is correctly resolved and available in context
    func testSemanticModeInContext() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SemanticMode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create test file
        let testFile = tempDir.appendingPathComponent("Test.swift")
        try "class Foo {}".write(to: testFile, atomically: true, encoding: .utf8)
        
        // Create context
        let config = Configuration.load(from: nil, profile: .criticalCore)
        let context = AnalysisContext(configuration: config, projectRoot: tempDir)
        
        // Initially no semantic config
        XCTAssertNil(context.semanticModeResolved)
        
        // Set up semantic resolver
        let resolvedConfig = SemanticModeResolver.ResolvedConfiguration(
            effectiveMode: .hybrid,
            isStrict: false,
            modeSource: .autoDetected,
            degradation: nil,
            checkedSources: []
        )
        
        let resolver = SemanticTypeResolver(
            mode: .hybrid,
            sourceKitClient: nil,
            projectRoot: tempDir
        )
        
        context.setSemanticResolver(resolver, config: resolvedConfig)
        
        // Now semantic config should be available
        XCTAssertNotNil(context.semanticModeResolved)
        XCTAssertEqual(context.semanticModeResolved?.effectiveMode, .hybrid)
        XCTAssertEqual(context.semanticModeResolved?.modeSource, .autoDetected)
    }
    
    // MARK: - Analysis Metadata
    
    /// Test that AnalysisMetadata correctly captures mode info
    func testAnalysisMetadata() {
        let resolvedConfig = SemanticModeResolver.ResolvedConfiguration(
            effectiveMode: .full,
            isStrict: true,
            modeSource: .cli,
            degradation: SemanticModeResolver.ResolvedConfiguration.Degradation(
                requestedMode: .full,
                actualMode: .hybrid,
                reason: "Build index not available"
            ),
            checkedSources: []
        )
        
        let metadata = AnalysisMetadata(from: resolvedConfig)
        
        XCTAssertEqual(metadata.semanticMode, .full)
        XCTAssertEqual(metadata.modeSource, "CLI")
        XCTAssertEqual(metadata.degradedFrom, .full)
        XCTAssertEqual(metadata.degradationReason, "Build index not available")
    }
    
    // MARK: - Reporter Mode Display
    
    /// Test that HumanReporter correctly formats mode header
    func testHumanReporterModeHeader() throws {
        let reporter = HumanReporter()
        
        // Test with metadata
        let metadata = AnalysisMetadata(
            semanticMode: .hybrid,
            modeSource: "Auto-detected"
        )
        
        let report = try reporter.generateReport([], metadata: metadata)
        
        XCTAssertTrue(report.contains("🔬"), "Hybrid mode should show microscope icon")
        XCTAssertTrue(report.contains("hybrid"), "Report should mention hybrid mode")
        XCTAssertTrue(report.contains("Auto-detected"), "Report should show mode source")
    }
    
    /// Test that JSONReporter includes mode in output
    func testJSONReporterModeOutput() throws {
        let reporter = JSONReporter(pretty: true)
        
        let metadata = AnalysisMetadata(
            semanticMode: .full,
            modeSource: "CLI",
            degradedFrom: .full,
            degradationReason: "Test reason"
        )
        
        let report = try reporter.generateReport([], metadata: metadata)
        
        XCTAssertTrue(report.contains("\"mode\" : \"full\""), "JSON should include mode")
        XCTAssertTrue(report.contains("\"source\" : \"CLI\""), "JSON should include source")
        XCTAssertTrue(report.contains("\"degradedFrom\""), "JSON should include degradation")
    }
    
    // MARK: - End-to-End SourceKit Query
    
    /// Test full SourceKit cursor info query with correct target
    func testSourceKitCursorInfoQuery() async throws {
        #if !os(macOS)
        throw XCTSkip("SourceKit tests only run on macOS")
        #endif
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorInfo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("Test.swift")
        let source = """
        class MyClass {
            var name: String = ""
        }
        """
        try source.write(to: testFile, atomically: true, encoding: .utf8)
        
        // Initialize SourceKit service
        let service = SourceKitDService()
        try await service.initialize()
        
        // Get SDK path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let sdkPath = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Get target from swift (same method SourceKitClient uses)
        let targetProcess = Process()
        targetProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        targetProcess.arguments = ["swift", "-print-target-info"]
        let targetPipe = Pipe()
        targetProcess.standardOutput = targetPipe
        try targetProcess.run()
        targetProcess.waitUntilExit()
        
        var target = "arm64-apple-macosx14.0" // fallback
        if let output = String(data: targetPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
           let jsonData = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let targetInfo = json["target"] as? [String: Any],
           let triple = targetInfo["triple"] as? String {
            target = triple
        }
        
        let compilerArgs = [
            testFile.path,
            "-sdk", sdkPath,
            "-target", target
        ]
        
        // Query cursor info at "MyClass" (offset 6)
        let result = try await service.cursorInfo(
            at: 6,
            in: testFile.path,
            sourceText: source,
            compilerArgs: compilerArgs
        )
        
        // Verify we got meaningful results
        XCTAssertEqual(result.name, "MyClass", "Should get class name from SourceKit")
        XCTAssertEqual(result.kind, "source.lang.swift.decl.class", "Should identify as class declaration")
        XCTAssertNotNil(result.usr, "Should have a USR")
    }
}
