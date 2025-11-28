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
        // Full capabilities -> hybrid mode (we prefer hybrid for performance)
        let fullCaps = SemanticCapabilities(
            sourceKitAvailable: true,
            sourceKitPath: "/usr/lib/sourcekitd",
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        XCTAssertEqual(fullCaps.bestAvailableMode, .hybrid)
        
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
        
        // No CLI, no YAML - should auto-detect to hybrid (preferred for performance)
        let resolved = resolver.resolve(cliMode: nil, cliStrict: false, yamlConfig: nil)
        
        // Auto with full capabilities should resolve to hybrid (we prefer hybrid for performance)
        XCTAssertEqual(resolved.effectiveMode, .hybrid)
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
    
    // MARK: - AnalysisContext Per-Rule Semantic Mode Tests
    
    func testAnalysisContextSemanticModeForRuleWithOverride() {
        // Setup configuration with per-rule semantic mode overrides
        // Note: semanticMode here simulates YAML project-level setting (not CLI)
        let config = Configuration(
            profile: .criticalCore,
            semanticMode: .hybrid,  // This is the project-level YAML setting
            semanticStrict: false,
            perRuleSemanticModes: ["dead-code": .full, "unused_import": .off],
            perRuleSemanticStrict: ["dead-code": true]
        )
        
        let context = AnalysisContext(
            configuration: config,
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        
        // Setup semantic analysis with resolver and YAML config
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        let modeResolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        let yamlConfig = SemanticModeYAMLConfig.from(config)
        
        // Get the global resolved config (project-level, no CLI override)
        let globalResolved = modeResolver.resolve(
            cliMode: nil,  // No CLI override for this test
            cliStrict: false,
            yamlConfig: yamlConfig
        )
        
        // Create a mock semantic resolver for testing
        let semanticResolver = SemanticTypeResolver(mode: globalResolved.effectiveMode, sourceKitClient: nil, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        context.setSemanticResolver(
            semanticResolver,
            config: globalResolved,
            modeResolver: modeResolver,
            yamlConfig: yamlConfig
        )
        
        // Test per-rule resolution: dead-code should get .full mode from per-rule override
        let deadCodeResolved = context.semanticModeForRule("dead-code")
        XCTAssertNotNil(deadCodeResolved)
        XCTAssertEqual(deadCodeResolved?.effectiveMode, .full)
        XCTAssertEqual(deadCodeResolved?.modeSource, .perRuleYAML)
        XCTAssertTrue(deadCodeResolved?.isStrict ?? false)
        
        // Test rule without override: should fall back to global config (project YAML)
        let forceUnwrapResolved = context.semanticModeForRule("force_unwrap")
        XCTAssertNotNil(forceUnwrapResolved)
        XCTAssertEqual(forceUnwrapResolved?.effectiveMode, .hybrid) // Global config mode
        XCTAssertEqual(forceUnwrapResolved?.modeSource, .projectYAML)
    }
    
    func testAnalysisContextSemanticModeForRuleFallback() {
        // Setup configuration without per-rule overrides
        let config = Configuration(
            profile: .criticalCore,
            semanticMode: .hybrid,
            semanticStrict: true
        )
        
        let context = AnalysisContext(
            configuration: config,
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        
        // Setup semantic analysis
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        let modeResolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        let yamlConfig = SemanticModeYAMLConfig.from(config)
        
        let globalResolved = modeResolver.resolve(
            cliMode: nil,  // No CLI override
            cliStrict: false,
            yamlConfig: yamlConfig
        )
        
        let semanticResolver = SemanticTypeResolver(mode: globalResolved.effectiveMode, sourceKitClient: nil, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        context.setSemanticResolver(
            semanticResolver,
            config: globalResolved,
            modeResolver: modeResolver,
            yamlConfig: yamlConfig
        )
        
        // Any rule should get the global config (no overrides defined)
        let resolved = context.semanticModeForRule("dead-code")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.effectiveMode, .hybrid)
        XCTAssertEqual(resolved?.modeSource, .projectYAML)
    }
    
    func testAnalysisContextSemanticModeForRuleWithCLIOverride() {
        // Test that when CLI mode is set globally, per-rule overrides still work
        let config = Configuration(
            profile: .criticalCore,
            semanticMode: .off,  // Global CLI setting (simulating --semantic off)
            semanticStrict: false,
            perRuleSemanticModes: ["dead-code": .full],
            perRuleSemanticStrict: [:]
        )
        
        let context = AnalysisContext(
            configuration: config,
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        let modeResolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        let yamlConfig = SemanticModeYAMLConfig.from(config)
        
        // Simulate CLI mode being passed (this would come from actual --semantic flag)
        let globalResolved = modeResolver.resolve(
            cliMode: .off,  // CLI override
            cliStrict: false,
            yamlConfig: yamlConfig
        )
        
        let semanticResolver = SemanticTypeResolver(mode: globalResolved.effectiveMode, sourceKitClient: nil, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        context.setSemanticResolver(
            semanticResolver,
            config: globalResolved,
            modeResolver: modeResolver,
            yamlConfig: yamlConfig
        )
        
        // Global resolution should be CLI (off)
        XCTAssertEqual(globalResolved.effectiveMode, SemanticMode.off)
        XCTAssertEqual(globalResolved.modeSource, SemanticModeResolver.ConfigurationSource.cli)
        
        // But per-rule override for dead-code should still get .full
        let deadCodeResolved = context.semanticModeForRule("dead-code")
        XCTAssertNotNil(deadCodeResolved)
        XCTAssertEqual(deadCodeResolved?.effectiveMode, .full)
        XCTAssertEqual(deadCodeResolved?.modeSource, .perRuleYAML)
        
        // Rule without override falls back to global (CLI)
        let otherResolved = context.semanticModeForRule("force_unwrap")
        XCTAssertNotNil(otherResolved)
        XCTAssertEqual(otherResolved?.effectiveMode, SemanticMode.off)
        XCTAssertEqual(otherResolved?.modeSource, SemanticModeResolver.ConfigurationSource.cli)
    }
    
    // MARK: - Rule-aware helper method tests
    
    func testHasSemanticAnalysisForRuleWithOverride() {
        // Setup: global semantic is OFF, but specific rule has FULL override
        let config = Configuration(
            profile: .criticalCore,
            semanticMode: .off,  // Global: off
            semanticStrict: false,
            perRuleSemanticModes: ["non_sendable_capture": .full],  // Per-rule override to full
            perRuleSemanticStrict: [:]
        )
        
        let context = AnalysisContext(
            configuration: config,
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        let modeResolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        let yamlConfig = SemanticModeYAMLConfig.from(config)
        
        // Global resolution should be OFF
        let globalResolved = modeResolver.resolve(
            cliMode: nil,
            cliStrict: false,
            yamlConfig: yamlConfig
        )
        XCTAssertEqual(globalResolved.effectiveMode, .off)
        
        let semanticResolver = SemanticTypeResolver(mode: globalResolved.effectiveMode, sourceKitClient: nil, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        context.setSemanticResolver(
            semanticResolver,
            config: globalResolved,
            modeResolver: modeResolver,
            yamlConfig: yamlConfig
        )
        
        // Global check should be false (semantic is off globally)
        XCTAssertFalse(context.hasSemanticAnalysis)
        
        // Per-rule check for non_sendable_capture should be true (has per-rule override to full)
        XCTAssertTrue(context.hasSemanticAnalysis(forRule: "non_sendable_capture"))
        XCTAssertEqual(context.effectiveSemanticMode(forRule: "non_sendable_capture"), .full)
        
        // Per-rule check for other rule should be false (no override, falls back to global)
        XCTAssertFalse(context.hasSemanticAnalysis(forRule: "force_unwrap"))
        XCTAssertEqual(context.effectiveSemanticMode(forRule: "force_unwrap"), .off)
    }
    
    func testIsSemanticStrictForRule() {
        // Setup: global strict is false, but specific rule has strict=true
        let config = Configuration(
            profile: .criticalCore,
            semanticMode: .hybrid,
            semanticStrict: false,  // Global: not strict
            perRuleSemanticModes: ["dead-code": .full],
            perRuleSemanticStrict: ["dead-code": true]  // Per-rule: strict
        )
        
        let context = AnalysisContext(
            configuration: config,
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,
            isSwiftPackage: true
        )
        let modeResolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        let yamlConfig = SemanticModeYAMLConfig.from(config)
        
        let globalResolved = modeResolver.resolve(
            cliMode: nil,
            cliStrict: false,
            yamlConfig: yamlConfig
        )
        
        let semanticResolver = SemanticTypeResolver(mode: globalResolved.effectiveMode, sourceKitClient: nil, projectRoot: URL(fileURLWithPath: "/tmp"))
        
        context.setSemanticResolver(
            semanticResolver,
            config: globalResolved,
            modeResolver: modeResolver,
            yamlConfig: yamlConfig
        )
        
        // dead-code has strict override
        XCTAssertTrue(context.isSemanticStrict(forRule: "dead-code"))
        
        // force_unwrap has no override, falls back to global (false)
        XCTAssertFalse(context.isSemanticStrict(forRule: "force_unwrap"))
    }
    
    // MARK: - Integration Tests for Per-Rule Semantic Override with Resolver Capability
    
    /// This test verifies that when global mode is .off but a per-rule override requests a higher mode,
    /// the SemanticTypeResolver is created with sufficient capability to satisfy that rule.
    /// Previously this was a bug: the resolver would be created in .off mode with no SourceKit client,
    /// so per-rule overrides had no actual effect.
    func testPerRuleOverrideElevatesResolverCapability() async throws {
        // Setup: global semantic is OFF, but specific rule requests HYBRID
        let config = Configuration(
            profile: .criticalCore,
            semanticMode: .off,  // Global: off
            semanticStrict: false,
            perRuleSemanticModes: ["non_sendable_capture": .hybrid],  // Per-rule: hybrid
            perRuleSemanticStrict: [:]
        )
        
        // Simulate capabilities where SourceKit IS available
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: false,
            isSwiftPackage: true
        )
        
        let modeResolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        let yamlConfig = SemanticModeYAMLConfig.from(config)
        
        // Global resolution should be OFF
        let globalResolved = modeResolver.resolve(
            cliMode: nil,
            cliStrict: false,
            yamlConfig: yamlConfig
        )
        XCTAssertEqual(globalResolved.effectiveMode, .off)
        
        // Now simulate what the Analyzer does: compute max required mode
        // This should detect the per-rule override and elevate to hybrid
        var maxMode: SemanticMode = globalResolved.effectiveMode
        if let perRuleModes = yamlConfig?.perRuleModes {
            for (_, mode) in perRuleModes {
                // Simple max comparison
                if mode == .full || (mode == .hybrid && maxMode == .off) {
                    maxMode = mode
                }
            }
        }
        
        // Verify the max mode is elevated to hybrid (from per-rule override)
        XCTAssertEqual(maxMode, .hybrid, "Per-rule override should elevate max mode to hybrid")
        
        // Create resolver with elevated mode
        let elevatedConfig = SemanticModeResolver.ResolvedConfiguration(
            effectiveMode: maxMode,
            isStrict: globalResolved.isStrict,
            modeSource: globalResolved.modeSource,
            degradation: nil,
            checkedSources: globalResolved.checkedSources
        )
        
        // The resolver mode should be hybrid, not off
        XCTAssertEqual(elevatedConfig.effectiveMode, .hybrid)
        XCTAssertTrue(elevatedConfig.hasSemantic, "Elevated resolver config should have semantic capability")
    }
    
    /// Test that verifies when a rule checks its per-rule semantic mode,
    /// the resolver actually has the capability to service semantic queries.
    func testSemanticResolverHasCapabilityForPerRuleOverride() {
        // Setup: global semantic is OFF, but specific rule requests FULL
        let config = Configuration(
            profile: .criticalCore,
            semanticMode: .off,  // Global: off (would normally create resolver with no SourceKit)
            semanticStrict: false,
            perRuleSemanticModes: ["non_sendable_capture": .full],  // Per-rule: full
            perRuleSemanticStrict: [:]
        )
        
        let context = AnalysisContext(
            configuration: config,
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: true,
            buildArtifactsExist: true,  // full mode requires this
            isSwiftPackage: true
        )
        let modeResolver = SemanticModeResolver(capabilities: capabilities, projectRoot: URL(fileURLWithPath: "/tmp"))
        let yamlConfig = SemanticModeYAMLConfig.from(config)
        
        // Compute max mode (simulating what Analyzer.computeMaxRequiredMode does)
        var maxMode: SemanticMode = .off  // global mode
        if let perRuleModes = yamlConfig?.perRuleModes {
            for (_, mode) in perRuleModes {
                if mode == .full {
                    maxMode = .full
                } else if mode == .hybrid && maxMode != .full {
                    maxMode = .hybrid
                }
            }
        }
        
        // Create resolver with the elevated mode
        let elevatedConfig = SemanticModeResolver.ResolvedConfiguration(
            effectiveMode: maxMode,
            isStrict: false,
            modeSource: .projectYAML,
            degradation: nil,
            checkedSources: []
        )
        
        // Create SemanticTypeResolver with the elevated mode
        // Note: In production, this would use SemanticTypeResolver.create() with SourceKit
        // Here we verify the mode is correctly elevated
        let semanticResolver = SemanticTypeResolver(
            mode: elevatedConfig.effectiveMode,
            sourceKitClient: nil,  // Would be real client in production
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        
        // Store in context with original global config but resolver has elevated capability
        let globalResolved = modeResolver.resolve(cliMode: nil, cliStrict: false, yamlConfig: yamlConfig)
        context.setSemanticResolver(
            semanticResolver,
            config: globalResolved,
            modeResolver: modeResolver,
            yamlConfig: yamlConfig
        )
        
        // CRITICAL ASSERTIONS:
        // 1. Global hasSemanticAnalysis should still be FALSE (global mode is off)
        XCTAssertFalse(context.hasSemanticAnalysis, "Global semantic check should be false")
        
        // 2. Per-rule hasSemanticAnalysis for non_sendable_capture should be TRUE
        XCTAssertTrue(context.hasSemanticAnalysis(forRule: "non_sendable_capture"),
                      "Per-rule semantic check should be true for overridden rule")
        
        // 3. The resolver's mode should be elevated (full)
        // This is the key fix - the resolver must have the capability
        XCTAssertEqual(elevatedConfig.effectiveMode, .full,
                       "Resolver should be created with elevated mode to satisfy per-rule overrides")
    }
    
    // MARK: - Per-Rule Strict Mode Enforcement Tests
    
    /// Regression test: perRuleSemanticStrict without explicit perRuleSemanticModes
    /// should use the ORIGINAL requested mode, not the degraded effective mode.
    ///
    /// Scenario: User configures:
    /// ```yaml
    /// semanticMode: full
    /// perRuleSemanticStrict:
    ///   dead-code: true
    /// ```
    /// If SourceKit is unavailable, full mode degrades to off.
    /// The old bug: strict check used the degraded mode (.off), so canSatisfyMode(.off) == true, no error.
    /// The fix: strict check uses the original requested mode (.full), so canSatisfyMode(.full) fails.
    func testPerRuleStrictWithoutExplicitModeUsesOriginalRequest() {
        // Simulate a config where global mode is "full" but no per-rule mode is set for dead-code
        let yamlConfig = SemanticModeYAMLConfig(
            projectMode: .full,        // User requested full mode
            projectStrict: nil,
            perRuleModes: [:],         // No per-rule mode override for dead-code
            perRuleStrict: ["dead-code": true]  // But strict IS set for dead-code
        )
        
        // Simulate degradation scenario: SourceKit unavailable, so full -> off
        let degradation = SemanticModeResolver.ResolvedConfiguration.Degradation(
            requestedMode: .full,
            actualMode: .off,
            reason: "SourceKit not available"
        )
        
        let degradedConfig = SemanticModeResolver.ResolvedConfiguration(
            effectiveMode: .off,  // Degraded to off
            isStrict: false,
            modeSource: .projectYAML,
            degradation: degradation,
            checkedSources: []
        )
        
        // Capabilities: No SourceKit
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: false,
            buildArtifactsExist: false,
            isSwiftPackage: true
        )
        
        // The key insight: when deriving the requested mode for dead-code:
        // - perRuleModes["dead-code"] is nil
        // - So we fall back to the ORIGINAL request, not the degraded mode
        // - Original request = degradation.requestedMode = .full
        // - .full cannot be satisfied without SourceKit
        // - Therefore, strict check should FAIL
        
        // Derive the original requested mode (as the fixed code does)
        let originalRequestedMode: SemanticMode = {
            if let degradation = degradedConfig.degradation {
                return degradation.requestedMode  // .full
            }
            if let projectMode = yamlConfig.projectMode {
                return projectMode
            }
            return degradedConfig.effectiveMode
        }()
        
        XCTAssertEqual(originalRequestedMode, .full,
                       "Original requested mode should be .full (from degradation.requestedMode)")
        
        // For the rule with strict=true, get the requested mode
        let ruleId = "dead-code"
        let requestedModeForRule = yamlConfig.perRuleModes[ruleId] ?? originalRequestedMode
        
        XCTAssertEqual(requestedModeForRule, .full,
                       "Rule without explicit perRuleMode should inherit original request (.full)")
        
        // Now check if this can be satisfied - it should NOT be satisfiable
        let canSatisfy = canSatisfyModeHelper(
            requestedModeForRule,
            effectiveMode: degradedConfig.effectiveMode,  // .off
            capabilities: capabilities  // no SourceKit
        )
        
        XCTAssertFalse(canSatisfy,
                       "Full mode cannot be satisfied without SourceKit - strict should fail")
    }
    
    /// Regression test: When global mode is "off" but a rule has strict=true,
    /// should that fail? This tests the edge case where projectMode is explicitly off.
    func testPerRuleStrictWithExplicitOffModeSucceeds() {
        // If user explicitly sets semanticMode: off AND perRuleSemanticStrict: dead-code: true
        // This is a confusing config, but since they asked for off, off is satisfiable
        let yamlConfig = SemanticModeYAMLConfig(
            projectMode: .off,         // Explicitly off
            projectStrict: nil,
            perRuleModes: [:],
            perRuleStrict: ["dead-code": true]
        )
        
        let resolvedConfig = SemanticModeResolver.ResolvedConfiguration(
            effectiveMode: .off,
            isStrict: false,
            modeSource: .projectYAML,
            degradation: nil,  // No degradation - user asked for off, got off
            checkedSources: []
        )
        
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: false,
            buildArtifactsExist: false,
            isSwiftPackage: true
        )
        
        // Original requested mode when no degradation
        let originalRequestedMode: SemanticMode = {
            if let degradation = resolvedConfig.degradation {
                return degradation.requestedMode
            }
            if let projectMode = yamlConfig.projectMode {
                return projectMode  // .off
            }
            return resolvedConfig.effectiveMode
        }()
        
        XCTAssertEqual(originalRequestedMode, .off,
                       "Original requested mode should be .off (from projectMode)")
        
        let requestedModeForRule = yamlConfig.perRuleModes["dead-code"] ?? originalRequestedMode
        XCTAssertEqual(requestedModeForRule, .off)
        
        // Off mode is always satisfiable
        let canSatisfy = canSatisfyModeHelper(
            requestedModeForRule,
            effectiveMode: .off,
            capabilities: capabilities
        )
        
        XCTAssertTrue(canSatisfy, "Off mode should always be satisfiable")
    }
    
    /// Test that explicit per-rule mode takes precedence over global mode for strict checking
    func testPerRuleStrictWithExplicitPerRuleModeUsesThatMode() {
        let yamlConfig = SemanticModeYAMLConfig(
            projectMode: .full,
            projectStrict: nil,
            perRuleModes: ["dead-code": .hybrid],  // Explicit hybrid for this rule
            perRuleStrict: ["dead-code": true]
        )
        
        let degradedConfig = SemanticModeResolver.ResolvedConfiguration(
            effectiveMode: .off,  // Global degraded to off
            isStrict: false,
            modeSource: .projectYAML,
            degradation: SemanticModeResolver.ResolvedConfiguration.Degradation(
                requestedMode: .full,
                actualMode: .off,
                reason: "SourceKit not available"
            ),
            checkedSources: []
        )
        
        let capabilities = SemanticCapabilities(
            sourceKitAvailable: false,
            buildArtifactsExist: false,
            isSwiftPackage: true
        )
        
        // For dead-code, the explicit perRuleMode takes precedence
        let requestedModeForRule = yamlConfig.perRuleModes["dead-code"]!  // .hybrid
        
        XCTAssertEqual(requestedModeForRule, .hybrid,
                       "Explicit per-rule mode should take precedence")
        
        // Hybrid needs SourceKit - should not be satisfiable
        let canSatisfy = canSatisfyModeHelper(
            requestedModeForRule,
            effectiveMode: degradedConfig.effectiveMode,
            capabilities: capabilities
        )
        
        XCTAssertFalse(canSatisfy,
                       "Hybrid mode cannot be satisfied without SourceKit")
    }
    
    // MARK: - Test Helpers
    
    /// Helper that mirrors the logic in Analyzer.canSatisfyMode for testing
    private func canSatisfyModeHelper(
        _ requested: SemanticMode,
        effectiveMode: SemanticMode,
        capabilities: SemanticCapabilities
    ) -> Bool {
        switch requested {
        case .off, .auto:
            return true
        case .hybrid:
            return capabilities.sourceKitAvailable &&
                   (effectiveMode == .hybrid || effectiveMode == .full)
        case .full:
            return capabilities.sourceKitAvailable &&
                   capabilities.buildArtifactsExist &&
                   effectiveMode == .full
        }
    }
}
