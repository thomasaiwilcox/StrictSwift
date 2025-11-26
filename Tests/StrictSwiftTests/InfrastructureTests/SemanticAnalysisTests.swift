import XCTest
@testable import StrictSwiftCore

/// Tests for the semantic analysis infrastructure
final class SemanticAnalysisTests: XCTestCase {
    
    // MARK: - SemanticMode Tests
    
    func testSemanticModeRawValues() {
        XCTAssertEqual(SemanticMode.off.rawValue, "off")
        XCTAssertEqual(SemanticMode.hybrid.rawValue, "hybrid")
        XCTAssertEqual(SemanticMode.full.rawValue, "full")
        XCTAssertEqual(SemanticMode.auto.rawValue, "auto")
    }
    
    func testSemanticModeFromRawValue() {
        XCTAssertEqual(SemanticMode(rawValue: "off"), .off)
        XCTAssertEqual(SemanticMode(rawValue: "hybrid"), .hybrid)
        XCTAssertEqual(SemanticMode(rawValue: "full"), .full)
        XCTAssertEqual(SemanticMode(rawValue: "auto"), .auto)
        XCTAssertNil(SemanticMode(rawValue: "invalid"))
    }
    
    func testSemanticModeDisplayNames() {
        XCTAssertEqual(SemanticMode.off.displayName, "Off (Syntactic Only)")
        XCTAssertEqual(SemanticMode.hybrid.displayName, "Hybrid")
        XCTAssertEqual(SemanticMode.full.displayName, "Full Semantic")
        XCTAssertEqual(SemanticMode.auto.displayName, "Auto")
    }
    
    func testSemanticModeRequiresSourceKit() {
        XCTAssertFalse(SemanticMode.off.requiresSourceKit)
        XCTAssertFalse(SemanticMode.auto.requiresSourceKit)
        XCTAssertTrue(SemanticMode.hybrid.requiresSourceKit)
        XCTAssertTrue(SemanticMode.full.requiresSourceKit)
    }
    
    func testSemanticModeRequiresBuildArtifacts() {
        XCTAssertFalse(SemanticMode.off.requiresBuildArtifacts)
        XCTAssertFalse(SemanticMode.auto.requiresBuildArtifacts)
        XCTAssertFalse(SemanticMode.hybrid.requiresBuildArtifacts)
        XCTAssertTrue(SemanticMode.full.requiresBuildArtifacts)
    }
    
    // MARK: - SemanticCapabilities Tests
    
    func testSemanticCapabilitiesBestAvailableMode() {
        // Full capabilities -> full mode
        let fullCaps = SemanticCapabilities(
            sourceKitAvailable: true,
            sourceKitPath: "/usr/lib/sourcekitd",
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        XCTAssertEqual(fullCaps.bestAvailableMode, .full)
        
        // SourceKit only -> hybrid mode
        let basicCaps = SemanticCapabilities(
            sourceKitAvailable: true,
            sourceKitPath: "/usr/lib/sourcekitd",
            buildArtifactsExist: false,
            isSwiftPackage: true
        )
        XCTAssertEqual(basicCaps.bestAvailableMode, .hybrid)
        
        // No capabilities -> off mode
        let noneCaps = SemanticCapabilities(
            sourceKitAvailable: false,
            buildArtifactsExist: false,
            isSwiftPackage: false
        )
        XCTAssertEqual(noneCaps.bestAvailableMode, .off)
    }
    
    func testSemanticCapabilitiesDegradationFull() {
        // Full capabilities - no degradation for any mode
        let fullCaps = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        
        let (fullMode, fullReason) = fullCaps.degrade(.full)
        XCTAssertEqual(fullMode, .full)
        XCTAssertNil(fullReason)
        
        let (hybridMode, hybridReason) = fullCaps.degrade(.hybrid)
        XCTAssertEqual(hybridMode, .hybrid)
        XCTAssertNil(hybridReason)
    }
    
    func testSemanticCapabilitiesDegradationBasic() {
        // Basic capabilities - full degrades to hybrid
        let basicCaps = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: false,
            isSwiftPackage: true
        )
        
        let (degradedFull, degradedReason) = basicCaps.degrade(.full)
        XCTAssertEqual(degradedFull, .hybrid)
        XCTAssertNotNil(degradedReason)
        XCTAssertTrue(degradedReason?.contains("build") ?? false)
        
        // Auto mode picks best available, doesn't degrade
        let (autoMode, autoReason) = basicCaps.degrade(.auto)
        XCTAssertEqual(autoMode, .hybrid) // Best available
        XCTAssertNil(autoReason)
    }
    
