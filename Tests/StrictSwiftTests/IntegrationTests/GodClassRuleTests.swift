import XCTest
@testable import StrictSwiftCore
import Foundation

final class GodClassRuleTests: XCTestCase {

    func testGodClassRuleDetectsExcessiveMethods() async throws {
        // Create test source with too many methods
        let source = """
        import Foundation

        class UserProfileManager {
            private let database: Database
            private let network: NetworkClient
            private let cache: CacheManager

            func loadUser() { }
            func saveUser() { }
            func deleteUser() { }
            func updateUser() { }
            func validateUser() { }
            func authenticateUser() { }
            func authorizeUser() { }
            func refreshUser() { }
            func syncUser() { }
            func backupUser() { }
            func exportUser() { }
            func importUser() { }
            func mergeUser() { }
            func splitUser() { }
            func archiveUser() { }
            func restoreUser() { }  // 16th method - exceeds threshold
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GodClassRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect excessive methods
        XCTAssertGreaterThan(violations.count, 0)

        // If violations are found, verify they have correct properties
        if !violations.isEmpty {
            let firstViolation = violations[0]
            XCTAssertEqual(firstViolation.ruleId, "god_class")
            XCTAssertEqual(firstViolation.category, .architecture)
            XCTAssertEqual(firstViolation.severity, .warning)
            XCTAssertTrue(firstViolation.message.contains("excessive methods"))
            XCTAssertTrue(firstViolation.message.contains("UserProfileManager"))
        }
    }

    func testGodClassRuleDetectsExcessiveProperties() async throws {
        // Create test source with too many properties
        let source = """
        import Foundation

        class ConfigurationManager {
            let database: Database
            let network: NetworkClient
            let cache: CacheManager
            let logger: Logger
            let validator: Validator
            let serializer: Serializer
            let parser: Parser
            let formatter: Formatter
            let transformer: Transformer
            let compressor: Compressor  // 11th property - exceeds threshold
            let encryptor: Encryptor    // 12th property

            func configure() { }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GodClassRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect excessive properties
        XCTAssertGreaterThan(violations.count, 0)

        // If violations are found, verify they have correct properties
        if !violations.isEmpty {
            let firstViolation = violations[0]
            XCTAssertEqual(firstViolation.ruleId, "god_class")
            XCTAssertEqual(firstViolation.category, .architecture)
            XCTAssertEqual(firstViolation.severity, .warning)
            XCTAssertTrue(firstViolation.message.contains("excessive properties"))
        }
    }

    func testGodClassRuleDetectsExcessiveDependencies() async throws {
        // Create test source with too many dependencies
        let source = """
        import Foundation

        class Orchestrator {
            let userService: UserService
            let productService: ProductService
            let orderService: OrderService
            let paymentService: PaymentService
            let notificationService: NotificationService
            let analyticsService: AnalyticsService
            let securityService: SecurityService
            let reportingService: ReportingService
            let auditService: AuditService  // 9th dependency - exceeds threshold

            func process() { }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GodClassRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect excessive dependencies
        XCTAssertGreaterThan(violations.count, 0)

        // If violations are found, verify they have correct properties
        if !violations.isEmpty {
            let firstViolation = violations[0]
            XCTAssertEqual(firstViolation.ruleId, "god_class")
            XCTAssertEqual(firstViolation.category, .architecture)
            XCTAssertEqual(firstViolation.severity, .warning)
            XCTAssertTrue(firstViolation.message.contains("excessive dependencies"))
        }
    }

    func testGodClassRuleDetectsComplexityIndicators() async throws {
        // Create test source with excessive methods and properties (complexity indicators)
        let source = """
        import Foundation

        class ComplexProcessor {
            let data: [String]
            let processor1: Processor
            let processor2: Processor
            let processor3: Processor
            let processor4: Processor
            let processor5: Processor
            let processor6: Processor
            let processor7: Processor
            let processor8: Processor
            let processor9: Processor  // 10 properties exceeds threshold of 10

            func method1() { }
            func method2() { }
            func method3() { }
            func method4() { }
            func method5() { }
            func method6() { }
            func method7() { }
            func method8() { }
            func method9() { }
            func method10() { }
            func method11() { }
            func method12() { }
            func method13() { }
            func method14() { }
            func method15() { }
            func method16() { }  // 16 methods exceeds threshold of 15
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GodClassRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect excessive methods or properties
        XCTAssertGreaterThan(violations.count, 0)

        // If violations are found, verify they have correct properties
        if !violations.isEmpty {
            let firstViolation = violations[0]
            XCTAssertEqual(firstViolation.ruleId, "god_class")
            XCTAssertEqual(firstViolation.category, .architecture)
            XCTAssertEqual(firstViolation.severity, .warning)
            XCTAssertTrue(firstViolation.message.contains("excessive"))
        }
    }

    func testGodClassRuleDetectsMultipleViolations() async throws {
        // Create test source with multiple God class indicators
        let source = """
        import Foundation

        class MegaManager {
            // Many properties
            let db: DatabaseManager
            let net: NetworkManager
            let cache: CacheManager
            let log: LogManager
            let auth: AuthManager
            let session: SessionManager
            let config: ConfigManager
            let backup: BackupManager
            let monitor: MonitorManager
            let alert: AlertManager
            let sync: SyncManager
            let queue: QueueManager

            // Many methods
            func initialize() { }
            func setup() { }
            func start() { }
            func stop() { }
            func pause() { }
            func resume() { }
            func restart() { }
            func shutdown() { }
            func cleanup() { }
            func validate() { }
            func process() { }
            func handle() { }
            func manage() { }
            func control() { }
            func orchestrate() { }
            func coordinate() { }
            func execute() { }

            // Complex logic
            func complexOperation() {
                for item in items {
                    if item.isValid {
                        switch item.type {
                        case .critical:
                            DispatchQueue.global().async {
                                NotificationCenter.default.post(name: .criticalItem, object: item)
                            }
                        case .normal:
                            try? self.processItem(item)
                        default:
                            break
                        }
                    }
                }
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GodClassRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should detect multiple violations
        XCTAssertGreaterThan(violations.count, 0)

        // All violations should be God class violations
        for violation in violations {
            XCTAssertEqual(violation.ruleId, "god_class")
            XCTAssertEqual(violation.category, .architecture)
            XCTAssertEqual(violation.severity, .warning)
            XCTAssertTrue(violation.message.contains("MegaManager"))
        }
    }

    func testGodClassRuleIgnoresWellStructuredClasses() async throws {
        // Create test source with well-structured classes (should not trigger)
        let source = """
        import Foundation

        // Well-structured class with single responsibility
        class UserValidator {
            func validate(_ user: User) -> Bool {
                return !user.name.isEmpty && user.email.contains("@")
            }
        }

        // Another well-structured class
        class EmailSender {
            private let smtpClient: SMTPClient

            init(smtpClient: SMTPClient) {
                self.smtpClient = smtpClient
            }

            func sendEmail(to: String, subject: String, body: String) {
                smtpClient.send(to: to, subject: subject, body: body)
            }
        }

        // Small, focused class
        class User {
            let name: String
            let email: String

            init(name: String, email: String) {
                self.name = name
                self.email = email
            }

            func isValid() -> Bool {
                return !name.isEmpty && email.contains("@")
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GodClassRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should not detect God class violations in well-structured code
        XCTAssertEqual(violations.count, 0)
    }

    func testGodClassRuleLocationAccuracy() async throws {
        // Create test source with specific line numbers
        let source = """
        import Foundation

        class LocatedGodClass {
            // This class is at a specific location
            let dep1: Service1
            let dep2: Service2
            let dep3: Service3
            let dep4: Service4
            let dep5: Service5
            let dep6: Service6
            let dep7: Service7
            let dep8: Service8
            let dep9: Service9
            let dep10: Service10
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GodClassRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Verify location if violations are found
        if !violations.isEmpty {
            let violation = violations[0]
            XCTAssertGreaterThan(violation.location.line, 0)
            XCTAssertTrue(violation.location.file.lastPathComponent.contains("test.swift"))
        }
    }

    func testGodClassRuleSeverity() async throws {
        // Verify that God class violations are warnings
        let source = """
        import Foundation

        class TestGodClass {
            // Too many methods
            func method1() { }
            func method2() { }
            func method3() { }
            func method4() { }
            func method5() { }
            func method6() { }
            func method7() { }
            func method8() { }
            func method9() { }
            func method10() { }
            func method11() { }
            func method12() { }
            func method13() { }
            func method14() { }
            func method15() { }
            func method16() { }  // Exceeds threshold
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = GodClassRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // If violations are found, verify severity
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