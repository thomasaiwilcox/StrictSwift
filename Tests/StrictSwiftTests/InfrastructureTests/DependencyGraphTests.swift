import XCTest
@testable import StrictSwiftCore

final class DependencyGraphTests: XCTestCase {

    func testDependencyGraphBasicOperations() throws {
        let graph = DependencyGraph()

        // Test adding nodes
        let node1 = DependencyNode(name: "ModuleA", type: .module, filePath: "/path/a.swift")
        let node2 = DependencyNode(name: "ClassB", type: .class, filePath: "/path/b.swift")

        graph.addNode(node1)
        graph.addNode(node2)

        XCTAssertEqual(graph.allNodes.count, 2)

        // Test adding dependencies
        let dependency = Dependency(
            from: "ModuleA",
            to: "ClassB",
            type: .composition,
            strength: .medium
        )
        graph.addDependency(dependency)

        XCTAssertEqual(graph.allDependencies.count, 1)
        XCTAssertTrue(graph.hasDependency(from: "ModuleA", to: "ClassB"))
    }

    func testDependencyGraphCircularDependencies() throws {
        let graph = DependencyGraph()

        // Create a circular dependency: A -> B -> C -> A
        let nodeA = DependencyNode(name: "A", type: .module, filePath: "/a.swift")
        let nodeB = DependencyNode(name: "B", type: .module, filePath: "/b.swift")
        let nodeC = DependencyNode(name: "C", type: .module, filePath: "/c.swift")

        graph.addNode(nodeA)
        graph.addNode(nodeB)
        graph.addNode(nodeC)

        graph.addDependency(Dependency(from: "A", to: "B", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "B", to: "C", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "C", to: "A", type: .importModule, strength: .strong))

        let cycles = graph.findCycles()
        XCTAssertEqual(cycles.count, 1)
        XCTAssertEqual(cycles.first?.count, 3)
        XCTAssertTrue(cycles.first?.contains("A") ?? false)
        XCTAssertTrue(cycles.first?.contains("B") ?? false)
        XCTAssertTrue(cycles.first?.contains("C") ?? false)
    }

    func testDependencyGraphMultipleCycles() throws {
        let graph = DependencyGraph()

        // Create two separate cycles
        let nodes = ["A", "B", "C", "D", "E", "F"].map {
            DependencyNode(name: $0, type: .module, filePath: "/\($0.lowercased()).swift")
        }

        nodes.forEach { graph.addNode($0) }

        // First cycle: A -> B -> A
        graph.addDependency(Dependency(from: "A", to: "B", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "B", to: "A", type: .importModule, strength: .strong))

        // Second cycle: D -> E -> F -> D
        graph.addDependency(Dependency(from: "D", to: "E", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "E", to: "F", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "F", to: "D", type: .importModule, strength: .strong))

        let cycles = graph.findCycles()
        XCTAssertEqual(cycles.count, 2)
    }

    func testDependencyGraphDepthCalculation() throws {
        let graph = DependencyGraph()

        // Create a dependency chain: A -> B -> C -> D
        let nodes = ["A", "B", "C", "D"].map {
            DependencyNode(name: $0, type: .module, filePath: "/\($0.lowercased()).swift")
        }

        nodes.forEach { graph.addNode($0) }

        graph.addDependency(Dependency(from: "A", to: "B", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "B", to: "C", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "C", to: "D", type: .importModule, strength: .strong))

        XCTAssertEqual(graph.dependencyDepth(for: "A"), 3)
        XCTAssertEqual(graph.dependencyDepth(for: "B"), 2)
        XCTAssertEqual(graph.dependencyDepth(for: "C"), 1)
        XCTAssertEqual(graph.dependencyDepth(for: "D"), 0)
    }

    func testDependencyGraphLongestChain() throws {
        let graph = DependencyGraph()

        // Create multiple chains
        let nodes = ["A", "B", "C", "D", "E", "F"].map {
            DependencyNode(name: $0, type: .module, filePath: "/\($0.lowercased()).swift")
        }

        nodes.forEach { graph.addNode($0) }

        // Long chain: A -> B -> C -> D -> E
        graph.addDependency(Dependency(from: "A", to: "B", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "B", to: "C", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "C", to: "D", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "D", to: "E", type: .importModule, strength: .strong))

        // Short chain: F -> E
        graph.addDependency(Dependency(from: "F", to: "E", type: .importModule, strength: .strong))

        let longestChain = graph.longestDependencyChain()
        XCTAssertEqual(longestChain.count, 5)
        XCTAssertEqual(longestChain, ["A", "B", "C", "D", "E"])
    }

    func testDependencyGraphDependents() throws {
        let graph = DependencyGraph()

        let nodes = ["A", "B", "C", "D"].map {
            DependencyNode(name: $0, type: .module, filePath: "/\($0.lowercased()).swift")
        }

        nodes.forEach { graph.addNode($0) }

        // B, C, D all depend on A
        graph.addDependency(Dependency(from: "B", to: "A", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "C", to: "A", type: .importModule, strength: .strong))
        graph.addDependency(Dependency(from: "D", to: "A", type: .importModule, strength: .strong))

        let dependents = graph.dependents(on: "A")
        XCTAssertEqual(dependents.count, 3)
        XCTAssertTrue(dependents.contains("B"))
        XCTAssertTrue(dependents.contains("C"))
        XCTAssertTrue(dependents.contains("D"))
    }

