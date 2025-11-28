import Foundation

// strictswift:ignore-file circular_dependency_graph -- OwnershipGraph↔OwnershipStatistics is intentional helper pattern

/// Visualizer for the OwnershipGraph that can export to DOT format and ASCII art
public struct OwnershipGraphVisualizer: Sendable {
    
    /// Output format for visualization
    public enum OutputFormat: String, CaseIterable, Sendable {
        case dot = "dot"          // GraphViz DOT format
        case ascii = "ascii"      // ASCII art diagram
        case json = "json"        // JSON representation
        case mermaid = "mermaid"  // Mermaid diagram format
    }
    
    /// Visualization options
    public struct Options: Sendable {
        /// Include node details (type, lifetime, etc.)
        public var includeNodeDetails: Bool = true
        
        /// Include reference details (type, escaping, etc.)
        public var includeReferenceDetails: Bool = true
        
        /// Highlight problematic patterns (cycles, leaks, etc.)
        public var highlightProblems: Bool = true
        
        /// Maximum nodes to display (for large graphs)
        public var maxNodes: Int = 100
        
        /// Group nodes by file
        public var groupByFile: Bool = true
        
        /// Color scheme for DOT output
        public var colorScheme: ColorScheme = .default
        
        public init() {}
        
        public enum ColorScheme: String, Sendable {
            case `default` = "default"
            case dark = "dark"
            case colorblind = "colorblind"
        }
    }
    
    private let graph: OwnershipGraph
    private let options: Options
    
    public init(graph: OwnershipGraph, options: Options = Options()) {
        self.graph = graph
        self.options = options
    }
    
    /// Export the graph to the specified format
    public func export(format: OutputFormat) async -> String {
        switch format {
        case .dot:
            return await exportToDOT()
        case .ascii:
            return await exportToASCII()
        case .json:
            return await exportToJSON()
        case .mermaid:
            return await exportToMermaid()
        }
    }
    
    /// Export to a file
    public func exportToFile(format: OutputFormat, path: URL) async throws {
        let content = await export(format: format)
        try content.write(to: path, atomically: true, encoding: .utf8)
    }
    
    // MARK: - DOT Format Export
    
    private func exportToDOT() async -> String {
        var output = """
        digraph OwnershipGraph {
            // Graph settings
            rankdir=TB;
            node [shape=box, style=filled, fontname="Helvetica"];
            edge [fontname="Helvetica", fontsize=10];
            
        """
        
        let allNodes = await graph.allNodes
        let allReferences = await graph.allReferences
        let cycles = await graph.findRetainCycles()
        let leaks = await graph.findMemoryLeaks()
        let escapingRefs = await graph.allEscapingReferences
        
        // Collect nodes in cycles and leaks for highlighting
        let cycleNodeIds = Set(cycles.flatMap { $0.flatMap { [$0.from, $0.to] } })
        let leakNodeIds = Set(leaks.map { $0.id })
        let escapingNodeIds = Set(escapingRefs.map { $0.from })
        
        // Group nodes by file if requested
        if options.groupByFile {
            let nodesByFile = Dictionary(grouping: allNodes) { node in
                node.location.file.lastPathComponent
            }
            
            for (fileName, nodes) in nodesByFile.prefix(options.maxNodes > 0 ? options.maxNodes : nodesByFile.count) {
                output += "    subgraph \"cluster_\(sanitize(fileName))\" {\n"
                output += "        label=\"\(fileName)\";\n"
                output += "        style=dashed;\n"
                
                for node in nodes {
                    output += "        \(nodeToDOT(node, inCycle: cycleNodeIds.contains(node.id), isLeak: leakNodeIds.contains(node.id), isEscaping: escapingNodeIds.contains(node.id)))\n"
                }
                
                output += "    }\n\n"
            }
        } else {
            // Output all nodes
            for node in allNodes.prefix(options.maxNodes) {
                output += "    \(nodeToDOT(node, inCycle: cycleNodeIds.contains(node.id), isLeak: leakNodeIds.contains(node.id), isEscaping: escapingNodeIds.contains(node.id)))\n"
            }
        }
        
        output += "\n    // References\n"
        
        // Output references
        for reference in allReferences {
            output += "    \(referenceToDOT(reference, isCyclic: cycleNodeIds.contains(reference.from) && cycleNodeIds.contains(reference.to)))\n"
        }
        
        // Add legend if problems are highlighted
        if options.highlightProblems && (!cycles.isEmpty || !leaks.isEmpty || !escapingRefs.isEmpty) {
            output += """
            
                // Legend
                subgraph cluster_legend {
                    label="Legend";
                    style=filled;
                    fillcolor=lightgrey;
                    
                    legend_normal [label="Normal Node", fillcolor=lightblue];
                    legend_cycle [label="In Retain Cycle", fillcolor=red];
                    legend_leak [label="Potential Leak", fillcolor=orange];
                    legend_escaping [label="Escaping", fillcolor=yellow];
                }
            
            """
        }
        
        output += "}\n"
        return output
    }
    
