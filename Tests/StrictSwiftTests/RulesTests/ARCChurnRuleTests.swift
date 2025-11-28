import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

final class ARCChurnRuleTests: XCTestCase {
    
    // MARK: - Basic ARC Churn Detection
    
    func testDetectsReferenceTypeAllocationInLoop() async throws {
        let sourceCode = """
        import Foundation
        
        class TestClass {
            func problematicLoop() {
                for i in 0..<100 {
                    let view = UIView()  // Reference type allocation in loop
                    print(view)
                }
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should detect reference type allocation in loop")
        XCTAssertTrue(violations.contains { $0.message.contains("UIView") }, "Should mention UIView")
    }
    
    func testDetectsRepeatedSelfAccess() async throws {
        let sourceCode = """
        import Foundation
        
        class DataProcessor {
            var data: [String] = []
            var count: Int = 0
            var name: String = ""
            var value: Int = 0
            
            func processInLoop() {
                for i in 0..<100 {
                    self.data.append("item")
                    self.count += 1
                    self.name = "test"
                    self.value = i
                    print(self.data.count)
                    print(self.count)
                    print(self.name)
                }
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        
        // Enable property access check with a low threshold to detect self access
        var config = Configuration()
        config.setRuleParameter("arc_churn", "checkPropertyAccess", value: true)
        config.setRuleParameter("arc_churn", "maxRetainsInLoop", value: 3)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        // Should detect excessive self access
        let selfAccessViolations = violations.filter { $0.message.contains("self") }
        XCTAssertFalse(selfAccessViolations.isEmpty, "Should detect repeated self access in loop")
    }
    
    func testDetectsClosureCapturesInLoop() async throws {
        let sourceCode = """
        import Foundation
        
        class ClosureTest {
            var items: [String] = []
            
            func processWithClosures() {
                for i in 0..<100 {
                    let closure = { [self] in
                        self.items.append("item \\(i)")
                    }
                    closure()
                }
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        
        var config = Configuration()
        config.setRuleParameter("arc_churn", "checkClosureCaptures", value: true)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        let closureViolations = violations.filter { $0.message.contains("closure") || $0.message.contains("Closure") }
        XCTAssertFalse(closureViolations.isEmpty, "Should detect closure captures in loop")
    }
    
    func testDetectsHigherOrderFunctionsInLoop() async throws {
        let sourceCode = """
        import Foundation
        
        class ArrayProcessor {
            func inefficientProcess(items: [[Int]]) {
                for batch in items {
                    let filtered = batch.filter { $0 > 0 }  // Creates new array per iteration
                    let mapped = filtered.map { $0 * 2 }    // Another new array
                    print(mapped)
                }
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        
        // Enable higher-order function checks (disabled by default as they're common patterns)
        var config = Configuration()
        config.setRuleParameter("arc_churn", "checkArrayOperations", value: true)
        config.setRuleParameter("arc_churn", "checkHigherOrderFunctions", value: true)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        let arrayOpViolations = violations.filter { 
            $0.message.contains("filter") || $0.message.contains("map") 
        }
        XCTAssertFalse(arrayOpViolations.isEmpty, "Should detect higher-order functions in loop")
    }
    
    // MARK: - Hot Path Integration
    
    func testHotPathElevatesSeverity() async throws {
        let sourceCode = """
        import Foundation
        
        class PerformanceCritical {
            @hotPath
            func criticalFunction() {
                for i in 0..<100 {
                    let obj = NSObject()  // Should be error in hot path
                    print(obj)
                }
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        
        var config = Configuration()
        config.setRuleParameter("arc_churn", "checkHotPaths", value: true)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        // In hot paths, violations should be elevated to errors
        let errorViolations = violations.filter { $0.severity == .error }
        XCTAssertFalse(errorViolations.isEmpty, "Should elevate severity in hot paths")
    }
    
    // MARK: - Configuration Tests
    
    func testConfigurableThresholds() async throws {
        let sourceCode = """
        import Foundation
        
        class ConfigTest {
            var a: String = ""
            var b: String = ""
            
            func simpleLoop() {
                for i in 0..<10 {
                    self.a = "value"
                    self.b = "value"
                }
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        
        // With low threshold, should trigger
        var lowConfig = Configuration()
        lowConfig.setRuleParameter("arc_churn", "maxRetainsInLoop", value: 1)
        
        let lowContext = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: lowConfig
        )
        
        let lowViolations = await rule.analyze(sourceFile, in: lowContext)
        
        // With high threshold, should not trigger
        var highConfig = Configuration()
        highConfig.setRuleParameter("arc_churn", "maxRetainsInLoop", value: 100)
        
        let highContext = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: highConfig
        )
        
        let highViolations = await rule.analyze(sourceFile, in: highContext)
        
        XCTAssertGreaterThanOrEqual(lowViolations.count, highViolations.count,
            "Lower threshold should produce more or equal violations")
    }
    
    func testDisabledChecks() async throws {
        let sourceCode = """
        import Foundation
        
        class DisabledTest {
            func process() {
                for i in 0..<100 {
                    let filtered = [1,2,3].filter { $0 > 0 }
                    print(filtered)
                }
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        
        // Disable array operations check
        var config = Configuration()
        config.setRuleParameter("arc_churn", "checkArrayOperations", value: false)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        let arrayViolations = violations.filter { $0.message.contains("filter") }
        XCTAssertTrue(arrayViolations.isEmpty, "Should not detect array operations when disabled")
    }
    
    // MARK: - Iterator Expression Tests (False Positive Prevention)
    
    func testDoesNotFlagSortedInLoopIterator() async throws {
        let sourceCode = """
        func process(items: [String]) {
            // sorted() is called ONCE here to create the sequence, not per iteration
            for item in items.sorted() {
                print(item)
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        let sortedViolations = violations.filter { $0.message.contains("sorted") }
        
        XCTAssertTrue(sortedViolations.isEmpty, "Should not flag sorted() in loop iterator expression")
    }
    
    func testDoesNotFlagFilterInLoopIterator() async throws {
        let sourceCode = """
        func process(items: [Int]) {
            // filter() is called ONCE here to create the sequence, not per iteration
            for item in items.filter({ $0 > 0 }) {
                print(item)
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        let filterViolations = violations.filter { $0.message.contains("filter") }
        
        XCTAssertTrue(filterViolations.isEmpty, "Should not flag filter() in loop iterator expression")
    }
    
    func testFlagsSortedInLoopBody() async throws {
        let sourceCode = """
        func process(items: [String]) {
            for _ in 0..<10 {
                // sorted() is called 10 times here - this SHOULD be flagged
                let sorted = items.sorted()
                print(sorted.count)
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        
        // Enable higher-order function checks (disabled by default as they're common patterns)
        var config = Configuration()
        config.setRuleParameter("arc_churn", "checkHigherOrderFunctions", value: true)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        let sortedViolations = violations.filter { $0.message.contains("sorted") }
        
        XCTAssertFalse(sortedViolations.isEmpty, "Should flag sorted() inside loop body")
    }
    
    func testDoesNotFlagChainedOperationsInIterator() async throws {
        let sourceCode = """
        func process(items: [Int]) {
            // The entire chain runs ONCE to create the sequence
            for item in items.filter({ $0 > 0 }).sorted().map({ String($0) }) {
                print(item)
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ARCChurnRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        let chainViolations = violations.filter { 
            $0.message.contains("filter") || $0.message.contains("sorted") || $0.message.contains("map")
        }
        
        XCTAssertTrue(chainViolations.isEmpty, "Should not flag chained operations in loop iterator")
    }
}
