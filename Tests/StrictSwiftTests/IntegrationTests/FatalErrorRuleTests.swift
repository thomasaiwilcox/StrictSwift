import XCTest
@testable import StrictSwiftCore
import Foundation

final class FatalErrorRuleTests: XCTestCase {

    func testFatalErrorRuleDetectsBasicFatalError() async throws {
        // Create test source with fatalError
        let source = """
        import Foundation

        func validateCondition(_ condition: Bool) {
            if !condition {
                fatalError("Invalid condition")
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = FatalErrorRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify violations
        XCTAssertGreaterThan(violations.count, 0)

        // Check violation
        let firstViolation = violations[0]
        XCTAssertEqual(firstViolation.ruleId, "fatal_error")
        XCTAssertEqual(firstViolation.category, .safety)
        XCTAssertEqual(firstViolation.severity, .error)
        XCTAssertTrue(firstViolation.message.contains("fatalError()"))
        XCTAssertTrue(firstViolation.suggestedFixes.contains("Replace with proper error handling: return error, use optional, or throw an exception"))
    }

    func testFatalErrorRuleIgnoresRegularFunctions() async throws {
        // Create test source without fatalError calls
        let source = """
        import Foundation

        func validateCondition(_ condition: Bool) -> Bool {
            if !condition {
                return false
            }
            return true
        }

        func handleError() {
            print("Error occurred")
        }

        // Variable named fatalError (should not trigger)
        let fatalError = "some string"
        print(fatalError)
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = FatalErrorRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify no violations
        XCTAssertEqual(violations.count, 0)
    }

    func testFatalErrorRuleDifferentContexts() async throws {
        // Create test source with various fatalError contexts
        let source = """
        import Foundation

        struct Validator {
            func validate(_ value: String) {
                guard !value.isEmpty else {
                    fatalError("Value cannot be empty")
                }
            }
        }

        class DataManager {
            let requiredData: String

            init(data: String?) {
                guard let data = data else {
                    fatalError("Data is required")
                }
                self.requiredData = data
            }
        }

        // fatalError in closure
        let processData = { (input: String?) in
            guard let input = input else {
                fatalError("No input provided")
            }
            return input.uppercased()
        }

        // fatalError with complex expression
        func complexValidation(_ items: [String]) {
            guard !items.isEmpty else {
                fatalError("Items array cannot be empty, got \\(items.count) items")
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = FatalErrorRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect some fatalError calls
        XCTAssertGreaterThan(violations.count, 0)

        // All violations should be fatalError violations
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "fatal_error")
            XCTAssertEqual(violation.category, .safety)
            XCTAssertEqual(violation.severity, .error)
            XCTAssertTrue(violation.message.contains("fatalError()"))
        }
    }

    func testFatalErrorRuleLocationAccuracy() async throws {
        // Create test source with specific line numbers
        let source = """
        func validate() {
            let condition = false
            if !condition {
                fatalError("This should be detected")
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = FatalErrorRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify location
        XCTAssertGreaterThan(violations.count, 0)
        let violation = violations[0]
        XCTAssertGreaterThan(violation.location.line, 0)
        XCTAssertTrue(violation.location.file.lastPathComponent.contains("test.swift"))
    }

    func testFatalErrorRuleWithDifferentMessageFormats() async throws {
        // Create test source with different fatalError message formats
        let source = """
        func testCases() {
            // Empty message
            fatalError()

            // String literal
            fatalError("Simple message")

            // String interpolation
            let value = 42
            fatalError("Value is \\(value)")

            // Multi-line
            fatalError(
                "Complex message " +
                "with concatenation"
            )
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = FatalErrorRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect multiple fatalError calls
        XCTAssertGreaterThan(violations.count, 0)

        // All violations should have correct properties
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "fatal_error")
            XCTAssertEqual(violation.category, .safety)
            XCTAssertEqual(violation.severity, .error)
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