import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

final class OwnershipGraphVisualizerTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func createTestGraph() async -> OwnershipGraph {
        let graph = OwnershipGraph()
        let testFile = URL(fileURLWithPath: "/tmp/test.swift")
        
        // Create nodes
        let nodeA = OwnershipGraph.Node(
            id: "ClassA",
            type: "ClassA",
            location: Location(file: testFile, line: 1, column: 1),
            isReferenceType: true
        )
        
        let nodeB = OwnershipGraph.Node(
            id: "ClassB",
            type: "ClassB",
            location: Location(file: testFile, line: 10, column: 1),
            isReferenceType: true
        )
        
        let nodeC = OwnershipGraph.Node(
            id: "StructC",
            type: "StructC",
            location: Location(file: testFile, line: 20, column: 1),
            isReferenceType: false
        )
        
        await graph.addNodeSync(nodeA)
        await graph.addNodeSync(nodeB)
        await graph.addNodeSync(nodeC)
        
        // Create references
        let refAB = OwnershipGraph.Reference(
            from: "ClassA",
            to: "ClassB",
            type: .strong,
            location: Location(file: testFile, line: 5, column: 10)
        )
        
        let refBC = OwnershipGraph.Reference(
            from: "ClassB",
            to: "StructC",
            type: .weak,
            location: Location(file: testFile, line: 15, column: 10),
            isWeak: true
        )
        
        await graph.addReferenceSync(refAB)
        await graph.addReferenceSync(refBC)
        
