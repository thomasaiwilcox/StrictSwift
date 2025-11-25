import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

final class OwnershipAnalysisTests: XCTestCase {

    // MARK: - OwnershipGraph Tests

    func testOwnershipGraphBasicFunctionality() async throws {
        let graph = OwnershipGraph()

        // Test adding nodes and references
        let testFileURL = URL(fileURLWithPath: "/tmp/test.swift")

        let node1 = OwnershipGraph.Node(
            id: "test1",
            type: "TestClass",
            location: Location(file: testFileURL, line: 1, column: 1),
            isReferenceType: true
        )

        let node2 = OwnershipGraph.Node(
            id: "test2",
            type: "AnotherClass",
            location: Location(file: testFileURL, line: 2, column: 1),
            isReferenceType: true
        )

        await graph.addNodeSync(node1)
        await graph.addNodeSync(node2)

        let reference = OwnershipGraph.Reference(
            from: "test1",
            to: "test2",
            type: .strong,
            location: Location(file: testFileURL, line: 1, column: 10)
        )

        await graph.addReferenceSync(reference)

        // Verify graph contents
        let nodes = await graph.allNodes
        let references = await graph.allReferences

        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(references.first?.from, "test1")
        XCTAssertEqual(references.first?.to, "test2")
    }

    func testOwnershipGraphFindMemoryLeaks() async throws {
        let graph = OwnershipGraph()
        let testFileURL = URL(fileURLWithPath: "/tmp/test.swift")

        // Create a scenario that should trigger memory leak detection
        let leakedNode = OwnershipGraph.Node(
            id: "leaked",
            type: "LeakedClass",
            location: Location(file: testFileURL, line: 5, column: 1),
            isReferenceType: true
        )

        let referencingNode = OwnershipGraph.Node(
            id: "referrer",
            type: "ReferrerClass",
            location: Location(file: testFileURL, line: 10, column: 1),
            isReferenceType: false
        )

        let reference = OwnershipGraph.Reference(
            from: "referrer",
            to: "leaked",
            type: .strong,
            location: Location(file: testFileURL, line: 12, column: 1)
        )

        await graph.addNodeSync(leakedNode)
        await graph.addNodeSync(referencingNode)
        await graph.addReferenceSync(reference)

        let memoryLeaks = await graph.findMemoryLeaks()
        XCTAssertFalse(memoryLeaks.isEmpty, "Should detect memory leak scenario")
    }

    // MARK: - OwnershipAnalyzer Tests

    func testOwnershipAnalyzerBasicAnalysis() async throws {
        let sourceCode = """
        import Foundation

        class TestClass {
            var property: String?

            func method() {
                let data = Data()
                property = "test"
            }
        }

        func testFunction() {
            let instance = TestClass()
            instance.property = "value"
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let analyzer = OwnershipAnalyzer()

        let result = await analyzer.analyze(sourceFile)

        XCTAssertNotNil(result.graph)
        XCTAssertGreaterThan(result.statistics.nodeCount, 0)
        // Note: This simple code doesn't have ownership issues like retain cycles,
        // use-after-free, or escaping references - it's just basic assignments.
        // The analysis should complete successfully without errors.
    }

    func testOwnershipAnalyzerClosureEscaping() async throws {
        let sourceCode = """
        import Foundation

        class Escaper {
            var value: String = "test"

            func createEscapingClosure() -> () -> Void {
                return {
                    self.value = "escaped"  // This should create an escaping reference
                }
            }
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let analyzer = OwnershipAnalyzer()

        let result = await analyzer.analyze(sourceFile)

        // Should detect escaping references
        let escapingIssues = result.issues.filter { $0.type == .escapingReference }
        XCTAssertFalse(escapingIssues.isEmpty, "Should detect escaping reference in closure")

        // Verify location accuracy - should not be line 1
        for issue in escapingIssues {
            XCTAssertGreaterThan(issue.location.line, 1, "Location should not be line 1")
            XCTAssertGreaterThan(issue.location.column, 0, "Column should be valid")
        }
    }

    func testOwnershipAnalyzerWeakReferences() async throws {
        let sourceCode = """
        import Foundation

        class Manager {
            weak var delegate: Delegate?

            func setDelegate(_ delegate: Delegate) {
                self.delegate = delegate  // Should be detected as weak reference
            }
        }

        protocol Delegate: AnyObject {}
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let analyzer = OwnershipAnalyzer()

        let result = await analyzer.analyze(sourceFile)

        // Should analyze weak references properly
        XCTAssertGreaterThan(result.statistics.nodeCount, 0)

        let weakReferences = await result.graph.allReferences.filter { $0.isWeak }
        XCTAssertFalse(weakReferences.isEmpty, "Should detect weak references")
    }

    func testOwnershipAnalyzerLocationAccuracy() async throws {
        let sourceCode = """
        import Foundation

        class LocationTest {
            func method() {  // Line 4
                let data = Data()  // Line 5
            }
        }
        """

        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let analyzer = OwnershipAnalyzer()

        let result = await analyzer.analyze(sourceFile)

        // Verify that at least some nodes have accurate locations (not all at line 1)
        let allNodes = await result.graph.allNodes
        if !allNodes.isEmpty {
            let nodesNotAtLine1 = allNodes.filter { $0.location.line > 1 }
            XCTAssertFalse(nodesNotAtLine1.isEmpty, "At least some nodes should have locations beyond line 1")
        }

        let allReferences = await result.graph.allReferences
        if !allReferences.isEmpty {
            let refsNotAtLine1 = allReferences.filter { $0.location.line > 1 }
            XCTAssertFalse(refsNotAtLine1.isEmpty, "At least some references should have locations beyond line 1")
        }

        // Check column values are positive for all items
        for node in allNodes {
            XCTAssertGreaterThan(node.location.column, 0, "Column should be positive")
        }

        for reference in allReferences {
            XCTAssertGreaterThan(reference.location.column, 0, "Column should be positive")
        }

        for issue in result.issues {
            XCTAssertGreaterThan(issue.location.column, 0, "Column should be positive")
        }
    }
}

// MARK: - Test Extensions

extension OwnershipAnalysisTests {

    func testOwnershipGraphStatistics() async throws {
        let graph = OwnershipGraph()
        let testFileURL = URL(fileURLWithPath: "/tmp/test.swift")

        // Add some test data
        for i in 1...5 {
            let node = OwnershipGraph.Node(
                id: "node\(i)",
                type: "TestType\(i)",
                location: Location(file: testFileURL, line: i, column: 1),
                isReferenceType: i % 2 == 0
            )
            await graph.addNodeSync(node)
        }

        // Add references
        await graph.addReferenceSync(OwnershipGraph.Reference(
            from: "node1",
            to: "node2",
            type: .strong,
            location: Location(file: testFileURL, line: 1, column: 10)
        ))

        await graph.addReferenceSync(OwnershipGraph.Reference(
            from: "node2",
            to: "node3",
            type: .weak,
            location: Location(file: testFileURL, line: 2, column: 10)
        ))

        let stats = await graph.statistics

        XCTAssertEqual(stats.nodeCount, 5)
        XCTAssertEqual(stats.referenceCount, 2)
        XCTAssertEqual(stats.referenceTypeCount[.strong], 1)
        XCTAssertEqual(stats.referenceTypeCount[.weak], 1)
    }
}