    private func nodeToDOT(_ node: OwnershipGraph.Node, inCycle: Bool, isLeak: Bool, isEscaping: Bool) -> String {
        var color = "lightblue"
        if options.highlightProblems {
            if inCycle {
                color = "red"
            } else if isLeak {
                color = "orange"
            } else if isEscaping {
                color = "yellow"
            }
        }
        
        var label = sanitize(node.id)
        if options.includeNodeDetails {
            label += "\\n[\(node.type)]"
            label += "\\nlifetime: \(node.lifetime.rawValue)"
            if node.isReferenceType {
                label += "\\n(reference type)"
            }
        }
        
        return "\"\(sanitize(node.id))\" [label=\"\(label)\", fillcolor=\(color)];"
    }
    
    private func referenceToDOT(_ reference: OwnershipGraph.Reference, isCyclic: Bool) -> String {
        var style = ""
        var color = "black"
        
        switch reference.type {
        case .strong:
            style = "solid"
            color = isCyclic ? "red" : "black"
        case .weak:
            style = "dashed"
            color = "blue"
        case .unowned:
            style = "dotted"
            color = "purple"
        case .escaping:
            style = "bold"
            color = "orange"
        case .capture:
            style = "dashed"
            color = "green"
        default:
            style = "solid"
            color = "gray"
        }
        
        var label = reference.type.rawValue
        if options.includeReferenceDetails && reference.isEscaping {
            label += " (escaping)"
        }
        
        return "\"\(sanitize(reference.from))\" -> \"\(sanitize(reference.to))\" [label=\"\(label)\", style=\(style), color=\(color)];"
    }
    
    // MARK: - ASCII Format Export
    