    func testDependencyGraphMerge() throws {
        let graph1 = DependencyGraph()
        let graph2 = DependencyGraph()

        // Add nodes and dependencies to first graph
        let node1 = DependencyNode(name: "A", type: .module, filePath: "/a.swift")
        let node2 = DependencyNode(name: "B", type: .module, filePath: "/b.swift")
        graph1.addNode(node1)
        graph1.addNode(node2)
        graph1.addDependency(Dependency(from: "A", to: "B", type: .importModule, strength: .strong))

        // Add nodes and dependencies to second graph
        let node3 = DependencyNode(name: "C", type: .module, filePath: "/c.swift")
        let node4 = DependencyNode(name: "D", type: .module, filePath: "/d.swift")
        graph2.addNode(node3)
        graph2.addNode(node4)
        graph2.addDependency(Dependency(from: "C", to: "D", type: .importModule, strength: .strong))

        // Merge graphs
        graph1.merge(graph2)

        XCTAssertEqual(graph1.allNodes.count, 4)
        XCTAssertEqual(graph1.allDependencies.count, 2)
        XCTAssertTrue(graph1.hasDependency(from: "A", to: "B"))
        XCTAssertTrue(graph1.hasDependency(from: "C", to: "D"))
    }

    func testDependencyGraphClear() throws {
        let graph = DependencyGraph()

        // Add some data
        let node = DependencyNode(name: "Test", type: .module, filePath: "/test.swift")
        graph.addNode(node)
        graph.addDependency(Dependency(from: "Test", to: "Other", type: .importModule, strength: .strong))

        XCTAssertEqual(graph.allNodes.count, 1)
        XCTAssertEqual(graph.allDependencies.count, 1)

        // Clear the graph
        graph.clear()

        XCTAssertEqual(graph.allNodes.count, 0)
        XCTAssertEqual(graph.allDependencies.count, 0)
    }

    func testDependencyGraphDescription() throws {
        let graph = DependencyGraph()

        let node1 = DependencyNode(name: "ModuleA", type: .module, filePath: "/a.swift")
        let node2 = DependencyNode(name: "ClassB", type: .class, filePath: "/b.swift")

        graph.addNode(node1)
        graph.addNode(node2)
        graph.addDependency(Dependency(from: "ModuleA", to: "ClassB", type: .composition, strength: .medium))

        let description = graph.generateDescription()

        XCTAssertTrue(description.contains("Dependency Graph"))
        XCTAssertTrue(description.contains("Nodes: 2"))
        XCTAssertTrue(description.contains("Dependencies: 1"))
        XCTAssertTrue(description.contains("ModuleA"))
        XCTAssertTrue(description.contains("ClassB"))
        XCTAssertTrue(description.contains("composition"))
        XCTAssertTrue(description.contains("strength: 2"))
    }

    func testDependencyStrength() throws {
        let graph = DependencyGraph()

        // Test all dependency strengths
        let weakDependency = Dependency(from: "A", to: "B", type: .functionCall, strength: .weak)
        let mediumDependency = Dependency(from: "A", to: "C", type: .composition, strength: .medium)
        let strongDependency = Dependency(from: "A", to: "D", type: .importModule, strength: .strong)

        graph.addDependency(weakDependency)
        graph.addDependency(mediumDependency)
        graph.addDependency(strongDependency)

        let dependencies = graph.allDependencies
        XCTAssertEqual(dependencies.count, 3)
        
        // Check that all strengths are present (order is not guaranteed)
        let strengths = Set(dependencies.map { $0.strength.rawValue })
        XCTAssertTrue(strengths.contains(1), "Should contain weak strength")
        XCTAssertTrue(strengths.contains(2), "Should contain medium strength")
        XCTAssertTrue(strengths.contains(3), "Should contain strong strength")
    }

    func testDependencyType() throws {
        let graph = DependencyGraph()

        // Test all dependency types
        let types: [DependencyType] = [
            .importModule, .classInheritance, .protocolConformance,
            .composition, .functionCall, .propertyAccess,
            .extension, .typeReference
        ]

        for (index, type) in types.enumerated() {
            let dependency = Dependency(
                from: "Source\(index)",
                to: "Target\(index)",
                type: type,
                strength: .medium
            )
            graph.addDependency(dependency)
        }

        let dependencies = graph.allDependencies
        XCTAssertEqual(dependencies.count, types.count)

        // Check that all types are present (order is not guaranteed)
        let foundTypes = Set(dependencies.map { $0.type.rawValue })
        for type in types {
            XCTAssertTrue(foundTypes.contains(type.rawValue), "Should contain type \(type.rawValue)")
        }
    }

    func testDependencyNodeTypes() throws {
        let graph = DependencyGraph()

        // Test all node types
        let types: [NodeType] = [
            .module, .file, .class, .struct, .protocol,
            .enum, .function, .extension
        ]

        for type in types {
            let node = DependencyNode(name: "Node_\(type.rawValue)", type: type, filePath: "/test.swift")
            graph.addNode(node)
        }

        let nodes = graph.allNodes
        XCTAssertEqual(nodes.count, types.count)

        // Check that all types are present (order is not guaranteed)
        let foundTypes = Set(nodes.map { $0.type.rawValue })
        for type in types {
            XCTAssertTrue(foundTypes.contains(type.rawValue), "Should contain node type \(type.rawValue)")
        }
    }

    func testDependencyGraphConcurrencySafety() throws {
        let graph = DependencyGraph()
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        let iterations = 10

        // Simulate concurrent access
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let node = DependencyNode(name: "Node\(index)", type: .module, filePath: "/test\(index).swift")
            graph.addNode(node)

            for j in 0..<5 {
                let dependency = Dependency(
                    from: "Node\(index)",
                    to: "Node\(j)",
                    type: .importModule,
                    strength: .strong
                )
                graph.addDependency(dependency)
            }

            if index == iterations - 1 {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(graph.allNodes.count, iterations)
        XCTAssertTrue(graph.allDependencies.count >= iterations * 5)
    }
}