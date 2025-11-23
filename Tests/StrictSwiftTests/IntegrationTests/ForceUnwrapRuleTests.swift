import XCTest
@testable import StrictSwiftCore
import Foundation

final class ForceUnwrapRuleTests: XCTestCase {

    func testForceUnwrapRuleDetectsBasicForceUnwraps() async throws {
        // Create test source with force unwraps
        let source = """
        import Foundation

        func testFunction() {
            let optional: String? = "test"
            let forced = optional!  // Should trigger violation

            let chained = optional!.count  // Should trigger violation
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = ForceUnwrapRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify violations
        XCTAssertEqual(violations.count, 2)

        // Check first violation (basic force unwrap)
        let firstViolation = violations[0]
        XCTAssertEqual(firstViolation.ruleId, "force_unwrap")
        XCTAssertEqual(firstViolation.category, .safety)
        XCTAssertEqual(firstViolation.severity, .error)
        XCTAssertEqual(firstViolation.location.line, 5) // Adjusted to actual line number
        XCTAssertTrue(firstViolation.message.contains("Force unwrap"))

        // Check second violation (force unwrap in method chaining)
        let secondViolation = violations[1]
        XCTAssertEqual(secondViolation.ruleId, "force_unwrap")
        XCTAssertEqual(secondViolation.location.line, 7) // Adjusted to actual line number
        XCTAssertTrue(secondViolation.message.contains("Force unwrap"))
    }

    func testForceUnwrapRuleIgnoresSafeOptionalOperations() async throws {
        // Create test source with safe optional operations
        let source = """
        import Foundation

        func testFunction() {
            let optional: String? = "test"

            // These should NOT trigger violations
            if let safe = optional {
                print(safe)
            }

            guard let guarded = optional else { return }
            print(guarded)

            let nilCoalesced = optional ?? "default"
            print(nilCoalesced)

            let optionalChained = optional?.count
            print(optionalChained)
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = ForceUnwrapRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify no violations
        XCTAssertEqual(violations.count, 0)
    }

    func testForceUnwrapRuleDetectsViolationsInStructsAndClasses() async throws {
        // Create test source with force unwraps in different contexts
        let source = """
        import Foundation

        struct TestStruct {
            var property: String?

            func method() {
                let value = property!  // Should trigger violation
                let count = property!.count  // Should trigger violation
            }
        }

        class TestClass {
            let optional: String?

            init(optional: String?) {
                self.optional = optional
                let forced = optional!  // Should trigger violation
            }

            func method() {
                let value = optional!  // Should trigger violation
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = ForceUnwrapRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify violations
        XCTAssertEqual(violations.count, 4)

        // All violations should be force unwrap violations
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "force_unwrap")
            XCTAssertEqual(violation.category, .safety)
            XCTAssertEqual(violation.severity, .error)
        }
    }

    func testForceUnwrapRuleLocationAccuracy() async throws {
        // Create test source to verify location accuracy
        let source = """
        // Line 1
        // Line 2
        func test() {  // Line 3
            let opt: String? = "test"  // Line 4
            let forced = opt!  // Line 5 - Column 19
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = ForceUnwrapRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify location accuracy
        XCTAssertEqual(violations.count, 1)
        let violation = violations[0]
        XCTAssertEqual(violation.location.line, 5) // Adjusted to actual line number
        XCTAssertEqual(violation.location.column, 18) // Actual column position
        XCTAssertTrue(violation.location.file.lastPathComponent.contains("test.swift")) // Check that filename is present (ignoring UUID prefix)
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