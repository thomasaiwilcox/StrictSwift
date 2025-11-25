import XCTest
@testable import StrictSwiftCore
import Foundation

final class GlobalStateRuleTests: XCTestCase {

    func testGlobalStateRuleDetectsGlobalVariables() async throws {
        // Create test source with global mutable variables
        let source = """
        import Foundation

        // Global mutable variables should be flagged
        var globalCounter: Int = 0
        var sharedState: String = ""

        class UserManager {
            func updateUser() {
                globalCounter += 1  // Accessing global state
            }
        }

        // Constants should not be flagged
        let globalConstant: Int = 42
        static let staticConstant: String = "fixed"
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GlobalStateRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect global mutable variables
        XCTAssertGreaterThan(violations.count, 0)

        // Verify violations have correct properties
        let globalVarViolations = violations.filter { $0.message.contains("global") }
        XCTAssertGreaterThan(globalVarViolations.count, 0)

        for violation in globalVarViolations {
            XCTAssertEqual(violation.ruleId, "global_state")
            XCTAssertEqual(violation.category, .architecture)
            XCTAssertEqual(violation.severity, .warning)
        }
    }

    func testGlobalStateRuleDetectsPublicStaticVariables() async throws {
        // Create test source with public static variables
        let source = """
        import Foundation

        class ConfigurationManager {
            // Public static mutable variables should be flagged
            static var sharedConfig: ConfigurationManager?
            public static var currentEnvironment: String = "development"
            internal static var debugMode: Bool = false

            // Private static variables should be allowed
            private static var internalState: String = ""
            fileprivate static var tempData: [String] = []
        }

        enum Settings {
            // Public static case
            static var userPreferences: [String: Any] = [:]

            // Private static case (should be allowed)
            private static var internalSettings: [String: Any] = [:]
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GlobalStateRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect public static variables but not private ones
        XCTAssertGreaterThan(violations.count, 0)

        // All violations should be global state violations
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "global_state")
            XCTAssertEqual(violation.category, .architecture)
            XCTAssertEqual(violation.severity, .warning)
        }
    }

    func testGlobalStateRuleDetectsSingletonUsage() async throws {
        // Create test source with singleton usage
        let source = """
        import Foundation
        import UIKit

        class DataPersistenceManager {
            func saveData(_ data: Data) {
                // Using singletons that contain global state
                UserDefaults.standard.set(data, forKey: "savedData")
                URLCache.shared.storeCachedResponse(cachedResponse, for: request)
            }

            func clearCache() {
                URLCache.shared.removeAllCachedResponses()
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }

            func showNotification() {
                NotificationCenter.default.post(name: .dataUpdated, object: nil)
            }
        }

        class NetworkManager {
            func fetchURL(_ url: URL) {
                URLSession.shared.dataTask(with: url) { data, response, error in
                    // Network request using shared session
                }
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GlobalStateRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect singleton usage
        XCTAssertGreaterThan(violations.count, 0)

        // Should detect various singleton patterns
        let singletonViolations = violations.filter { violation in
            violation.message.contains("UserDefaults") ||
            violation.message.contains("URLCache") ||
            violation.message.contains("HTTPCookieStorage") ||
            violation.message.contains("NotificationCenter") ||
            violation.message.contains("URLSession")
        }

        XCTAssertGreaterThan(singletonViolations.count, 0)
    }

    func testGlobalStateRuleIgnoresConstants() async throws {
        // Create test source with constants (should not trigger violations)
        let source = """
        import Foundation

        // Global constants should not be flagged
        let globalConstant: Int = 42
        static let staticConstant: String = "fixed"
        private static let privateConstant: Bool = true

        class Configuration {
            // Class constants
            static let apiKey: String = "12345"
            static let maxRetries: Int = 3
            private static let debugMode: Bool = false
        }

        enum AppConstants {
            static let version: String = "1.0.0"
            static let bundleIdentifier: String = "com.example.app"
        }

        // Function parameters with 'var' (should not be flagged)
        func process(var value: Int) -> Int {
            return value * 2
        }

        // Guard statements with 'var' (should not be flagged)
        func validate(data: String?) -> Bool {
            guard var validData = data else { return false }
            return !validData.isEmpty
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GlobalStateRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should not detect violations in constant definitions
        XCTAssertEqual(violations.count, 0)
    }

    func testGlobalStateRuleIgnoresPrivateStaticVariables() async throws {
        // Create test source with private static variables (should not trigger violations)
        let source = """
        import Foundation

        class InternalState {
            // Private static variables should be allowed
            private static var counter: Int = 0
            fileprivate static var data: [String] = []

            private class var classVar: String = ""

            func incrementCounter() {
                InternalState.counter += 1
            }
        }

        struct Cache {
            // File-private static variables should be allowed
            fileprivate static var cache: [String: Any] = [:]
            private static var maxSize: Int = 100
        }

        // Local static variables in functions should be allowed
        func createManager() -> Manager {
            private static var instance: Manager?
            // This is actually not valid Swift syntax, but testing the pattern
            return Manager()
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GlobalStateRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should not detect violations for private static variables
        XCTAssertEqual(violations.count, 0)
    }

    func testGlobalStateRuleDetectsComplexGlobalStateUsage() async throws {
        // Create test source with complex global state usage patterns
        let source = """
        import Foundation
        import UIKit

        // Global mutable dictionary
        var globalCache: [String: Any] = [:]

        class AppCoordinator {
            var window: UIWindow?

            func start() {
                // Multiple global state accesses
                globalCache["appStarted"] = Date()
                UserDefaults.standard.set(true, forKey: "appLaunched")
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleNotification),
                    name: UIApplication.didBecomeActiveNotification,
                    object: nil
                )
            }

            func clearAllData() {
                globalCache.removeAll()
                URLCache.shared.removeAllCachedResponses()
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        // Global mutable state in extensions
        extension String {
            static var sharedFormatter: DateFormatter = {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter
            }()
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GlobalStateRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect multiple global state violations
        XCTAssertGreaterThan(violations.count, 0)

        // All violations should be global state violations
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "global_state")
            XCTAssertEqual(violation.category, .architecture)
            XCTAssertEqual(violation.severity, .warning)
        }
    }

    func testGlobalStateRuleLocationAccuracy() async throws {
        // Create test source with specific line numbers
        let source = """
        import Foundation

        // Line 5 - global variable
        var globalState: Int = 0

        class TestClass {
            func test() {
                // Line 11 - singleton usage
                UserDefaults.standard.set("test", forKey: "key")
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GlobalStateRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify location accuracy
        if !violations.isEmpty {
            for violation in violations {
                XCTAssertGreaterThan(violation.location.line, 0)
                XCTAssertTrue(violation.location.file.lastPathComponent.contains("test.swift"))
            }
        }
    }

    func testGlobalStateRuleSeverity() async throws {
        // Verify that global state violations are warnings
        let source = """
        import Foundation

        var globalVariable: String = "test"
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GlobalStateRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // All violations should be warnings
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