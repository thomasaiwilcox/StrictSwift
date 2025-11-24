import XCTest
@testable import StrictSwiftCore

final class TypeResolverTests: XCTestCase {

    func testTypeResolverClassResolution() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        import Foundation

        public class UserService {
            public let id: String
            private var cache: [String: Any]
            internal static let shared: UserService

            public init(id: String) {
                self.id = id
                self.cache = [:]
            }

            public func fetchUser() -> User? {
                return User(id: id)
            }

            private func validateUser(_ user: User) -> Bool {
                return !user.id.isEmpty
            }

            static func create() -> UserService {
                return UserService(id: "default")
            }
        }

        struct User {
            let id: String
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        let userServiceType = resolver.type(named: "UserService")
        XCTAssertNotNil(userServiceType)
        XCTAssertEqual(userServiceType?.name, "UserService")
        XCTAssertEqual(userServiceType?.kind, .class)
        XCTAssertTrue(userServiceType?.isPublic ?? false)
        XCTAssertEqual(userServiceType?.properties.count, 3)
        XCTAssertEqual(userServiceType?.methods.count, 3)

        // Check properties
        let idProperty = userServiceType?.properties.first { $0.name == "id" }
        XCTAssertNotNil(idProperty)
        XCTAssertEqual(idProperty?.type, "String")
        XCTAssertFalse(idProperty?.isMutable ?? true)

        let cacheProperty = userServiceType?.properties.first { $0.name == "cache" }
        XCTAssertNotNil(cacheProperty)
        XCTAssertEqual(cacheProperty?.type, "[String: Any]")
        XCTAssertTrue(cacheProperty?.isMutable ?? false)
        XCTAssertTrue(cacheProperty?.isPrivate ?? false)

        // Check methods
        let fetchMethod = userServiceType?.methods.first { $0.name == "fetchUser" }
        XCTAssertNotNil(fetchMethod)
        XCTAssertEqual(fetchMethod?.returnType, "User?")
        XCTAssertTrue(fetchMethod?.isPublic ?? false)

        let validateMethod = userServiceType?.methods.first { $0.name == "validateUser" }
        XCTAssertNotNil(validateMethod)
        XCTAssertTrue(validateMethod?.isPrivate ?? false)
    }

    func testTypeResolverStructResolution() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        struct UserProfile {
            let name: String
            var email: String
            private var settings: [String: String]

            func updateEmail(_ newEmail: String) {
                self.email = newEmail
            }

            internal func validateEmail() -> Bool {
                return email.contains("@")
            }
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        let profileType = resolver.type(named: "UserProfile")
        XCTAssertNotNil(profileType)
        XCTAssertEqual(profileType?.name, "UserProfile")
        XCTAssertEqual(profileType?.kind, .struct)
        XCTAssertEqual(profileType?.properties.count, 3)
        XCTAssertEqual(profileType?.methods.count, 2)
    }

    func testTypeResolverProtocolResolution() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        protocol UserRepository {
            func fetchUser(id: String) -> User?
            func saveUser(_ user: User) throws
        }

        protocol NetworkService {
            func makeRequest(url: URL) async throws -> Data
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        let repositoryProtocol = resolver.type(named: "UserRepository")
        XCTAssertNotNil(repositoryProtocol)
        XCTAssertEqual(repositoryProtocol?.name, "UserRepository")
        XCTAssertEqual(repositoryProtocol?.kind, .protocol)
        XCTAssertEqual(repositoryProtocol?.methods.count, 2)

        let networkProtocol = resolver.type(named: "NetworkService")
        XCTAssertNotNil(networkProtocol)
        XCTAssertEqual(networkProtocol?.name, "NetworkService")
        XCTAssertEqual(networkProtocol?.kind, .protocol)
        XCTAssertEqual(networkProtocol?.methods.count, 1)
    }

    func testTypeResolverEnumResolution() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        enum UserRole: String, CaseIterable {
            case admin
            case user
            case guest

            var isAdmin: Bool {
                return self == .admin
            }

            static func defaultRole() -> UserRole {
                return .user
            }
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        let roleEnum = resolver.type(named: "UserRole")
        XCTAssertNotNil(roleEnum)
        XCTAssertEqual(roleEnum?.name, "UserRole")
        XCTAssertEqual(roleEnum?.kind, .enum)
        XCTAssertEqual(roleEnum?.methods.count, 2)
    }