    func testSemanticCapabilitiesDegradationNone() {
        // No capabilities - everything degrades to off
        let noneCaps = SemanticCapabilities(
            sourceKitAvailable: false,
            buildArtifactsExist: false,
            isSwiftPackage: false
        )
        
        let (noSourceKitFull, noSourceKitReason) = noneCaps.degrade(.full)
        XCTAssertEqual(noSourceKitFull, .off)
        XCTAssertNotNil(noSourceKitReason)
        
        let (noSourceKitHybrid, noSourceKitHybridReason) = noneCaps.degrade(.hybrid)
        XCTAssertEqual(noSourceKitHybrid, .off)
        XCTAssertNotNil(noSourceKitHybridReason)
        
        // Off mode never degrades
        let (offMode, offReason) = noneCaps.degrade(.off)
        XCTAssertEqual(offMode, .off)
        XCTAssertNil(offReason)
    }
    
    // MARK: - SemanticModeResolver Tests
    
    func testResolverCLIPrecedence() {
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        let resolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        // CLI mode should take precedence over YAML
        let yamlConfig = SemanticModeYAMLConfig(
            projectMode: .off,
            projectStrict: false,
            perRuleModes: [:],
            perRuleStrict: [:]
        )
        
        let resolved = resolver.resolve(cliMode: .full, cliStrict: true, yamlConfig: yamlConfig)
        XCTAssertEqual(resolved.effectiveMode, .full)
        XCTAssertEqual(resolved.modeSource, .cli)
        XCTAssertTrue(resolved.isStrict)
    }
    
    func testResolverYAMLFallback() {
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        let resolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        // No CLI mode, should fall back to YAML
        let yamlConfig = SemanticModeYAMLConfig(
            projectMode: .hybrid,
            projectStrict: true,
            perRuleModes: [:],
            perRuleStrict: [:]
        )
        
        let resolved = resolver.resolve(cliMode: nil, cliStrict: false, yamlConfig: yamlConfig)
        XCTAssertEqual(resolved.effectiveMode, .hybrid)
        XCTAssertEqual(resolved.modeSource, .projectYAML)
        XCTAssertTrue(resolved.isStrict)
    }
    
    func testResolverAutoDetection() {
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        let resolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        // No CLI, no YAML - should auto-detect
        let resolved = resolver.resolve(cliMode: nil, cliStrict: false, yamlConfig: nil)
        
        // Auto with full capabilities should resolve to full
        XCTAssertEqual(resolved.effectiveMode, .full)
        XCTAssertEqual(resolved.modeSource, .autoDetected)
        XCTAssertFalse(resolved.isStrict)
    }
    
    func testResolverDegradation() {
        // Limited capabilities - no build artifacts
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: false,
            isSwiftPackage: true
        )
        let resolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        // Request full mode but capabilities are limited
        let resolved = resolver.resolve(cliMode: .full, cliStrict: false, yamlConfig: nil)
        
