import XCTest
@testable import StrictSwiftCore
import Foundation

final class NonSendableCaptureRuleTests: XCTestCase {

    func testNonSendableCaptureRuleDetectsTaskCapture() async throws {
        // Create test source with Task capturing non-Sendable type
        let source = """
        import Foundation

        class ViewController: UIViewController {
            func processAsync() {
                Task {
                    self.updateView() // Potential non-Sendable capture
                }
            }

            func updateView() {
                // Update UI
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = NonSendableCaptureRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify violations
        XCTAssertGreaterThan(violations.count, 0)

        // Check violation
        let firstViolation = violations[0]
        XCTAssertEqual(firstViolation.ruleId, "non_sendable_capture")
        XCTAssertEqual(firstViolation.category, .concurrency)
        XCTAssertEqual(firstViolation.severity, .error)
        XCTAssertTrue(firstViolation.message.contains("UIView"))
    }

    func testNonSendableCaptureRuleIgnoresSendableTypes() async throws {
        // Create test source with Task capturing Sendable types (should not trigger)
        let source = """
        import Foundation

        struct SendableData: Sendable {
            let value: Int
            let message: String
        }

        func processSendable() {
            let data = SendableData(value: 42, message: "test")
            Task {
                processData(data) // Sendable capture, should not trigger
            }
        }

        func processData(_ data: SendableData) {
            print("Processing: \\(data.value)")
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = NonSendableCaptureRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify no violations (Sendable types should be safe)
        XCTAssertEqual(violations.count, 0)
    }

    func testNonSendableCaptureRuleDetectsDispatchQueueCapture() async throws {
        // Create test source with DispatchQueue capturing non-Sendable types
        let source = """
        import Foundation

        class DataManager {
            let mutableArray = NSMutableArray()

            func processOnBackground() {
                DispatchQueue.global().async {
                    self.mutableArray.add("value") // Non-Sendable capture
                }
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = NonSendableCaptureRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify violations
        XCTAssertGreaterThan(violations.count, 0)

        // Check violation
        let firstViolation = violations[0]
        XCTAssertEqual(firstViolation.ruleId, "non_sendable_capture")
        XCTAssertEqual(firstViolation.category, .concurrency)
        XCTAssertEqual(firstViolation.severity, .error)
        XCTAssertTrue(firstViolation.message.contains("non-Sendable"))
    }

    func testNonSendableCaptureRuleDifferentContexts() async throws {
        // Create test source with various async contexts
        let source = """
        import Foundation

        class UIComponent: UIView {
            let dataStore = NSMutableDictionary()

            func taskExample() {
                Task {
                    self.dataStore.setObject("test", forKey: "key")
                }
            }

            func asyncFunctionExample() async {
                Task {
                    self.updateLayer() // UIView is non-Sendable
                }
            }

            func dispatchExample() {
                DispatchQueue.main.async {
                    self.setNeedsDisplay() // UIView method
                }
            }

            func updateLayer() {
                // Update layer
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = NonSendableCaptureRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect multiple non-Sendable captures
        XCTAssertGreaterThan(violations.count, 0)

        // All violations should be non-Sendable capture violations
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "non_sendable_capture")
            XCTAssertEqual(violation.category, .concurrency)
            XCTAssertEqual(violation.severity, .error)
            XCTAssertTrue(violation.message.contains("non-Sendable"))
        }
    }

    func testNonSendableCaptureRuleLocationAccuracy() async throws {
        // Create test source with specific line numbers
        let source = """
        class TestClass: NSObject {
            func method() {
                Task {
                    self.doSomething() // Should be detected
                }
            }

            func doSomething() {
                // Implementation
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = NonSendableCaptureRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify location
        XCTAssertGreaterThan(violations.count, 0)
        let violation = violations[0]
        XCTAssertGreaterThan(violation.location.line, 0)
        XCTAssertTrue(violation.location.file.lastPathComponent.contains("test.swift"))
    }

    func testNonSendableCaptureRuleMultipleNonSendableTypes() async throws {
        // Create test source with multiple non-Sendable types
        let source = """
        import Foundation

        class ComplexClass {
            let array = NSMutableArray()
            let dictionary = NSMutableDictionary()
            let timer = Timer()

            func processMultiple() {
                Task {
                    self.array.add("item")
                    self.dictionary.setObject("value", forKey: "key")
                    self.timer.invalidate()
                }
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = NonSendableCaptureRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect multiple non-Sendable types
        XCTAssertGreaterThan(violations.count, 0)

        // All violations should have correct properties
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "non_sendable_capture")
            XCTAssertEqual(violation.category, .concurrency)
            XCTAssertEqual(violation.severity, .error)
        }
    }

    func testNonSendableCaptureRuleSeverity() async throws {
        // Verify that non-Sendable captures are errors
        let source = """
        class UnsafeClass: NSObject {
            func method() {
                Task {
                    self.performAction()
                }
            }

            func performAction() {
                // Action
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = NonSendableCaptureRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        XCTAssertGreaterThan(violations.count, 0)
        for violation in violations {
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