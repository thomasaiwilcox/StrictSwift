import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

final class ComplexityAnalysisTests: XCTestCase {

    // MARK: - CyclomaticComplexityRule Tests

    func testCyclomaticComplexityBasicAnalysis() async throws {
        let sourceCode = """
        import Foundation

        class ComplexClass {
            func simpleMethod() {
                print("simple")
            }

            func complexMethod(condition: Bool, flag: Bool) {
                if condition {  // +1
                    print("branch 1")
                } else {      // +1
                    print("branch 2")
                }

                for i in 0..<10 {    // +1
                    if flag {         // +1
                        print("nested branch")
                    }
                }

                switch condition {   // +1
                case true:
                    print("true case")
                case false:
                    print("false case")
                }
            }
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

        // Should detect complexity violations
        XCTAssertFalse(violations.isEmpty, "Should detect cyclomatic complexity violations")

        let complexityViolations = violations.filter { $0.ruleId == "cyclomatic_complexity" }
        XCTAssertFalse(complexityViolations.isEmpty, "Should have cyclomatic complexity violations")

        // Verify location accuracy
        for violation in complexityViolations {
            XCTAssertGreaterThan(violation.location.line, 1, "Violation location should not be line 1")
        }
    }

    func testCyclomaticComplexityConfigurableThresholds() async throws {
        let sourceCode = """
        import Foundation

        func moderatelyComplex(data: [String]) -> String {
            var result = ""

            for item in data {    // +1
                if item.isEmpty {  // +1
                    continue
                }

                if item.hasPrefix("test") {  // +1
                    result += item
                } else if item.hasPrefix("prod") {  // +1
                    result += item.uppercased()
                }
            }

            return result
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = CyclomaticComplexityRule()

        // Set a low threshold to trigger violations
        var config = Configuration()
        config.setRuleParameter("cyclomatic_complexity", "maxComplexity", value: 3)
        config.setRuleParameter("cyclomatic_complexity", "maxFileComplexity", value: 5)
        config.enableRule("cyclomatic_complexity", enabled: true)

        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )

        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect violations with low threshold
        XCTAssertFalse(violations.isEmpty, "Should detect complexity violations with low threshold")

        // Verify configuration is applied
        let functionViolations = violations.filter { $0.ruleId == "cyclomatic_complexity" }
        XCTAssertFalse(functionViolations.isEmpty, "Should have function-level complexity violations")
    }

    // MARK: - NestingDepthRule Tests

    func testNestingDepthBasicAnalysis() async throws {
        let sourceCode = """
        import Foundation

        class DeeplyNested {
            func deeplyNestedMethod() {
                if true {                                    // Level 1
                    if true {                                // Level 2
                        for i in 0..<10 {                   // Level 3
                            if true {                        // Level 4
                                while true {                 // Level 5
                                    if true {                // Level 6
                                        print("too deep")
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
        let rule = NestingDepthRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )

        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect excessive nesting
        XCTAssertFalse(violations.isEmpty, "Should detect nesting depth violations")

        let nestingViolations = violations.filter { $0.ruleId == "nesting_depth" }
        XCTAssertFalse(nestingViolations.isEmpty, "Should have nesting depth violations")

        // Verify location accuracy
        for violation in nestingViolations {
            XCTAssertGreaterThan(violation.location.line, 1, "Violation location should not be line 1")
        }
    }

    func testNestingDepthDifferentControlStructures() async throws {
        let sourceCode = """
        import Foundation

        func mixedNesting() {
            // Test different control structures
            guard true else { return }

            if true {
                switch "test" {
                case "test":
                    for i in 0..<5 {
                        if true {
                            while true {
                                defer { }
                                repeat {
                                    if true { }
                                } while false
                            }
                        }
                    }
                default:
                    break
                }
            }
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = NestingDepthRule()

        // Set a lower threshold for testing
        var config = Configuration()
        config.setRuleParameter("nesting_depth", "maxNestingDepth", value: 4)
        config.enableRule("nesting_depth", enabled: true)

        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )

        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect violations with lower threshold
        XCTAssertFalse(violations.isEmpty, "Should detect mixed nesting violations")
    }

    // MARK: - FunctionLengthRule Tests