        // Should degrade to hybrid
        XCTAssertEqual(resolved.effectiveMode, .hybrid)
        XCTAssertNotNil(resolved.degradation)
        XCTAssertEqual(resolved.degradation?.requestedMode, .full)
        XCTAssertEqual(resolved.degradation?.actualMode, .hybrid)
    }
    
    func testResolverNoSourceKitDegradation() {
        // No SourceKit available
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: false,
            buildArtifactsExist: false,
            isSwiftPackage: true
        )
        let resolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        // Request hybrid mode
        let resolved = resolver.resolve(cliMode: .hybrid, cliStrict: false, yamlConfig: nil)
        
        // Should degrade to off
        XCTAssertEqual(resolved.effectiveMode, .off)
        XCTAssertNotNil(resolved.degradation)
        XCTAssertEqual(resolved.degradation?.requestedMode, .hybrid)
        XCTAssertEqual(resolved.degradation?.actualMode, .off)
    }
    
    func testResolverPerRuleModes() {
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        let resolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        let yamlConfig = SemanticModeYAMLConfig(
            projectMode: .hybrid,
            projectStrict: false,
            perRuleModes: ["dead_code": .full, "unused_import": .off],
            perRuleStrict: ["dead_code": true]
        )
        
        // Resolve for dead_code rule - should get per-rule override
        let resolved = resolver.resolve(cliMode: nil, cliStrict: false, ruleName: "dead_code", yamlConfig: yamlConfig)
        
        // Per-rule mode should override project mode
        XCTAssertEqual(resolved.effectiveMode, .full)
        XCTAssertEqual(resolved.modeSource, .perRuleYAML)
    }
    
    // MARK: - SemanticModeYAMLConfig Tests
    
    func testYAMLConfigFromConfiguration() {
        let config = Configuration(
            profile: .criticalCore,
            semanticMode: .hybrid,
            semanticStrict: true,
            perRuleSemanticModes: ["dead_code": .full],
            perRuleSemanticStrict: ["dead_code": true]
        )
        
        let yamlConfig = SemanticModeYAMLConfig.from(config)
        
        XCTAssertNotNil(yamlConfig)
        XCTAssertEqual(yamlConfig?.projectMode, .hybrid)
        XCTAssertEqual(yamlConfig?.projectStrict, true)
        XCTAssertEqual(yamlConfig?.perRuleModes["dead_code"], SemanticMode.full)
        XCTAssertEqual(yamlConfig?.perRuleStrict["dead_code"], true)
    }
    
    func testYAMLConfigFromDefaultConfiguration() {
        // Default configuration has no semantic settings
        let config = Configuration()
        let yamlConfig = SemanticModeYAMLConfig.from(config)
        
        // Returns a config but with nil values since no semantic config is set
        if let yaml = yamlConfig {
            XCTAssertNil(yaml.projectMode)
            XCTAssertNil(yaml.projectStrict)
            XCTAssertTrue(yaml.perRuleModes.isEmpty)
            XCTAssertTrue(yaml.perRuleStrict.isEmpty)
        }
    }
    
    // MARK: - SemanticCapabilityDetector Tests
    
    func testCapabilityDetectorBasicDetection() {
        // Use temp directory for testing
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let detector = SemanticCapabilityDetector(projectRoot: tempDir)
        
        // Detection should not crash
        let capabilities = detector.detect()
        
        // Temp dir is not a Swift package
        XCTAssertFalse(capabilities.isSwiftPackage)
        XCTAssertFalse(capabilities.buildArtifactsExist)
    }
    
    // MARK: - Integration Tests
    
    func testEndToEndFlow() {
        // Simulate a typical configuration flow
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: false, // No build artifacts
            isSwiftPackage: true
        )
        let resolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        // User sets auto mode
        let resolved = resolver.resolve(cliMode: .auto, cliStrict: false, yamlConfig: nil)
        
        // Auto should resolve to best available (hybrid since no build artifacts)
        XCTAssertEqual(resolved.effectiveMode, .hybrid)
        XCTAssertNil(resolved.degradation) // Auto doesn't degrade, it picks best available
    }
    
    func testConfigurationSourcePriorities() {
        // Verify ConfigurationSource priorities are correct
        XCTAssertGreaterThan(
            SemanticModeResolver.ConfigurationSource.cli.priority,
            SemanticModeResolver.ConfigurationSource.environment.priority
        )
        XCTAssertGreaterThan(
            SemanticModeResolver.ConfigurationSource.environment.priority,
            SemanticModeResolver.ConfigurationSource.vsCodeSettings.priority
        )
        XCTAssertGreaterThan(
            SemanticModeResolver.ConfigurationSource.vsCodeSettings.priority,
            SemanticModeResolver.ConfigurationSource.perRuleYAML.priority
        )
        XCTAssertGreaterThan(
            SemanticModeResolver.ConfigurationSource.perRuleYAML.priority,
            SemanticModeResolver.ConfigurationSource.projectYAML.priority
        )
        XCTAssertGreaterThan(
            SemanticModeResolver.ConfigurationSource.projectYAML.priority,
            SemanticModeResolver.ConfigurationSource.autoDetected.priority
        )
    }
}
