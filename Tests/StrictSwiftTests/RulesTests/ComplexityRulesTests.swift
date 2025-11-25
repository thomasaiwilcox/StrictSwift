import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

/// Tests for CyclomaticComplexityRule
final class CyclomaticComplexityRuleTests: XCTestCase {
    
    func testDetectsHighComplexity() async throws {
        let sourceCode = """
        func complexFunction(a: Int, b: Int, c: Int, d: Bool, e: Bool) -> Int {
            var result = 0
            if a > 0 {
                if b > 0 {
                    result += 1
                } else if c > 0 {
                    result += 2
                }
            } else if d {
                result += 3
            } else if e {
                result += 4
            }
            
            switch a {
            case 1: result += 10
            case 2: result += 20
            case 3: result += 30
            case 4: result += 40
            case 5: result += 50
            default: result += 100
            }
            
            for i in 0..<10 {
                if i % 2 == 0 {
                    result += i
                }
            }
            
            return result
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = CyclomaticComplexityRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should detect high complexity")
        XCTAssertEqual(violations.first?.ruleId, "cyclomatic_complexity")
    }
    
    func testNoFalsePositiveOnSimpleFunction() async throws {
        let sourceCode = """
        func simpleFunction(value: Int) -> Int {
            return value * 2
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = CyclomaticComplexityRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 0, "Should not flag simple function")
    }
}

/// Tests for NestingDepthRule
final class NestingDepthRuleTests: XCTestCase {
    
    func testDetectsDeepNesting() async throws {
        let sourceCode = """
        func deeplyNested(a: Bool, b: Bool, c: Bool, d: Bool, e: Bool, f: Bool) {
            if a {
                if b {
                    if c {
                        if d {
                            if e {
                                if f {
                                    print("Too deep!")
                                }
                            }
                        }
                    }
                }
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = NestingDepthRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should detect deep nesting")
        XCTAssertEqual(violations.first?.ruleId, "nesting_depth")
    }
    
    func testNoFalsePositiveOnShallowNesting() async throws {
        let sourceCode = """
        func shallowNesting(value: Int?) {
            if let v = value {
                print(v)
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = NestingDepthRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 0, "Should not flag shallow nesting")
    }
}

/// Tests for FunctionLengthRule
final class FunctionLengthRuleTests: XCTestCase {
    
    func testDetectsLongFunction() async throws {
        var lines = ""
        for i in 1...60 {
            lines += "        let line\(i) = \(i)\n"
        }
        
        let sourceCode = """
        func veryLongFunction() {
        \(lines)    }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = FunctionLengthRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should detect long function")
        XCTAssertEqual(violations.first?.ruleId, "function_length")
    }
    
    func testNoFalsePositiveOnShortFunction() async throws {
        let sourceCode = """
        func shortFunction() {
            let a = 1
            let b = 2
            let c = a + b
            print(c)
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = FunctionLengthRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 0, "Should not flag short function")
    }
}
