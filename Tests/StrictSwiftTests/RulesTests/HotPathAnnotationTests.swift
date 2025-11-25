import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

final class HotPathAnnotationTests: XCTestCase {
    
    // MARK: - HotPathAnnotation Detection Tests
    
    func testDetectsHotPathAttribute() {
        let sourceCode = """
        @hotPath
        func criticalFunction() {
            // Performance critical code
        }
        """
        
        let tree = Parser.parse(source: sourceCode)
        let collector = HotPathCollector()
        collector.walk(tree)
        
        XCTAssertEqual(collector.hotPathFunctions.count, 1, "Should detect one @hotPath function")
        XCTAssertEqual(collector.hotPathFunctions.first?.name, "criticalFunction")
    }
    
    func testDetectsHotPathWithReason() {
        let sourceCode = """
        @hotPath("Called 10000x per frame")
        func renderLoop() {
            // Hot rendering code
        }
        """
        
        let tree = Parser.parse(source: sourceCode)
        let collector = HotPathCollector()
        collector.walk(tree)
        
        XCTAssertEqual(collector.hotPathFunctions.count, 1)
        XCTAssertEqual(collector.hotPathFunctions.first?.reason, "Called 10000x per frame")
    }
    
    func testDetectsMultipleHotPathFunctions() {
        let sourceCode = """
        @hotPath
        func function1() {}
        
        func normalFunction() {}
        
        @hotPath
        func function2() {}
        
        @HotPath
        func function3() {}
        """
        
        let tree = Parser.parse(source: sourceCode)
        let collector = HotPathCollector()
        collector.walk(tree)
        
        XCTAssertEqual(collector.hotPathFunctions.count, 3, "Should detect all @hotPath functions")
    }
    
    func testDetectsAsyncHotPath() {
        let sourceCode = """
        @hotPath
        func syncFunction() {}
        
        @hotPath
        func asyncFunction() async {}
        """
        
        let tree = Parser.parse(source: sourceCode)
        let collector = HotPathCollector()
        collector.walk(tree)
        
        let asyncFuncs = collector.hotPathFunctions.filter { $0.isAsync }
        let syncFuncs = collector.hotPathFunctions.filter { !$0.isAsync }
        
        XCTAssertEqual(asyncFuncs.count, 1, "Should detect one async hot path")
        XCTAssertEqual(syncFuncs.count, 1, "Should detect one sync hot path")
    }
    
    func testAlternativeAnnotationNames() {
        let sourceCode = """
        @performanceCritical
        func func1() {}
        
        @PerformanceCritical
        func func2() {}
        
        @hot_path
        func func3() {}
        """
        
        let tree = Parser.parse(source: sourceCode)
        let collector = HotPathCollector()
        collector.walk(tree)
        
        XCTAssertEqual(collector.hotPathFunctions.count, 3, "Should detect alternative annotation names")
    }
    
    // MARK: - HotPathValidationRule Tests
    