        return graph
    }
    
    private func createCyclicGraph() async -> OwnershipGraph {
        let graph = OwnershipGraph()
        let testFile = URL(fileURLWithPath: "/tmp/test.swift")
        
        // Create nodes that form a cycle
        let nodeA = OwnershipGraph.Node(
            id: "CycleA",
            type: "CycleA",
            location: Location(file: testFile, line: 1, column: 1),
            isReferenceType: true
        )
        
        let nodeB = OwnershipGraph.Node(
            id: "CycleB",
            type: "CycleB",
            location: Location(file: testFile, line: 10, column: 1),
            isReferenceType: true
        )
        
        await graph.addNodeSync(nodeA)
        await graph.addNodeSync(nodeB)
        
        // Create cyclic references: A -> B -> A
        let refAB = OwnershipGraph.Reference(
            from: "CycleA",
            to: "CycleB",
            type: .strong,
            location: Location(file: testFile, line: 5, column: 10)
        )
        
        let refBA = OwnershipGraph.Reference(
            from: "CycleB",
            to: "CycleA",
            type: .strong,
            location: Location(file: testFile, line: 15, column: 10)
        )
        
        await graph.addReferenceSync(refAB)
        await graph.addReferenceSync(refBA)
        
        return graph
    }
    
    // MARK: - DOT Format Tests
    
    func testDOTExportBasicStructure() async throws {
        let graph = await createTestGraph()
        let dot = await graph.exportToDOT()
        
        XCTAssertTrue(dot.contains("digraph OwnershipGraph"), "Should have DOT graph header")
        XCTAssertTrue(dot.contains("ClassA"), "Should contain ClassA node")
        XCTAssertTrue(dot.contains("ClassB"), "Should contain ClassB node")
        XCTAssertTrue(dot.contains("StructC"), "Should contain StructC node")
        XCTAssertTrue(dot.contains("->"), "Should contain edge arrows")
    }
    
    func testDOTExportWithOptions() async throws {
        let graph = await createTestGraph()
        var options = OwnershipGraphVisualizer.Options()
        options.includeNodeDetails = true
        options.includeReferenceDetails = true
        
        let visualizer = OwnershipGraphVisualizer(graph: graph, options: options)
        let dot = await visualizer.export(format: .dot)
        
        XCTAssertTrue(dot.contains("lifetime"), "Should include lifetime details")
        XCTAssertTrue(dot.contains("reference type"), "Should include reference type info")
    }
    
    func testDOTExportHighlightsCycles() async throws {
        let graph = await createCyclicGraph()
        var options = OwnershipGraphVisualizer.Options()
        options.highlightProblems = true
        
        let visualizer = OwnershipGraphVisualizer(graph: graph, options: options)
        let dot = await visualizer.export(format: .dot)
        
        XCTAssertTrue(dot.contains("red") || dot.contains("fillcolor"), "Should highlight cyclic nodes")
    }
    
    // MARK: - ASCII Format Tests
    
    func testASCIIExportBasicStructure() async throws {
        let graph = await createTestGraph()
        let ascii = await graph.exportToASCII()
        
        XCTAssertTrue(ascii.contains("OWNERSHIP GRAPH"), "Should have header")
        XCTAssertTrue(ascii.contains("STATISTICS"), "Should have statistics section")
        XCTAssertTrue(ascii.contains("NODES"), "Should have nodes section")
        XCTAssertTrue(ascii.contains("REFERENCES"), "Should have references section")
    }
    
    func testASCIIExportShowsStatistics() async throws {
        let graph = await createTestGraph()
        let ascii = await graph.exportToASCII()
        
        XCTAssertTrue(ascii.contains("Nodes:"), "Should show node count")
        XCTAssertTrue(ascii.contains("References:"), "Should show reference count")
    }
    
    func testASCIIExportShowsNodeTypes() async throws {
        let graph = await createTestGraph()
        let ascii = await graph.exportToASCII()
        
        XCTAssertTrue(ascii.contains("REF") || ascii.contains("VAL"), "Should show node type indicators")
    }
    
    func testASCIIExportHighlightsIssues() async throws {
        let graph = await createCyclicGraph()
        var options = OwnershipGraphVisualizer.Options()
        options.highlightProblems = true
        
        let visualizer = OwnershipGraphVisualizer(graph: graph, options: options)
        let ascii = await visualizer.export(format: .ascii)
        
        XCTAssertTrue(ascii.contains("ISSUES") || ascii.contains("POTENTIAL"), "Should have issues section")
    }
    
    // MARK: - JSON Format Tests
    
    func testJSONExportBasicStructure() async throws {
        let graph = await createTestGraph()
        let json = await graph.exportToJSON()
        
        XCTAssertTrue(json.contains("\"statistics\""), "Should have statistics")
        XCTAssertTrue(json.contains("\"nodes\""), "Should have nodes array")
        XCTAssertTrue(json.contains("\"references\""), "Should have references array")
    }
    
    func testJSONExportIsValidJSON() async throws {
        let graph = await createTestGraph()
        let json = await graph.exportToJSON()
        
        let data = json.data(using: .utf8)!
        let parsed = try JSONSerialization.jsonObject(with: data)
        
        XCTAssertNotNil(parsed as? [String: Any], "Should produce valid JSON dictionary")
    }
    
    func testJSONExportContainsNodeDetails() async throws {
        let graph = await createTestGraph()
        let json = await graph.exportToJSON()
        
        XCTAssertTrue(json.contains("\"id\""), "Should have node IDs")
        XCTAssertTrue(json.contains("\"type\""), "Should have node types")
        XCTAssertTrue(json.contains("\"isReferenceType\""), "Should have reference type flag")
        XCTAssertTrue(json.contains("\"lifetime\""), "Should have lifetime info")
    }
    
    func testJSONExportContainsIssues() async throws {
        let graph = await createCyclicGraph()
        let json = await graph.exportToJSON()
        
        XCTAssertTrue(json.contains("\"issues\""), "Should have issues section")
        XCTAssertTrue(json.contains("\"retainCycles\""), "Should track retain cycles")
        XCTAssertTrue(json.contains("\"potentialLeaks\""), "Should track potential leaks")
    }
    
    // MARK: - Mermaid Format Tests
    
    func testMermaidExportBasicStructure() async throws {
        let graph = await createTestGraph()
        let mermaid = await graph.exportToMermaid()
        
        XCTAssertTrue(mermaid.contains("graph TD"), "Should have Mermaid graph header")
        XCTAssertTrue(mermaid.contains("-->") || mermaid.contains("-.-"), "Should have edge arrows")
    }
    
    func testMermaidExportIncludesStyles() async throws {
        let graph = await createTestGraph()
        let mermaid = await graph.exportToMermaid()
        
        XCTAssertTrue(mermaid.contains("classDef"), "Should define CSS classes")
        XCTAssertTrue(mermaid.contains("class "), "Should apply classes to nodes")
    }
    
    func testMermaidExportSanitizesNodeIds() async throws {
        let graph = OwnershipGraph()
        let testFile = URL(fileURLWithPath: "/tmp/test.swift")
        
        // Create node with special characters
        let node = OwnershipGraph.Node(
            id: "Module.Class#123",
            type: "SpecialClass",
            location: Location(file: testFile, line: 1, column: 1),
            isReferenceType: true
        )
        
        await graph.addNodeSync(node)
        
        let mermaid = await graph.exportToMermaid()
        
        // Should not contain problematic characters
        XCTAssertFalse(mermaid.contains("Module.Class#123["), "Should sanitize node IDs")
        XCTAssertTrue(mermaid.contains("Module_Class_123"), "Should replace special chars with underscores")
    }
    
    // MARK: - Options Tests
    
    func testMaxNodesOption() async throws {
        let graph = OwnershipGraph()
        let testFile = URL(fileURLWithPath: "/tmp/test.swift")
        
        // Add many nodes
        for i in 0..<50 {
            let node = OwnershipGraph.Node(
                id: "Node\(i)",
                type: "Type\(i)",
                location: Location(file: testFile, line: i, column: 1),
                isReferenceType: true
            )
            await graph.addNodeSync(node)
        }
        
        var options = OwnershipGraphVisualizer.Options()
        options.maxNodes = 10
        
        let visualizer = OwnershipGraphVisualizer(graph: graph, options: options)
        let ascii = await visualizer.export(format: .ascii)
        
        XCTAssertTrue(ascii.contains("more nodes"), "Should indicate truncation")
    }
    
    func testGroupByFileOption() async throws {
        let graph = OwnershipGraph()
        let file1 = URL(fileURLWithPath: "/tmp/File1.swift")
        let file2 = URL(fileURLWithPath: "/tmp/File2.swift")
        
        let node1 = OwnershipGraph.Node(
            id: "Node1",
            type: "Type1",
            location: Location(file: file1, line: 1, column: 1),
            isReferenceType: true
        )
        
        let node2 = OwnershipGraph.Node(
            id: "Node2",
            type: "Type2",
            location: Location(file: file2, line: 1, column: 1),
            isReferenceType: true
        )
        
        await graph.addNodeSync(node1)
        await graph.addNodeSync(node2)
        
        var options = OwnershipGraphVisualizer.Options()
        options.groupByFile = true
        
        let visualizer = OwnershipGraphVisualizer(graph: graph, options: options)
        let dot = await visualizer.export(format: .dot)
        
        XCTAssertTrue(dot.contains("subgraph"), "Should create subgraphs for files")
        XCTAssertTrue(dot.contains("File1"), "Should include File1 cluster")
        XCTAssertTrue(dot.contains("File2"), "Should include File2 cluster")
    }
    
    // MARK: - Extension Method Tests
    
    func testGraphVisualizerExtension() async throws {
        let graph = await createTestGraph()
        
        let visualizer = graph.visualizer()
        let dot = await visualizer.export(format: .dot)
        
        XCTAssertFalse(dot.isEmpty, "Extension method should work")
    }
    
    func testQuickExportMethods() async throws {
        let graph = await createTestGraph()
        
        let dot = await graph.exportToDOT()
        let ascii = await graph.exportToASCII()
        let json = await graph.exportToJSON()
        let mermaid = await graph.exportToMermaid()
        
        XCTAssertFalse(dot.isEmpty, "DOT export should work")
        XCTAssertFalse(ascii.isEmpty, "ASCII export should work")
        XCTAssertFalse(json.isEmpty, "JSON export should work")
        XCTAssertFalse(mermaid.isEmpty, "Mermaid export should work")
    }
}