    func testFunctionLengthBasicAnalysis() async throws {
        // Create a long function
        let functionBody = """
        var result = ""

        // Add many lines to exceed length limit
        for i in 1...30 {
            switch i % 4 {
            case 0:
                result += "Multiple case \\(i)\\n"
                if i > 10 {
                    result += "Nested logic\\n"
                }
            case 1:
                result += "Another case \\(i)\\n"
            case 2:
                result += "Yet another case \\(i)\\n"
                if i < 20 {
                    result += "More nested logic\\n"
                }
            default:
                result += "Default case \\(i)\\n"
            }
        }

        return result
        """

        let sourceCode = """
        import Foundation

        class LongFunctionClass {
            func veryLongFunction() -> String {
        \(functionBody)
            }
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = FunctionLengthRule()
        
        // Configure with a lower threshold so the test function triggers a violation
        var config = Configuration()
        config.setRuleParameter("function_length", "maxFunctionLength", value: 20)
        config.enableRule("function_length", enabled: true)
        
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )

        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect function length violations
        XCTAssertFalse(violations.isEmpty, "Should detect function length violations")

        let lengthViolations = violations.filter { $0.ruleId == "function_length" }
        XCTAssertFalse(lengthViolations.isEmpty, "Should have function length violations")
    }

    func testFunctionLengthConfigurableParameters() async throws {
        let shortFunction = """
        func shortFunction() {
            print("short")
            print("still short")
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: shortFunction)
        let rule = FunctionLengthRule()

        // Set very low threshold to trigger violations
        var config = Configuration()
        config.setRuleParameter("function_length", "maxFunctionLength", value: 2)
        config.setRuleParameter("function_length", "countEmptyLines", value: true)
        config.enableRule("function_length", enabled: true)

        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )

        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect violations even with short function
        XCTAssertFalse(violations.isEmpty, "Should detect function length violations with low threshold")
    }

    // MARK: - Location Accuracy Tests for Complexity Rules

    func testComplexityRulesLocationAccuracy() async throws {
        let sourceCode = """
        import Foundation

        class LocationTestComplexity {
            // Line 6: Simple method
            func simpleMethod() {
                print("simple")
            }

            // Line 10: Complex method starts here
            func complexMethod(data: [String]) {
                if data.isEmpty {              // Line 12
                    return
                }

                for item in data {             // Line 16
                    if item.count > 5 {       // Line 17
                        if item.hasPrefix("test") {  // Line 18 - Deep nesting here
                            print(item)
                        }
                    }
                }
            }
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)

        let complexityRule = CyclomaticComplexityRule()
        let nestingRule = NestingDepthRule()
        let lengthRule = FunctionLengthRule()

        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )

        async let complexityViolations = complexityRule.analyze(sourceFile, in: context)
        async let nestingViolations = nestingRule.analyze(sourceFile, in: context)
        async let lengthViolations = lengthRule.analyze(sourceFile, in: context)

        let (compResult, nestResult, lenResult) = await (complexityViolations, nestingViolations, lengthViolations)

        // Verify location accuracy for all complexity rules
        let allViolations = compResult + nestResult + lenResult

        for violation in allViolations {
            XCTAssertGreaterThan(violation.location.line, 1, "Violation should not be at line 1")
            XCTAssertLessThanOrEqual(violation.location.line, 22, "Violation should be within source range")
            XCTAssertGreaterThan(violation.location.column, 0, "Column should be positive")
        }

        // If we have nesting violations, they should be around line 18 where deep nesting occurs
        if !nestResult.isEmpty {
            let nestingLines = nestResult.map { $0.location.line }
            XCTAssertTrue(nestingLines.contains { $0 >= 16 && $0 <= 18 }, "Should have nesting violations around line 16-18")
        }
    }

    // MARK: - Performance Tests

    func testComplexityAnalysisPerformance() async throws {
        // Create a large file with many functions
        var sourceCode = """
        import Foundation

        class PerformanceTestComplexity {
        """

        // Add many functions with varying complexity
        for i in 1...50 {
            sourceCode += """

            func function\\(i)(data: [String]) -> String {
                var result = ""

                for item in data {
                    if item.isEmpty {
                        continue
                    }

                    switch i % 4 {
                    case 0:
                        result += item
                    case 1:
                        result += item.uppercased()
                    case 2:
                        result += item.lowercased()
                    default:
                        result += item
                    }
                }

                return result
            }
            """
        }

        sourceCode += """
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/performance_complexity.swift"), source: sourceCode)

        let complexityRule = CyclomaticComplexityRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )

        // Measure performance
        let startTime = Date()
        let violations = await complexityRule.analyze(sourceFile, in: context)
        let timeElapsed = Date().timeIntervalSince(startTime)

        // Should complete in reasonable time
        XCTAssertLessThan(timeElapsed, 2.0, "Complexity analysis should complete quickly")
        XCTAssertNotNil(violations, "Should complete complexity analysis")

        // Should analyze all functions
        XCTAssertGreaterThan(violations.count, 0, "Should analyze multiple functions")
    }
}