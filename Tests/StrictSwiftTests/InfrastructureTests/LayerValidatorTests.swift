import XCTest
@testable import StrictSwiftCore

final class LayerValidatorTests: XCTestCase {

    func testCleanArchitecturePolicyValidation() throws {
        let policy = LayerValidator.cleanArchitecturePolicy()
        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        // Create nodes in different layers
        let entitiesNode = DependencyNode(name: "UserEntity", type: .class, filePath: "/entities/UserEntity.swift")
        let useCaseNode = DependencyNode(name: "CreateUserUseCase", type: .class, filePath: "/usecases/CreateUserUseCase.swift")
        let presenterNode = DependencyNode(name: "UserPresenter", type: .class, filePath: "/presenters/UserPresenter.swift")
        let uiNode = DependencyNode(name: "UserViewController", type: .class, filePath: "/ui/UserViewController.swift")

        graph.addNode(entitiesNode)
        graph.addNode(useCaseNode)
        graph.addNode(presenterNode)
        graph.addNode(uiNode)

        // Add valid dependencies (according to Clean Architecture)
        graph.addDependency(Dependency(from: "CreateUserUseCase", to: "UserEntity", type: .composition, strength: .strong))
        graph.addDependency(Dependency(from: "UserPresenter", to: "CreateUserUseCase", type: .composition, strength: .strong))
        graph.addDependency(Dependency(from: "UserPresenter", to: "UserEntity", type: .typeReference, strength: .medium))

        // Validate
        let violations = validator.validate(graph)

        // Should have no violations for valid dependencies
        XCTAssertEqual(violations.count, 0)
    }