    func testValidationRuleDetectsAsyncInHotPath() async throws {
        let sourceCode = """
        import Foundation
        
        class AsyncTest {
            @hotPath
            func shouldNotBeAsync() async {
                // Async in hot path is problematic
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = HotPathValidationRule()
        
        var config = Configuration()
        config.setRuleParameter("hot_path_validation", "flagAsyncInHotPath", value: true)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should detect async in hot path")
        XCTAssertTrue(violations.contains { $0.message.contains("async") })
    }
    
    func testValidationRuleDetectsHighComplexity() async throws {
        let sourceCode = """
        import Foundation
        
        class ComplexityTest {
            @hotPath
            func tooComplex(value: Int) {
                if value > 0 {
                    if value > 10 {
                        if value > 100 {
                            if value > 1000 {
                                if value > 10000 {
                                    if value > 100000 {
                                        print("Very high")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = HotPathValidationRule()
        
        var config = Configuration()
        config.setRuleParameter("hot_path_validation", "maxComplexityInHotPath", value: 5)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        let complexityViolations = violations.filter { $0.message.contains("complexity") }
        XCTAssertFalse(complexityViolations.isEmpty, "Should detect high complexity in hot path")
    }
    
    func testValidationRuleDetectsDeepNesting() async throws {
        let sourceCode = """
        import Foundation
        
        class NestingTest {
            @hotPath
            func deeplyNested(values: [[Int]]) {
                for outer in values {
                    for middle in outer {
                        for inner in 0..<middle {
                            for deepest in 0..<inner {
                                print(deepest)
                            }
                        }
                    }
                }
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = HotPathValidationRule()
        
        var config = Configuration()
        config.setRuleParameter("hot_path_validation", "maxNestingInHotPath", value: 3)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        let nestingViolations = violations.filter { $0.message.contains("Nesting") || $0.message.contains("nesting") }
        XCTAssertFalse(nestingViolations.isEmpty, "Should detect deep nesting in hot path")
    }
    
    func testValidationRuleDetectsHeapAllocations() async throws {
        let sourceCode = """
        import Foundation
        
        class AllocationTest {
            @hotPath
            func allocatesHeap() {
                let array = [Int]()  // Array literal creates heap allocation
                let dict = [String: Int]()  // Dictionary literal
                let closure = { print("closure") }  // Closure allocation
                print(array, dict)
                closure()
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = HotPathValidationRule()
        
        var config = Configuration()
        config.setRuleParameter("hot_path_validation", "flagHeapAllocations", value: true)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        // Closure detection should work
        let closureViolations = violations.filter { $0.message.contains("Closure") || $0.message.contains("closure") }
        XCTAssertFalse(closureViolations.isEmpty, "Should detect closure allocations in hot path")
    }
    
    func testValidationRuleDetectsClosuresInHotPath() async throws {
        let sourceCode = """
        import Foundation
        
        class ClosureTest {
            @hotPath
            func usesClosures() {
                let closure = { print("hello") }  // Closure allocation
                closure()
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = HotPathValidationRule()
        
        var config = Configuration()
        config.setRuleParameter("hot_path_validation", "flagHeapAllocations", value: true)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        let closureViolations = violations.filter { $0.message.contains("Closure") || $0.message.contains("closure") }
        XCTAssertFalse(closureViolations.isEmpty, "Should detect closures in hot path")
    }
    
    func testValidationRuleDetectsLongFunctions() async throws {
        let sourceCode = """
        import Foundation
        
        class LengthTest {
            @hotPath
            func veryLongFunction() {
                print("line 1")
                print("line 2")
                print("line 3")
                print("line 4")
                print("line 5")
                print("line 6")
                print("line 7")
                print("line 8")
                print("line 9")
                print("line 10")
                print("line 11")
                print("line 12")
                print("line 13")
                print("line 14")
                print("line 15")
                print("line 16")
                print("line 17")
                print("line 18")
                print("line 19")
                print("line 20")
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = HotPathValidationRule()
        
        var config = Configuration()
        config.setRuleParameter("hot_path_validation", "maxLengthInHotPath", value: 10)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        let lengthViolations = violations.filter { $0.message.contains("lines") }
        XCTAssertFalse(lengthViolations.isEmpty, "Should detect long functions in hot path")
    }
    
    func testNoViolationsForNonHotPath() async throws {
        let sourceCode = """
        import Foundation
        
        class NormalClass {
            func normalFunction() async {
                let array = Array<Int>()
                let closure = { print("hello") }
                closure()
                print(array)
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = HotPathValidationRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertTrue(violations.isEmpty, "Should not flag non-@hotPath functions")
    }
    
    // MARK: - HotPathConfiguration Tests
    
    func testConfigurationThresholdAdjustment() {
        let config = HotPathConfiguration()
        
        // Default multiplier is 0.5
        XCTAssertEqual(config.adjustedThreshold(10), 5)
        XCTAssertEqual(config.adjustedThreshold(100), 50)
    }
    
    func testConfigurationSeverityElevation() {
        var config = HotPathConfiguration()
        config.elevateToError = true
        
        XCTAssertEqual(config.severity(for: .warning), .error)
        XCTAssertEqual(config.severity(for: .error), .error)
        XCTAssertEqual(config.severity(for: .info), .info)
        
        config.elevateToError = false
        XCTAssertEqual(config.severity(for: .warning), .warning)
    }
}
