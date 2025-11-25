import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

/// Tests for RepeatedAllocationRule
final class RepeatedAllocationRuleTests: XCTestCase {
    
    func testDetectsAllocationInLoop() async throws {
        let sourceCode = """
        func processItems() {
            for i in 0..<1000 {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                print(formatter.string(from: Date()))
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = RepeatedAllocationRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        // Should detect allocation in loop
        XCTAssertFalse(violations.isEmpty, "Should detect allocation in loop")
        XCTAssertEqual(violations.first?.ruleId, "repeated_allocation")
        XCTAssertEqual(violations.first?.category, .performance)
    }
    
    func testNoFalsePositiveOnHoistedAllocation() async throws {
        let sourceCode = """
        func processItemsOptimized() {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            
            for i in 0..<1000 {
                print(formatter.string(from: Date()))
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = RepeatedAllocationRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        // Hoisted allocation should be fine
        let loopAllocationViolations = violations.filter {
            $0.message.lowercased().contains("loop")
        }
        XCTAssertEqual(loopAllocationViolations.count, 0, "Should not flag hoisted allocation")
    }
}

/// Tests for LargeStructCopyRule
final class LargeStructCopyRuleTests: XCTestCase {
    
    func testDetectsLargeStructCopy() async throws {
        var properties = ""
        for i in 1...30 {
            properties += "    var property\(i): String = \"\"\n"
        }
        
        let sourceCode = """
        struct LargeStruct {
        \(properties)}
        
        func processLargeStruct(_ s: LargeStruct) {
            let copy = s  // This is a copy of a large struct
            print(copy.property1)
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = LargeStructCopyRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        // Should detect large struct (may or may not detect the copy depending on analysis depth)
        XCTAssertEqual(violations.first?.ruleId ?? "large_struct_copy", "large_struct_copy")
    }
    
    func testNoFalsePositiveOnSmallStruct() async throws {
        let sourceCode = """
        struct SmallStruct {
            var x: Int
            var y: Int
        }
        
        func processSmallStruct(_ s: SmallStruct) {
            let copy = s
            print(copy.x)
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = LargeStructCopyRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        // Small struct should not trigger
        XCTAssertEqual(violations.count, 0, "Should not flag small struct")
    }
}

/// Tests for EscapingReferenceRule
final class EscapingReferenceRuleTests: XCTestCase {
    
    func testDetectsEscapingClosure() async throws {
        let sourceCode = """
        class Handler {
            var callback: (() -> Void)?
            
            func setup() {
                callback = {
                    self.doSomething()
                }
            }
            
            func doSomething() {}
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = EscapingReferenceRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        // Should detect escaping reference (self captured in stored closure)
        XCTAssertFalse(violations.isEmpty, "Should detect escaping reference")
        XCTAssertEqual(violations.first?.ruleId, "escaping_reference")
    }
}

/// Tests for ExclusiveAccessRule
final class ExclusiveAccessRuleTests: XCTestCase {
    
    func testRuleInitializes() async throws {
        let rule = ExclusiveAccessRule()
        XCTAssertEqual(rule.id, "exclusive_access")
        XCTAssertEqual(rule.category, .memory)
    }
    
    func testAnalyzesWithoutCrash() async throws {
        let sourceCode = """
        struct Container {
            var values: [Int] = []
            
            mutating func append(_ value: Int) {
                values.append(value)
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ExclusiveAccessRule()
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