    func testTypeResolverInheritanceChain() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        class BaseClass {
            let baseProperty: String
            init(baseProperty: String) {
                self.baseProperty = baseProperty
            }
        }

        class DerivedClass: BaseClass {
            let derivedProperty: Int
            init(derivedProperty: Int) {
                self.derivedProperty = derivedProperty
                super.init(baseProperty: "base")
            }
        }

        class FinalClass: DerivedClass {
            let finalProperty: Bool
            init(finalProperty: Bool) {
                self.finalProperty = finalProperty
                super.init(derivedProperty: 42)
            }
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        let finalClass = resolver.type(named: "FinalClass")
        XCTAssertNotNil(finalClass)
        XCTAssertEqual(finalClass?.inheritanceChain.count, 2)
        XCTAssertTrue(finalClass?.inheritanceChain.contains("DerivedClass") ?? false)
        XCTAssertTrue(finalClass?.inheritanceChain.contains("BaseClass") ?? false)

        let derivedClass = resolver.type(named: "DerivedClass")
        XCTAssertNotNil(derivedClass)
        XCTAssertEqual(derivedClass?.inheritanceChain.count, 1)
        XCTAssertTrue(derivedClass?.inheritanceChain.contains("BaseClass") ?? false)
    }

    func testTypeResolverProtocolConformance() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        protocol Identifiable {
            var id: String { get }
        }

        protocol Codable: Identifiable {
            func encode() throws -> Data
        }

        class User: Codable, Identifiable {
            let id: String
            let name: String

            init(id: String, name: String) {
                self.id = id
                self.name = name
            }

            func encode() throws -> Data {
                return "user_data".data(using: .utf8) ?? Data()
            }
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        let userType = resolver.type(named: "User")
        XCTAssertNotNil(userType)
        XCTAssertEqual(userType?.conformances.count, 2)
        XCTAssertTrue(userType?.conformances.contains("Codable") ?? false)
        XCTAssertTrue(userType?.conformances.contains("Identifiable") ?? false)
    }

    func testTypeResolverTypeCompatibility() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        class BaseModel: Identifiable {
            let id: String
        }

        protocol Identifiable {
            var id: String { get }
        }

        class UserModel: BaseModel {
            let name: String
        }

        class ExternalModel: Identifiable {
            let id: String
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        // Test compatibility between different types
        XCTAssertTrue(resolver.areTypesCompatible("BaseModel", "BaseModel")) // Same type
        XCTAssertTrue(resolver.areTypesCompatible("UserModel", "BaseModel")) // Inheritance
        XCTAssertFalse(resolver.areTypesCompatible("BaseModel", "UserModel")) // Wrong direction
        XCTAssertTrue(resolver.areTypesCompatible("UserModel", "Identifiable")) // Protocol conformance
        XCTAssertFalse(resolver.areTypesCompatible("BaseModel", "NonExistent")) // One type doesn't exist
    }

    func testTypeResolverTypeComplexity() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        class ComplexClass {
            // Many properties
            public let property1: String
            public let property2: Int
            public let property3: Double
            public let property4: Bool
            public let property5: Date
            public let property6: Data
            public let property7: URL
            public let property8: [String]
            public let property9: [Int: String]
            public let property10: Set<String>

            // Many methods
            public func method1() { }
            public func method2() { }
            public func method3() { }
            public func method4() { }
            public func method5() { }
            public func method6() { }
            public func method7() { }
            public func method8() { }
            public func method9() { }
            public func method10() { }
            public func method11() { }
            public func method12() { }
            public func method13() { }
            public func method14() { }
            public func method15() { }

            // Protocol conformances
            init() {
                property1 = ""
                property2 = 0
                property3 = 0.0
                property4 = false
                property5 = Date()
                property6 = Data()
                property7 = URL(fileURLWithPath: "/")
                property8 = []
                property9 = [:]
                property10 = Set()
            }
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        let complexType = resolver.type(named: "ComplexClass")
        XCTAssertNotNil(complexType)

        let complexity = resolver.complexity(of: "ComplexClass")
        XCTAssertNotNil(complexity)

        // Check complexity metrics
        XCTAssertEqual(complexity?.propertyCount, 10)
        XCTAssertEqual(complexity?.methodCount, 15)
        XCTAssertEqual(complexity?.complexityScore, 10 * 2 + 15 + 10) // 45
        XCTAssertTrue(complexity?.isGodClass ?? false)
    }

    func testTypeResolverConformingToProtocol() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        protocol Repository {
            func save() throws
        }