    private func exportToASCII() async -> String {
        var output = """
        ╔══════════════════════════════════════════════════════════════╗
        ║                    OWNERSHIP GRAPH                           ║
        ╠══════════════════════════════════════════════════════════════╣
        
        """
        
        let allNodes = await graph.allNodes
        let allReferences = await graph.allReferences
        let statistics = await graph.statistics
        let cycles = await graph.findRetainCycles()
        let leaks = await graph.findMemoryLeaks()
        
        // Statistics section
        output += """
        ║ STATISTICS                                                   ║
        ║ ─────────────────────────────────────────────────────────── ║
        ║  Nodes:              \(String(format: "%-10d", statistics.nodeCount))                           ║
        ║  References:         \(String(format: "%-10d", statistics.referenceCount))                           ║
        ║  Escaping Refs:      \(String(format: "%-10d", statistics.escapingReferenceCount))                           ║
        ║  Retain Cycles:      \(String(format: "%-10d", statistics.retainCycleCount))                           ║
        ║  Potential Leaks:    \(String(format: "%-10d", statistics.memoryLeakCount))                           ║
        ╠══════════════════════════════════════════════════════════════╣
        
        """
        
        // Nodes section
        output += "║ NODES                                                        ║\n"
        output += "║ ─────────────────────────────────────────────────────────── ║\n"
        
        for (index, node) in allNodes.prefix(options.maxNodes).enumerated() {
            let marker = leaks.contains(where: { $0.id == node.id }) ? "⚠️" : 
                        (cycles.flatMap { $0 }.contains(where: { $0.from == node.id || $0.to == node.id }) ? "🔄" : "  ")
            let refType = node.isReferenceType ? "REF" : "VAL"
            output += "║ \(marker) [\(String(format: "%3d", index + 1))] \(truncate(node.id, to: 35)) (\(refType)) ║\n"
            if options.includeNodeDetails {
                output += "║       Type: \(truncate(node.type, to: 40))    ║\n"
                output += "║       Lifetime: \(node.lifetime.rawValue.padding(toLength: 37, withPad: " ", startingAt: 0)) ║\n"
            }
        }
        
        if allNodes.count > options.maxNodes {
            output += "║       ... and \(allNodes.count - options.maxNodes) more nodes                      ║\n"
        }
        
        output += "╠══════════════════════════════════════════════════════════════╣\n"
        
        // References section
        output += "║ REFERENCES                                                   ║\n"
        output += "║ ─────────────────────────────────────────────────────────── ║\n"
        
        // Group references by type
        let refsByType = Dictionary(grouping: allReferences) { $0.type }
        for (type, refs) in refsByType {
            let arrow = arrowForReferenceType(type)
            output += "║ \(type.rawValue.uppercased()) (\(refs.count))                                          ║\n"
            for ref in refs.prefix(5) {
                output += "║   \(truncate(ref.from, to: 20)) \(arrow) \(truncate(ref.to, to: 20)) ║\n"
            }
            if refs.count > 5 {
                output += "║   ... and \(refs.count - 5) more                                    ║\n"
            }
        }
        
        output += "╠══════════════════════════════════════════════════════════════╣\n"
        
        // Problems section
        if options.highlightProblems {
            output += "║ POTENTIAL ISSUES                                             ║\n"
            output += "║ ─────────────────────────────────────────────────────────── ║\n"
            
            if cycles.isEmpty && leaks.isEmpty {
                output += "║ ✅ No issues detected                                        ║\n"
            } else {
                if !cycles.isEmpty {
                    output += "║ 🔄 RETAIN CYCLES DETECTED: \(cycles.count)                              ║\n"
                    for (index, cycle) in cycles.prefix(3).enumerated() {
                        let cycleStr = cycle.map { $0.from }.joined(separator: " → ")
                        output += "║    Cycle \(index + 1): \(truncate(cycleStr, to: 43)) ║\n"
                    }
                }
                
                if !leaks.isEmpty {
                    output += "║ ⚠️ POTENTIAL MEMORY LEAKS: \(leaks.count)                             ║\n"
                    for leak in leaks.prefix(5) {
                        output += "║    • \(truncate(leak.id, to: 50))  ║\n"
                    }
                }
            }
        }
        
        output += """
        ╚══════════════════════════════════════════════════════════════╝
        
        Legend: 🔄 = In retain cycle  ⚠️ = Potential leak
                REF = Reference type  VAL = Value type
        """
        
        return output
    }
    
    private func arrowForReferenceType(_ type: OwnershipGraph.ReferenceType) -> String {
        switch type {
        case .strong: return "──▶"
        case .weak: return "- -▷"
        case .unowned: return "···▷"
        case .escaping: return "══▶"
        case .capture: return "──○"
        default: return "──→"
        }
    }
    
    // MARK: - JSON Format Export
    
