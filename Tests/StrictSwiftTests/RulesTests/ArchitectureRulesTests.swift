import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

/// Tests for EnhancedGodClassRule
final class EnhancedGodClassRuleUnitTests: XCTestCase {
    
    func testDetectsClassWithTooManyMethods() async throws {
        var methods = ""
        for i in 1...20 {
            methods += "    func method\(i)() {}\n"
        }
        
        let sourceCode = """
        class GodClass {
        \(methods)}
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = EnhancedGodClassRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should detect god class with many methods")
        XCTAssertEqual(violations.first?.ruleId, "enhanced_god_class")
        XCTAssertEqual(violations.first?.category, .architecture)
    }
    
    func testNoFalsePositiveOnSmallClass() async throws {
        let sourceCode = """
        class SmallClass {
            var name: String = ""
            var age: Int = 0
            
            func greet() {
                print("Hello, \\(name)")
            }
            
            func birthday() {
                age += 1
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = EnhancedGodClassRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 0, "Should not flag small, well-designed class")
    }
}

/// Tests for CircularDependencyRule
final class CircularDependencyRuleUnitTests: XCTestCase {
    
    func testNoFalsePositiveOnLinearDependencies() async throws {
        let sourceCode = """
        class A {
            var b: B?
        }
        
        class B {
            var c: C?
        }
        
        class C {
            var value: Int = 0
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = CircularDependencyRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 0, "Should not flag linear dependencies")
    }
}

/// Tests for GlobalStateRule
final class GlobalStateRuleUnitTests: XCTestCase {
    
    func testDetectsGlobalMutableState() async throws {
        let sourceCode = """
        var globalCounter = 0
        
        func increment() {
            globalCounter += 1
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = GlobalStateRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertGreaterThanOrEqual(violations.count, 1, "Should detect global mutable state")
        XCTAssertEqual(violations.first?.ruleId, "global_state")
    }
    
    func testNoFalsePositiveOnGlobalConstants() async throws {
        let sourceCode = """
        let appVersion = "1.0.0"
        let maxRetries = 3
        
        struct Config {
            static let timeout: TimeInterval = 30
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = GlobalStateRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 0, "Should not flag global constants")
    }
}

/// Tests for EnhancedLayeredDependenciesRule
final class EnhancedLayeredDependenciesRuleUnitTests: XCTestCase {
    
    func testRuleInitializes() async throws {
        let rule = EnhancedLayeredDependenciesRule()
        XCTAssertEqual(rule.id, "enhanced_layered_dependencies")
        XCTAssertEqual(rule.category, .architecture)
    }
    
    func testAnalyzesWithoutCrash() async throws {
        let sourceCode = """
        import Foundation
        import UIKit
        
        class ViewController {
            func viewDidLoad() {}
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = EnhancedLayeredDependenciesRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        // Should not crash
        let violations = await rule.analyze(sourceFile, in: context)
        XCTAssertNotNil(violations)
    }
}