    func testCleanArchitecturePolicyViolations() throws {
        let policy = LayerValidator.cleanArchitecturePolicy()
        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        // Create nodes in different layers
        let entitiesNode = DependencyNode(name: "UserEntity", type: .class, filePath: "/entities/UserEntity.swift")
        let uiNode = DependencyNode(name: "UserViewController", type: .class, filePath: "/ui/UserViewController.swift")

        graph.addNode(entitiesNode)
        graph.addNode(uiNode)

        // Add invalid dependency: UI layer depending directly on Entities layer
        graph.addDependency(Dependency(from: "UserViewController", to: "UserEntity", type: .composition, strength: .strong))

        // Validate
        let violations = validator.validate(graph)

        // Should have one violation
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.fromLayer, "FrameworksAndDrivers")  // UI is in this layer
        XCTAssertEqual(violations.first?.toLayer, "Entities")
        XCTAssertEqual(violations.first?.dependencyType, .composition)
    }

    func testLayeredArchitecturePolicyValidation() throws {
        let policy = LayerValidator.layeredArchitecturePolicy()
        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        // Create nodes following layered architecture
        let viewNode = DependencyNode(name: "UserView", type: .class, filePath: "/presentation/UserView.swift")
        let serviceNode = DependencyNode(name: "UserService", type: .class, filePath: "/application/UserService.swift")
        let repositoryNode = DependencyNode(name: "UserRepository", type: .class, filePath: "/domain/UserRepository.swift")
        let databaseNode = DependencyNode(name: "UserDatabase", type: .class, filePath: "/infrastructure/UserDatabase.swift")

        graph.addNode(viewNode)
        graph.addNode(serviceNode)
        graph.addNode(repositoryNode)
        graph.addNode(databaseNode)

        // Add valid dependencies: Presentation -> Application -> Domain -> Infrastructure
        graph.addDependency(Dependency(from: "UserView", to: "UserService", type: .composition, strength: .strong))
        graph.addDependency(Dependency(from: "UserService", to: "UserRepository", type: .composition, strength: .strong))
        graph.addDependency(Dependency(from: "UserRepository", to: "UserDatabase", type: .composition, strength: .strong))

        // Validate
        let violations = validator.validate(graph)

        // Should have no violations for valid layered dependencies
        XCTAssertEqual(violations.count, 0)
    }

    func testLayeredArchitecturePolicyViolations() throws {
        let policy = LayerValidator.layeredArchitecturePolicy()
        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        // Create nodes
        let viewNode = DependencyNode(name: "UserView", type: .class, filePath: "/presentation/UserView.swift")
        let databaseNode = DependencyNode(name: "UserDatabase", type: .class, filePath: "/infrastructure/UserDatabase.swift")

        graph.addNode(viewNode)
        graph.addNode(databaseNode)

        // Add invalid dependency: Presentation layer directly depending on Infrastructure
        graph.addDependency(Dependency(from: "UserView", to: "UserDatabase", type: .composition, strength: .strong))

        // Validate
        let violations = validator.validate(graph)

        // Should have one violation
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.fromLayer, "Presentation")
        XCTAssertEqual(violations.first?.toLayer, "Infrastructure")
    }

    func testThreeTierArchitecturePolicy() throws {
        let policy = LayerValidator.threeTierArchitecturePolicy()
        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        // Create nodes following three-tier architecture
        let uiNode = DependencyNode(name: "UserForm", type: .class, filePath: "/ui/UserForm.swift")
        let businessNode = DependencyNode(name: "UserService", type: .class, filePath: "/business/UserService.swift")
        let dataNode = DependencyNode(name: "UserRepository", type: .class, filePath: "/data/UserRepository.swift")

        graph.addNode(uiNode)
        graph.addNode(businessNode)
        graph.addNode(dataNode)

        // Add valid dependencies: UI -> Business -> Data
        graph.addDependency(Dependency(from: "UserForm", to: "UserService", type: .composition, strength: .strong))
        graph.addDependency(Dependency(from: "UserService", to: "UserRepository", type: .composition, strength: .strong))

        // Validate
        let violations = validator.validate(graph)

        // Should have no violations
        XCTAssertEqual(violations.count, 0)
    }

    func testThreeTierArchitecturePolicyViolations() throws {
        let policy = LayerValidator.threeTierArchitecturePolicy()
        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        // Create nodes
        let uiNode = DependencyNode(name: "UserForm", type: .class, filePath: "/ui/UserForm.swift")
        let dataNode = DependencyNode(name: "UserRepository", type: .class, filePath: "/data/UserRepository.swift")

        graph.addNode(uiNode)
        graph.addNode(dataNode)

        // Add invalid dependency: UI layer directly depending on Data layer
        graph.addDependency(Dependency(from: "UserForm", to: "UserRepository", type: .composition, strength: .strong))

        // Validate
        let violations = validator.validate(graph)

        // Should have one violation
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.fromLayer, "UI")
        XCTAssertEqual(violations.first?.toLayer, "Data")
    }

    func testModularArchitecturePolicy() throws {
        let modules = ["Auth", "User", "Product", "Order"]
        let policy = LayerValidator.modularArchitecturePolicy(modules: modules)
        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        // Create nodes for each module
        let authNode = DependencyNode(name: "AuthService", type: .class, filePath: "/Auth/AuthService.swift")
        let userNode = DependencyNode(name: "UserService", type: .class, filePath: "/User/UserService.swift")
        let productNode = DependencyNode(name: "ProductService", type: .class, filePath: "/Product/ProductService.swift")
        let orderNode = DependencyNode(name: "OrderService", type: .class, filePath: "/Order/OrderService.swift")

        graph.addNode(authNode)
        graph.addNode(userNode)
        graph.addNode(productNode)
        graph.addNode(orderNode)

        // Add inter-module dependencies (allowed in modular architecture)
        graph.addDependency(Dependency(from: "OrderService", to: "UserService", type: .composition, strength: .strong))
        graph.addDependency(Dependency(from: "UserService", to: "AuthService", type: .composition, strength: .strong))

        // Validate
        let violations = validator.validate(graph)

        // Should have no violations in modular architecture
        XCTAssertEqual(violations.count, 0)
    }

    func testLayerResolution() throws {
        let policy = LayerValidator.cleanArchitecturePolicy()
        let validator = LayerValidator(policy: policy)

        // Test layer resolution for different patterns
        let entityLayer = validator.getLayer(for: "UserEntity", isFile: false)
        let useCaseLayer = validator.getLayer(for: "CreateUserUseCase", isFile: false)
        let presenterLayer = validator.getLayer(for: "UserPresenter", isFile: false)
        let uiLayer = validator.getLayer(for: "UserViewController", isFile: false)

        XCTAssertEqual(entityLayer?.name, "Entities")
        XCTAssertEqual(useCaseLayer?.name, "UseCases")
        XCTAssertEqual(presenterLayer?.name, "InterfaceAdapters")
        XCTAssertEqual(uiLayer?.name, "FrameworksAndDrivers")
    }

    func testCustomArchitecturePolicy() throws {
        // Create a custom policy with specific layers and constraints
        let layers = [
            Layer(name: "Foundation", pattern: ".*Foundation.*", level: 1),
            Layer(name: "Core", pattern: ".*Core.*", level: 2, allowedDependencies: ["Foundation"]),
            Layer(name: "Features", pattern: ".*Features.*", level: 3, allowedDependencies: ["Foundation", "Core"])
        ]

        let policy = ArchitecturePolicy(
            name: "Custom Policy",
            layers: layers,
            allowSameLevelDependencies: false,
            allowLowerLevelDependencies: false
        )

        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        // Create nodes following the custom policy
        let foundationNode = DependencyNode(name: "NetworkFoundation", type: .class, filePath: "/Foundation/NetworkFoundation.swift")
        let coreNode = DependencyNode(name: "DataCore", type: .class, filePath: "/Core/DataCore.swift")
        let featureNode = DependencyNode(name: "UserProfileFeature", type: .class, filePath: "/Features/UserProfileFeature.swift")

        graph.addNode(foundationNode)
        graph.addNode(coreNode)
        graph.addNode(featureNode)

        // Add valid dependencies
        graph.addDependency(Dependency(from: "DataCore", to: "NetworkFoundation", type: .composition, strength: .strong))
        graph.addDependency(Dependency(from: "UserProfileFeature", to: "DataCore", type: .composition, strength: .strong))

        // Validate
        let violations = validator.validate(graph)

        // Should have no violations for valid dependencies
        XCTAssertEqual(violations.count, 0)
    }

    func testCustomArchitecturePolicyViolations() throws {
        let layers = [
            Layer(name: "Foundation", pattern: ".*Foundation.*", level: 1),
            Layer(name: "Core", pattern: ".*Core.*", level: 2, allowedDependencies: ["Foundation"]),
            Layer(name: "Features", pattern: ".*Features.*", level: 3, allowedDependencies: ["Foundation", "Core"])
        ]

        let policy = ArchitecturePolicy(
            name: "Custom Policy",
            layers: layers,
            allowSameLevelDependencies: false,
            allowLowerLevelDependencies: false
        )

        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        // Create nodes
        let foundationNode = DependencyNode(name: "NetworkFoundation", type: .class, filePath: "/Foundation/NetworkFoundation.swift")
        let featureNode = DependencyNode(name: "UserProfileFeature", type: .class, filePath: "/Features/UserProfileFeature.swift")

        graph.addNode(foundationNode)
        graph.addNode(featureNode)

        // Add invalid dependency: Features depending on Foundation (not allowed explicitly)
        graph.addDependency(Dependency(from: "UserProfileFeature", to: "NetworkFoundation", type: .composition, strength: .strong))

        // Validate
        let violations = validator.validate(graph)

        // Should have one violation
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.fromLayer, "Features")
        XCTAssertEqual(violations.first?.toLayer, "Foundation")
    }

    func testDependencyTypeSeverity() throws {
        let policy = LayerValidator.cleanArchitecturePolicy()
        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        let uiNode = DependencyNode(name: "UserViewController", type: .class, filePath: "/ui/UserViewController.swift")
        let entityNode = DependencyNode(name: "UserEntity", type: .class, filePath: "/entities/UserEntity.swift")

        graph.addNode(uiNode)
        graph.addNode(entityNode)

        // Test different dependency types and their severity levels
        let classInheritanceViolation = Dependency(from: "UserViewController", to: "UserEntity", type: .classInheritance, strength: .strong)
        let functionCallViolation = Dependency(from: "UserViewController", to: "UserEntity", type: .functionCall, strength: .weak)
        let typeReferenceViolation = Dependency(from: "UserViewController", to: "UserEntity", type: .typeReference, strength: .medium)

        // Add violations and test each one separately
        let violations1 = validator.validate(graph)
        XCTAssertEqual(violations1.count, 0)

        graph.addDependency(classInheritanceViolation)
        let violations2 = validator.validate(graph)
        XCTAssertEqual(violations2.count, 1)
        XCTAssertEqual(violations2.first?.severity, .error)

        graph.removeDependency(classInheritanceViolation)
        graph.addDependency(functionCallViolation)
        let violations3 = validator.validate(graph)
        XCTAssertEqual(violations3.count, 1)
        XCTAssertEqual(violations3.first?.severity, .info)

        graph.removeDependency(functionCallViolation)
        graph.addDependency(typeReferenceViolation)
        let violations4 = validator.validate(graph)
        XCTAssertEqual(violations4.count, 1)
        XCTAssertEqual(violations4.first?.severity, .warning)
    }

    func testProtocolConformanceAllowed() throws {
        let policy = LayerValidator.cleanArchitecturePolicy()
        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        let uiNode = DependencyNode(name: "UserViewController", type: .class, filePath: "/ui/UserViewController.swift")
        let protocolNode = DependencyNode(name: "Displayable", type: .protocol, filePath: "/protocols/Displayable.swift")

        graph.addNode(uiNode)
        graph.addNode(protocolNode)

        // Protocol conformance should generally be allowed regardless of layers
        graph.addDependency(Dependency(from: "UserViewController", to: "Displayable", type: .protocolConformance, strength: .medium))

        // Validate
        let violations = validator.validate(graph)

        // Should have no violations for protocol conformance
        XCTAssertEqual(violations.count, 0)
    }

    func testExtensionAllowed() throws {
        let policy = LayerValidator.cleanArchitecturePolicy()
        let validator = LayerValidator(policy: policy)
        let graph = DependencyGraph()

        let frameworkNode = DependencyNode(name: "String", type: .class, filePath: "/frameworks/String.swift")
        let extensionNode = DependencyNode(name: "String(extension)", type: .extension, filePath: "/extensions/String+Custom.swift")

        graph.addNode(frameworkNode)
        graph.addNode(extensionNode)

        // Extensions should be allowed
        graph.addDependency(Dependency(from: "String(extension)", to: "String", type: .extension, strength: .medium))

        // Validate
        let violations = validator.validate(graph)

        // Should have no violations for extensions
        XCTAssertEqual(violations.count, 0)
    }
}

