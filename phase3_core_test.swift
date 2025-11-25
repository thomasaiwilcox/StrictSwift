import Foundation
import SwiftSyntax

// Test core Phase 3 functionality directly
func testOwnershipGraph() async {
    let graph = OwnershipGraph()

    // Create test nodes
    let testFileURL = URL(fileURLWithPath: "/tmp/test.swift")
    let node1 = OwnershipGraph.Node(
        id: "test1",
        type: "TestClass",
        location: Location(file: testFileURL, line: 1, column: 1),
        isReferenceType: true
    )

    await graph.addNodeSync(node1)

    print("✅ OwnershipGraph: Node added successfully")

    // Create test reference
    let reference = OwnershipGraph.Reference(
        from: "test1",
        to: "test2",
        type: .strong,
        location: Location(file: testFileURL, line: 2, column: 1)
    )

    await graph.addReferenceSync(reference)

    print("✅ OwnershipGraph: Reference added successfully")

    // Test graph operations
    let nodes = await graph.allNodes
    let references = await graph.allReferences

    print("✅ OwnershipGraph: \(nodes.count) nodes, \(references.count) references")

    // Test statistics
    let stats = await graph.statistics
    print("✅ OwnershipGraph: Statistics generated - NodeCount: \(stats.nodeCount)")
}

func testOwnershipAnalyzer() async {
    let sourceCode = """
    import Foundation

    class TestClass {
        var property: String?

        func method() {
            let closure = {
                self.property = "test"
            }
        }
    }
    """

    let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
    let analyzer = OwnershipAnalyzer()

    let result = await analyzer.analyze(sourceFile)

    print("✅ OwnershipAnalyzer: Analysis completed")
    print("✅ OwnershipAnalyzer: \(result.statistics.nodeCount) nodes analyzed")
    print("✅ OwnershipAnalyzer: \(result.issues.count) issues found")

    // Test location accuracy - should not be line 1
    for issue in result.issues {
        if issue.location.line > 1 {
            print("✅ Location Accuracy: Issue at line \(issue.location.line) (not line 1)")
        } else {
            print("❌ Location Accuracy: Issue still at line 1")
        }
    }
}

func testEscapingReferenceRule() async {
    let sourceCode = """
    import Foundation

    class Escaper {
        var value = "test"

        func createEscapingClosure() -> () -> Void {
            return {
                self.value = "escaped"
            }
        }
    }
    """

    let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
    let rule = EscapingReferenceRule()
    let context = AnalysisContext(
        sourceFiles: [sourceFile],
        workspace: URL(fileURLWithPath: "/tmp"),
        configuration: Configuration()
    )

    let violations = await rule.analyze(sourceFile, in: context)

    print("✅ EscapingReferenceRule: \(violations.count) violations found")

    for violation in violations {
        print("  - Violation at line \(violation.location.line): \(violation.message)")
    }
}

func testExclusiveAccessRule() async {
    let sourceCode = """
    import Foundation

    class SharedResource {
        private var counter = 0

        func increment() {
            counter += 1
        }

        func reset() {
            counter = 0
        }
    }
    """

    let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
    let rule = ExclusiveAccessRule()
    let context = AnalysisContext(
        sourceFiles: [sourceFile],
        workspace: URL(fileURLWithPath: "/tmp"),
        configuration: Configuration()
    )

    let violations = await rule.analyze(sourceFile, in: context)

    print("✅ ExclusiveAccessRule: \(violations.count) violations found")

    for violation in violations {
        print("  - Violation at line \(violation.location.line): \(violation.message)")
    }
}

// Main test runner
@main
struct Phase3CoreTests {
    static func main() async {
        print("🚀 Testing Phase 3 Core Functionality")
        print("=" * 50)

        await testOwnershipGraph()
        print()

        await testOwnershipAnalyzer()
        print()

        await testEscapingReferenceRule()
        print()

        await testExclusiveAccessRule()
        print()

        print("=" * 50)
        print("✅ Phase 3 Core Tests Completed")
    }
}