        protocol Cache {
            func invalidate()
        }

        class UserRepository: Repository, Cache {
            func save() throws { }
            func invalidate() { }
        }

        class MemoryCache: Cache {
            func invalidate() { }
        }

        class DatabaseRepository: Repository {
            func save() throws { }
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        // Find types conforming to Repository protocol
        let repositoryConformingTypes = resolver.typesConforming(to: "Repository")
        XCTAssertEqual(repositoryConformingTypes.count, 2)
        XCTAssertTrue(repositoryConformingTypes.contains { $0.name == "UserRepository" })
        XCTAssertTrue(repositoryConformingTypes.contains { $0.name == "DatabaseRepository" })

        // Find types conforming to Cache protocol
        let cacheConformingTypes = resolver.typesConforming(to: "Cache")
        XCTAssertEqual(cacheConformingTypes.count, 2)
        XCTAssertTrue(cacheConformingTypes.contains { $0.name == "UserRepository" })
        XCTAssertTrue(cacheConformingTypes.contains { $0.name == "MemoryCache" })
    }

    func testTypeResolverInheritingFromClass() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        class UIViewController {
            let view: UIView
        }

        class UITableViewController: UIViewController {
            let tableView: UITableView
        }

        class CustomTableViewController: UITableViewController {
            let customView: CustomView
        }

        class BaseController: UIViewController {
            func viewDidLoad() { }
        }

        class SpecificController: BaseController {
            func setupUI() { }
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        // Find types inheriting from UIViewController
        let viewControllerSubclasses = resolver.typesInheriting(from: "UIViewController")
        XCTAssertEqual(viewControllerSubclasses.count, 3)
        XCTAssertTrue(viewControllerSubclasses.contains { $0.name == "UITableViewController" })
        XCTAssertTrue(viewControllerSubclasses.contains { $0.name == "CustomTableViewController" })
        XCTAssertTrue(viewControllerSubclasses.contains { $0.name == "BaseController" })

        // Find types inheriting from UITableViewController
        let tableViewControllerSubclasses = resolver.typesInheriting(from: "UITableViewController")
        XCTAssertEqual(tableViewControllerSubclasses.count, 1)
        XCTAssertTrue(tableViewControllerSubclasses.contains { $0.name == "CustomTableViewController" })
    }

    func testTypeResolverAccessLevels() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        public class PublicClass {
            public let publicProperty: String
            private let privateProperty: Int
            internal let internalProperty: Bool
            fileprivate let filePrivateProperty: Double
        }

        private struct PrivateStruct {
            public let accessibleProperty: String
        }

        internal enum InternalEnum {
            case case1
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        let publicType = resolver.type(named: "PublicClass")
        XCTAssertNotNil(publicType)
        XCTAssertTrue(publicType?.isPublic ?? false)

        let publicProperties = publicType?.properties.filter {
            $0.accessLevel == .public || $0.accessLevel == .open
        }
        XCTAssertEqual(publicProperties?.count, 1)

        let privateProperties = publicType?.properties.filter { $0.accessLevel == .private }
        XCTAssertEqual(privateProperties?.count, 1)
    }

    func testTypeResolverAsyncMethods() throws {
        let resolver = TypeResolver()
        let sourceFile = try createTestSourceFile(content: """
        class AsyncService {
            public func fetchData() async throws -> Data {
                return Data()
            }

            public func processValue<T>(_ value: T) async -> T {
                return value
            }

            private func handleError(_ error: Error) async {
                // Handle error
            }
        }
        """)

        resolver.resolveTypes(from: [sourceFile])

        let asyncService = resolver.type(named: "AsyncService")
        XCTAssertNotNil(asyncService)

        // Check async methods
        let fetchDataMethod = asyncService?.methods.first { $0.name == "fetchData" }
        XCTAssertNotNil(fetchDataMethod)
        XCTAssertTrue(fetchDataMethod?.isAsync ?? false)
        XCTAssertTrue(fetchDataMethod?.throwsError ?? false)

        let processValueMethod = asyncService?.methods.first { $0.name == "processValue" }
        XCTAssertNotNil(processValueMethod)
        XCTAssertTrue(processValueMethod?.isAsync ?? false)
        XCTAssertFalse(processValueMethod?.throwsError ?? true)
    }

    // MARK: - Helper Methods

    private func createTestSourceFile(content: String) throws -> SourceFile {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString).swift")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Register cleanup
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }

        return try SourceFile(url: fileURL)
    }
}