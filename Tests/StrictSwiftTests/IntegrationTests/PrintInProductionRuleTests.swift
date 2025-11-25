import XCTest
@testable import StrictSwiftCore
import Foundation

final class PrintInProductionRuleTests: XCTestCase {

    func testPrintInProductionRuleDetectsBasicPrint() async throws {
        // Create test source with print statement
        let source = """
        import Foundation

        func debugFunction() {
            print("Debug information")
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = PrintInProductionRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify violations
        XCTAssertGreaterThan(violations.count, 0)

        // Check violation
        let firstViolation = violations[0]
        XCTAssertEqual(firstViolation.ruleId, "print_in_production")
        XCTAssertEqual(firstViolation.category, .safety)
        XCTAssertEqual(firstViolation.severity, .warning)
        XCTAssertTrue(firstViolation.message.contains("print()"))
        XCTAssertTrue(firstViolation.suggestedFixes.contains("Replace with proper logging framework or remove debug output"))
    }

    func testPrintInProductionRuleIgnoresNonPrintFunctions() async throws {
        // Create test source without print statements
        let source = """
        import Foundation

        func debugFunction() {
            // These should NOT trigger violations
            log("Debug information")
            logger.info("Information")
            NSLog("System log")

            // Variable named print (should not trigger)
            let customPrint = "custom print function"
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = PrintInProductionRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify no violations (adjust if pattern matching is too broad)
        XCTAssertEqual(violations.count, 0)
    }

    func testPrintInProductionRuleDifferentContexts() async throws {
        // Create test source with various print contexts
        let source = """
        import Foundation

        struct Logger {
            func logInfo() {
                print("Info from struct")
            }
        }

        class DataManager {
            func processData() {
                print("Processing data")
                let result = "processed"
                print("Result: \\(result)")
            }
        }

        // print in closure
        let closure = {
            print("Debug from closure")
        }

        // print with complex expression
        func complexLogging(items: [String]) {
            print("Items count: \\(items.count), first: \\(items.first ?? "none")")
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = PrintInProductionRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect some print calls
        XCTAssertGreaterThan(violations.count, 0)

        // All violations should be print violations
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "print_in_production")
            XCTAssertEqual(violation.category, .safety)
            XCTAssertEqual(violation.severity, .warning)
            XCTAssertTrue(violation.message.contains("print()"))
        }
    }

    func testPrintInProductionRuleLocationAccuracy() async throws {
        // Create test source with specific line numbers
        let source = """
        func debug() {
            let value = 42
            print("Value is \\(value)")
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = PrintInProductionRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify location
        XCTAssertGreaterThan(violations.count, 0)
        let violation = violations[0]
        XCTAssertGreaterThan(violation.location.line, 0)
        XCTAssertTrue(violation.location.file.lastPathComponent.contains("test.swift"))
    }

    func testPrintInProductionRuleWithDifferentPrintFormats() async throws {
        // Create test source with different print formats
        let source = """
        func testPrintFormats() {
            // Empty print
            print()

            // String literal
            print("Simple message")

            // String interpolation
            let value = 42
            print("Value is \\(value)")

            // Multiple arguments
            print("Value:", value, "Double:", value * 2)

            // Terminator parameter
            print("Message", terminator: "")

            // Separator parameter
            print("A", "B", "C", separator: "-")
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = PrintInProductionRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect multiple print calls
        XCTAssertGreaterThan(violations.count, 0)

        // All violations should have correct properties
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "print_in_production")
            XCTAssertEqual(violation.category, .safety)
            XCTAssertEqual(violation.severity, .warning)
        }
    }

    func testPrintInProductionRuleSeverity() async throws {
        // Verify that print statements are warnings, not errors
        let source = """
        func testSeverity() {
            print("This should be a warning")
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = PrintInProductionRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        XCTAssertGreaterThan(violations.count, 0)
        for violation in violations {
            XCTAssertEqual(violation.severity, .warning)
        }
    }

    // MARK: - Helper Methods

    private func createSourceFile(content: String, filename: String) throws -> SourceFile {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString)-\(filename)")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Register cleanup
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }

        return try SourceFile(url: fileURL)
    }

    private func createAnalysisContext(sourceFile: SourceFile) -> AnalysisContext {
        let configuration = Configuration.default
        let projectRoot = FileManager.default.temporaryDirectory
        let context = AnalysisContext(configuration: configuration, projectRoot: projectRoot)
        context.addSourceFile(sourceFile)
        return context
    }
}