import XCTest
@testable import StrictSwiftCore

/// Tests for graph-enhanced rules
final class GraphEnhancedRulesTests: XCTestCase {
    
    // MARK: - GraphEnhancedGodClassRule Tests
    
    func testGraphEnhancedGodClassRuleMetadata() {
        let rule = GraphEnhancedGodClassRule()
        XCTAssertEqual(rule.id, "god_class_enhanced")
        XCTAssertEqual(rule.category, .architecture)
        XCTAssertFalse(rule.enabledByDefault) // Opt-in rule
    }
    
    func testGraphEnhancedGodClassRuleDisabledWithoutConfig() async throws {
        let rule = GraphEnhancedGodClassRule()
        
        let source = """
        class MassiveClass {
            var prop1: String = ""
            func method1() {}
        }
        """
        
        let sourceFile = SourceFile(
            url: URL(fileURLWithPath: "/test/MassiveClass.swift"),
            source: source,
            moduleName: "TestModule"
        )
        
        // Without useEnhancedRules, should return empty
        let config = Configuration() // useEnhancedRules defaults to false
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/test"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        XCTAssertTrue(violations.isEmpty, "Should not report violations when useEnhancedRules is false")
    }
    
    func testGraphEnhancedGodClassRuleEnabledWithConfig() async throws {
        let rule = GraphEnhancedGodClassRule()
        
        let source = """
        class MassiveClass {
            var prop1: String = ""
            var prop2: String = ""
            var prop3: String = ""
            var prop4: String = ""
            var prop5: String = ""
            var prop6: String = ""
            var prop7: String = ""
            var prop8: String = ""
            var prop9: String = ""
            var prop10: String = ""
            var prop11: String = ""
            
            func method1() {}
            func method2() {}
            func method3() {}
            func method4() {}
            func method5() {}
            func method6() {}
            func method7() {}
            func method8() {}
            func method9() {}
            func method10() {}
            func method11() {}
            func method12() {}
            func method13() {}
            func method14() {}
            func method15() {}
            func method16() {}
        }
        """
        
        let sourceFile = SourceFile(
            url: URL(fileURLWithPath: "/test/MassiveClass.swift"),
            source: source,
            moduleName: "TestModule"
        )
        
        // With useEnhancedRules = true
        let config = Configuration(useEnhancedRules: true)
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/test"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        // Should detect issues when enabled (methods + properties > thresholds)
        XCTAssertFalse(violations.isEmpty, "Should report violations when useEnhancedRules is true")
    }
    
    // MARK: - CouplingMetricsRule Tests
    
    func testCouplingMetricsRuleMetadata() {
        let rule = CouplingMetricsRule()
        XCTAssertEqual(rule.id, "coupling_metrics")
        XCTAssertEqual(rule.category, .architecture)
        XCTAssertFalse(rule.enabledByDefault)
    }
    
    func testCouplingMetricsRuleDisabledWithoutConfig() async throws {
        let rule = CouplingMetricsRule()
        
        let source = """
        class TestClass {
            func doSomething() {}
        }
        """
        
        let sourceFile = SourceFile(
            url: URL(fileURLWithPath: "/test/TestClass.swift"),
            source: source,
            moduleName: "TestModule"
        )
        
        let config = Configuration() // useEnhancedRules defaults to false
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/test"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        XCTAssertTrue(violations.isEmpty)
    }
    
    // MARK: - CircularDependencyGraphRule Tests
    
    func testCircularDependencyGraphRuleMetadata() {
        let rule = CircularDependencyGraphRule()
        XCTAssertEqual(rule.id, "circular_dependency_graph")
        XCTAssertEqual(rule.category, .architecture)
        XCTAssertEqual(rule.defaultSeverity, .error)
        XCTAssertFalse(rule.enabledByDefault)
    }
    
    // MARK: - GraphEnhancedNonSendableCaptureRule Tests
    
    func testGraphEnhancedNonSendableCaptureRuleMetadata() {
        let rule = GraphEnhancedNonSendableCaptureRule()
        XCTAssertEqual(rule.id, "non_sendable_capture_graph")
        XCTAssertEqual(rule.category, .concurrency)
        XCTAssertEqual(rule.defaultSeverity, .error)
        XCTAssertFalse(rule.enabledByDefault)
    }
}