    private func exportToJSON() async -> String {
        let allNodes = await graph.allNodes
        let allReferences = await graph.allReferences
        let statistics = await graph.statistics
        let cycles = await graph.findRetainCycles()
        let leaks = await graph.findMemoryLeaks()
        
        let jsonObject: [String: Any] = [
            "statistics": [
                "nodeCount": statistics.nodeCount,
                "referenceCount": statistics.referenceCount,
                "escapingReferenceCount": statistics.escapingReferenceCount,
                "retainCycleCount": statistics.retainCycleCount,
                "memoryLeakCount": statistics.memoryLeakCount
            ],
            "nodes": allNodes.map { node in
                [
                    "id": node.id,
                    "type": node.type,
                    "isReferenceType": node.isReferenceType,
                    "isEscaping": node.isEscaping,
                    "lifetime": node.lifetime.rawValue,
                    "location": [
                        "file": node.location.file.path,
                        "line": node.location.line,
                        "column": node.location.column
                    ]
                ] as [String: Any]
            },
            "references": allReferences.map { ref in
                [
                    "from": ref.from,
                    "to": ref.to,
                    "type": ref.type.rawValue,
                    "isEscaping": ref.isEscaping,
                    "isWeak": ref.isWeak,
                    "location": [
                        "file": ref.location.file.path,
                        "line": ref.location.line,
                        "column": ref.location.column
                    ]
                ] as [String: Any]
            },
            "issues": [
                "retainCycles": cycles.map { cycle in
                    cycle.map { [$0.from, $0.to] }
                },
                "potentialLeaks": leaks.map { $0.id }
            ]
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "{\"error\": \"Failed to serialize graph\"}"
    }
    
    // MARK: - Mermaid Format Export
    
    private func exportToMermaid() async -> String {
        var output = "graph TD\n"
        
        let allNodes = await graph.allNodes
        let allReferences = await graph.allReferences
        let cycles = await graph.findRetainCycles()
        let leaks = await graph.findMemoryLeaks()
        
        let cycleNodeIds = Set(cycles.flatMap { $0.flatMap { [$0.from, $0.to] } })
        let leakNodeIds = Set(leaks.map { $0.id })
        
        // Define node styles
        output += "    %% Styles\n"
        output += "    classDef normal fill:#lightblue,stroke:#333\n"
        output += "    classDef cycle fill:#ff6b6b,stroke:#333\n"
        output += "    classDef leak fill:#ffa500,stroke:#333\n"
        output += "    classDef escaping fill:#ffff00,stroke:#333\n\n"
        
        // Output nodes
        output += "    %% Nodes\n"
        for node in allNodes.prefix(options.maxNodes) {
            let nodeId = mermaidSafe(node.id)
            let label = options.includeNodeDetails ? 
                "\(node.type)\\n\(node.lifetime.rawValue)" : node.type
            
            if node.isReferenceType {
                output += "    \(nodeId)[\"\(label)\"]\n"
            } else {
                output += "    \(nodeId)(\"\(label)\")\n"
            }
            
            // Apply style class
            if cycleNodeIds.contains(node.id) {
                output += "    class \(nodeId) cycle\n"
            } else if leakNodeIds.contains(node.id) {
                output += "    class \(nodeId) leak\n"
            } else if node.isEscaping {
                output += "    class \(nodeId) escaping\n"
            } else {
                output += "    class \(nodeId) normal\n"
            }
        }
        
        output += "\n    %% References\n"
        
        // Output references
        for reference in allReferences {
            let fromId = mermaidSafe(reference.from)
            let toId = mermaidSafe(reference.to)
            let arrow = mermaidArrowForType(reference.type)
            let label = options.includeReferenceDetails ? "|" + reference.type.rawValue + "|" : ""
            
            output += "    \(fromId) \(arrow)\(label) \(toId)\n"
        }
        
        return output
    }
    
    private func mermaidArrowForType(_ type: OwnershipGraph.ReferenceType) -> String {
        switch type {
        case .strong: return "-->"
        case .weak: return "-.->"
        case .unowned: return "..>"
        case .escaping: return "==>"
        case .capture: return "--o"
        default: return "-->"
        }
    }
    
    private func mermaidSafe(_ id: String) -> String {
        return id.replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "#", with: "_")
    }
    
    // MARK: - Helper Methods
    
    private func sanitize(_ string: String) -> String {
        return string.replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
    
    private func truncate(_ string: String, to length: Int) -> String {
        if string.count <= length {
            return string.padding(toLength: length, withPad: " ", startingAt: 0)
        }
        return String(string.prefix(length - 3)) + "..."
    }
}

// MARK: - OwnershipGraph Extension for Visualization

extension OwnershipGraph {
    /// Create a visualizer for this graph
    public func visualizer(options: OwnershipGraphVisualizer.Options = .init()) -> OwnershipGraphVisualizer {
        return OwnershipGraphVisualizer(graph: self, options: options)
    }
    
    /// Quick export to DOT format
    public func exportToDOT() async -> String {
        return await visualizer().export(format: .dot)
    }
    
    /// Quick export to ASCII format
    public func exportToASCII() async -> String {
        return await visualizer().export(format: .ascii)
    }
    
    /// Quick export to JSON format
    public func exportToJSON() async -> String {
        return await visualizer().export(format: .json)
    }
    
    /// Quick export to Mermaid format
    public func exportToMermaid() async -> String {
        return await visualizer().export(format: .mermaid)
    }
}
