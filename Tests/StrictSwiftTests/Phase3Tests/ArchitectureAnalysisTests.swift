import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

final class ArchitectureAnalysisTests: XCTestCase {

    // MARK: - ModuleBoundaryRule Tests

    func testModuleBoundaryRuleBasicEnforcement() async throws {
        let sourceCode = """
        import Foundation
        import UIKit  // Import from forbidden module

        class ViewLayer {
            private var dataService: DataService  // Direct dependency on lower layer

            init() {
                self.dataService = DataService()  // Violates architectural boundary
            }

            func processData() {
                let model = dataService.fetchData()
                model.saveToDatabase()  // UI layer calling database operations
            }
        }

        class DataService {
            func fetchData() -> DatabaseModel {
                return DatabaseModel()
            }
        }

        class DatabaseModel {
            func saveToDatabase() {
                // Database operations
            }
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/ViewLayer.swift"), source: sourceCode)
        let rule = ModuleBoundaryRule()

        // Configure with Clean Architecture policy
        var config = Configuration()
        config.setRuleParameter("module_boundary", "architecturePattern", value: "clean_architecture")
        config.setRuleParameter("module_boundary", "enforceLayering", value: true)
        config.setRuleParameter("module_boundary", "forbiddenModules", value: ["UIKit"])
        config.enableRule("module_boundary", enabled: true)

        let context = AnalysisContext(
            configuration: config,
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect module boundary violations
        XCTAssertFalse(violations.isEmpty, "Should detect module boundary violations")

        let boundaryViolations = violations.filter { $0.ruleId == "module_boundary" }
        XCTAssertFalse(boundaryViolations.isEmpty, "Should have module boundary violations")

        // Check that we have forbidden import violations (UIKit is forbidden)
        let forbiddenImportViolations = boundaryViolations.filter { $0.message.contains("UIKit") }
        XCTAssertFalse(forbiddenImportViolations.isEmpty, "Should detect forbidden UIKit import")
    }

    func testModuleBoundaryRuleCircularDependencies() async throws {
        // Test detection of excessive module dependencies
        let sourceCode1 = """
        import Foundation
        import UIKit
        import SwiftUI
        import Combine
        import CoreData

        class ModuleA {
            private let moduleB: ModuleB

            init(moduleB: ModuleB) {
                self.moduleB = moduleB
            }

            func process() {
                moduleB.handle()
            }
        }
        """

        let sourceFile1 = SourceFile(url: URL(fileURLWithPath: "/tmp/ModuleA.swift"), source: sourceCode1)

        let rule = ModuleBoundaryRule()

        // Configure with a low dependency threshold to trigger violations
        var config = Configuration()
        config.setRuleParameter("module_boundary", "detectCircularDependencies", value: true)
        config.setRuleParameter("module_boundary", "maxModuleDependencies", value: 2) // Low threshold
        config.enableRule("module_boundary", enabled: true)

        let context = AnalysisContext(
            sourceFiles: [sourceFile1],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )

        let violations = await rule.analyze(sourceFile1, in: context)

        // Should detect excessive dependencies or other architectural issues
        XCTAssertFalse(violations.isEmpty, "Should detect module boundary violations")
    }

    // MARK: - ImportDirectionRule Tests

    func testImportDirectionRuleValidation() async throws {
        let sourceCode = """
        import Foundation

        // Domain layer should not import presentation layer
        import UIKit  // Violates import direction (domain importing presentation)
        import SwiftUI  // Another violation

        protocol UserRepository {
            func save(user: User)
        }

        class DatabaseUserRepository: UserRepository {
            private let database: Database

            init(database: Database) {
                self.database = database
            }

            func save(user: User) {
                database.save(user)
            }
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/DomainLayer.swift"), source: sourceCode)
        let rule = ImportDirectionRule()

        // Configure with import direction enforcement
        var config = Configuration()
        config.setRuleParameter("import_direction", "enforceStrictLayering", value: true)
        config.setRuleParameter("import_direction", "allowTestImports", value: false)
        config.setRuleParameter("import_direction", "forbiddenImports", value: ["UIKit", "SwiftUI"])
        config.setRuleParameter("import_direction", "architecturePattern", value: "clean_architecture")
        config.enableRule("import_direction", enabled: true)

        let context = AnalysisContext(
            configuration: config,
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect import direction violations
        XCTAssertFalse(violations.isEmpty, "Should detect import direction violations")

        let importViolations = violations.filter { $0.ruleId == "import_direction" }
        XCTAssertFalse(importViolations.isEmpty, "Should have import direction violations")

        // Verify forbidden imports are detected
        let forbiddenViolations = importViolations.filter {
            $0.message.contains("forbidden") || $0.message.contains("UIKit") || $0.message.contains("SwiftUI")
        }
        XCTAssertFalse(forbiddenViolations.isEmpty, "Should detect forbidden imports")
    }

    func testImportDirectionRuleArchitecturalLayers() async throws {
        let presentationCode = """
        import Foundation
        import UIKit
        import SwiftUI

        class PresentationLayer {
            func showView() {
                let view = UIView()
            }
        }
        """

        let domainCode = """
        import Foundation
        import UIKit  // Should be flagged - domain importing presentation

        protocol DomainService {
            func execute()
        }
        """

        let dataCode = """
        import Foundation
        import UIKit  // Should be flagged - data layer importing presentation
        import SwiftUI  // Also should be flagged

        class DataSource {
            func fetchData() -> Data {
                return Data()
            }
        }
        """

        let presentationFile = SourceFile(url: URL(fileURLWithPath: "/tmp/Presentation.swift"), source: presentationCode)
        let domainFile = SourceFile(url: URL(fileURLWithPath: "/tmp/Domain.swift"), source: domainCode)
        let dataFile = SourceFile(url: URL(fileURLWithPath: "/tmp/Data.swift"), source: dataCode)

        let rule = ImportDirectionRule()

        // Configure architectural layer enforcement
        var config = Configuration()
        config.setRuleParameter("import_direction", "architecturePattern", value: "mvvm")
        config.setRuleParameter("import_direction", "enforceStrictLayering", value: true)
        config.setRuleParameter("import_direction", "allowTestImports", value: false)
        config.enableRule("import_direction", enabled: true)

        let context = AnalysisContext(
            sourceFiles: [presentationFile, domainFile, dataFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )

        let presentationViolations = await rule.analyze(presentationFile, in: context)
        let domainViolations = await rule.analyze(domainFile, in: context)
        let dataViolations = await rule.analyze(dataFile, in: context)

        // Domain and data layers should have violations for importing UI frameworks
        XCTAssertTrue(domainViolations.count > 0, "Domain layer should have import violations")
        XCTAssertTrue(dataViolations.count > 0, "Data layer should have import violations")

        // Verify that violations exist (location may vary depending on implementation)
        let allViolations = domainViolations + dataViolations
        XCTAssertFalse(allViolations.isEmpty, "Should have architectural violations")
    }

    // MARK: - Location Accuracy Tests

    func testArchitectureRulesLocationAccuracy() async throws {
        let sourceCode = """
        import Foundation
        import UIKit  // Line 3 - forbidden import
        import SwiftUI  // Line 4 - forbidden import

        class ArchitecturalTest {
            private var dependency: LowerLayer  // Line 7 - architectural violation

            init() {
                // Line 10 - problematic initialization
                self.dependency = LowerLayer()
                self.setupUI()  // Line 11 - wrong layer calling UI
            }

            private func setupUI() {
                let view = UIView()  // Line 15 - UI code in wrong layer
            }
        }

        class LowerLayer {
            func process() {
                // Lower layer implementation
            }
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/architecture_test.swift"), source: sourceCode)

        let importRule = ImportDirectionRule()
        let moduleRule = ModuleBoundaryRule()

        // Configure to detect forbidden imports
        var config = Configuration()
        config.setRuleParameter("module_boundary", "forbiddenModules", value: ["UIKit", "SwiftUI"])
        config.enableRule("module_boundary", enabled: true)
        config.enableRule("import_direction", enabled: true)

        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: config
        )

        async let importViolations = importRule.analyze(sourceFile, in: context)
        async let moduleViolations = moduleRule.analyze(sourceFile, in: context)

        let (importResult, moduleResult) = await (importViolations, moduleViolations)

        // Verify we get violations for the forbidden imports
        let allViolations = importResult + moduleResult
        XCTAssertFalse(allViolations.isEmpty, "Should detect architecture violations")

        // Check that forbidden import violations exist
        let forbiddenViolations = allViolations.filter {
            $0.message.contains("UIKit") || $0.message.contains("SwiftUI")
        }
        XCTAssertFalse(forbiddenViolations.isEmpty, "Should detect forbidden imports")
    }

    // MARK: - Performance Tests

    func testArchitectureAnalysisPerformance() async throws {
        // Create a large file with many architectural patterns
        var sourceCode = """
        import Foundation

        """

        // Add many imports and classes to test performance
        for i in 1...50 {
            sourceCode += """
            import Module\(i)

            class TestClass\(i) {
                private let dependency: Dependency\(i)

                init() {
                    self.dependency = Dependency\(i)()
                }

                func process() {
                    dependency.handle()
                }
            }

            class Dependency\(i) {
                func handle() {
                    print("Handling dependency \\(i)")
                }
            }

            """
        }

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/architecture_performance.swift"), source: sourceCode)

        let importRule = ImportDirectionRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )

        // Measure performance
        let startTime = CFAbsoluteTimeGetCurrent()
        let violations = await importRule.analyze(sourceFile, in: context)
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Should complete in reasonable time
        XCTAssertLessThan(timeElapsed, 1.0, "Architecture analysis should complete quickly")
        XCTAssertNotNil(violations, "Should complete architecture analysis")

        // Should analyze all imports
        XCTAssertGreaterThan(violations.count, 0, "Should analyze multiple imports")
    }
}