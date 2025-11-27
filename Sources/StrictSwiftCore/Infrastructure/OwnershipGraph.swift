import Foundation
import SwiftSyntax

/// Tracks ownership relationships and reference lifetimes for memory safety analysis
/// SAFETY: @unchecked Sendable is safe because all mutable state (references, nodes)
/// is protected by NSLock for thread-safe access.
public final class OwnershipGraph: @unchecked Sendable {
    /// Represents a reference between objects
    public struct Reference: Codable, Hashable, Sendable {
        public let from: String
        public let to: String
        public let type: ReferenceType
        public let location: Location
        public let isEscaping: Bool
        public let isWeak: Bool

        public init(from: String, to: String, type: ReferenceType, location: Location, isEscaping: Bool = false, isWeak: Bool = false) {
            self.from = from
            self.to = to
            self.type = type
            self.location = location
            self.isEscaping = isEscaping
            self.isWeak = isWeak
        }
    }

    /// Types of references between objects
    public enum ReferenceType: String, Codable, CaseIterable, Sendable {
        case strong = "strong"
        case weak = "weak"
        case unowned = "unowned"
        case escaping = "escaping"
        case nonEscaping = "non_escaping"
        case capture = "capture"
        case parameter = "parameter"
        case returnValue = "return_value"
        case assignment = "assignment"
    }

    /// Represents an object in the ownership graph
    public struct Node: Codable, Hashable, Sendable {
        public let id: String
        public let type: String
        public let location: Location
        public let isReferenceType: Bool
        public let isEscaping: Bool
        public let lifetime: Lifetime

        public init(id: String, type: String, location: Location, isReferenceType: Bool, isEscaping: Bool = false, lifetime: Lifetime = .automatic) {
            self.id = id
            self.type = type
            self.location = location
            self.isReferenceType = isReferenceType
            self.isEscaping = isEscaping
            self.lifetime = lifetime
        }
    }

    /// Object lifetime categories
    public enum Lifetime: String, Codable, CaseIterable, Sendable {
        case automatic = "automatic"
        case manual = "manual"
        case globalStatic = "static"
        case weak = "weak"
        case unowned = "unowned"
        case escaping = "escaping"
    }

    /// Graph state - use actor isolation for thread safety
    private actor GraphState {
        var nodes: [String: Node] = [:]
        var references: Set<Reference> = []
        var escapingReferences: Set<Reference> = []

        func addNode(_ node: Node) {
            nodes[node.id] = node
        }

        func addReference(_ reference: Reference) {
            references.insert(reference)
            if reference.isEscaping {
                escapingReferences.insert(reference)
            }
        }

        func getAllNodes() -> [Node] {
            Array(nodes.values)
        }

        func getAllReferences() -> [Reference] {
            Array(references)
        }

        func getAllEscapingReferences() -> [Reference] {
            Array(escapingReferences)
        }

        func clear() {
            nodes.removeAll()
            references.removeAll()
            escapingReferences.removeAll()
        }
    }

    private let graphState = GraphState()

    public init() {}

    /// Add a node to the graph (async - use addNodeSync for synchronous contexts)
    /// NOTE: This method is deprecated. Use addNodeSync for reliable node addition.
    @available(*, deprecated, message: "Use addNodeSync for reliable node addition")
    public func addNode(_ node: Node) {
        // Fire-and-forget pattern removed - now synchronously adds
        // Using synchronous dispatch to ensure data is not lost
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await graphState.addNode(node)
            semaphore.signal()
        }
        semaphore.wait()
    }

    /// Add a reference to the graph (async - use addReferenceSync for synchronous contexts)
    /// NOTE: This method is deprecated. Use addReferenceSync for reliable reference addition.
    @available(*, deprecated, message: "Use addReferenceSync for reliable reference addition")
    public func addReference(_ reference: Reference) {
        // Fire-and-forget pattern removed - now synchronously adds
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await graphState.addReference(reference)
            semaphore.signal()
        }
        semaphore.wait()
    }

    /// Add a node to the graph (synchronous for immediate analysis)
    public func addNodeSync(_ node: Node) async {
        await graphState.addNode(node)
    }

    /// Add a reference to the graph (synchronous for immediate analysis)
    public func addReferenceSync(_ reference: Reference) async {
        await graphState.addReference(reference)
    }

    /// Get all nodes
    public var allNodes: [Node] {
        get async {
            await graphState.getAllNodes()
        }
    }

    /// Get all references
    public var allReferences: [Reference] {
        get async {
            await graphState.getAllReferences()
        }
    }

    /// Get all escaping references
    public var allEscapingReferences: [Reference] {
        get async {
            await graphState.getAllEscapingReferences()
        }
    }

    /// Get references from a specific node
    public func references(from nodeId: String) async -> [Reference] {
        let allRefs = await graphState.getAllReferences()
        return allRefs.filter { $0.from == nodeId }
    }

    /// Get references to a specific node
    public func references(to nodeId: String) async -> [Reference] {
        let allRefs = await graphState.getAllReferences()
        return allRefs.filter { $0.to == nodeId }
    }

    /// Check if a node has escaping references
    public func hasEscapingReferences(nodeId: String) async -> Bool {
        let escapingRefs = await graphState.getAllEscapingReferences()
        return escapingRefs.contains { $0.from == nodeId }
    }

    /// Find potential use-after-free scenarios
    public func findUseAfterFree() async -> [(node: Node, reference: Reference)] {
        let allNodes = await graphState.getAllNodes()
        let allRefs = await graphState.getAllReferences()

        var scenarios: [(Node, Reference)] = []

        for node in allNodes {
            if node.isReferenceType {
                // Check for weak/unowned references that might dangle
                let weakRefs = allRefs.filter { $0.to == node.id && ($0.isWeak || $0.type == .unowned) }
                for reference in weakRefs {
                    scenarios.append((node, reference))
                }
            }
        }

        return scenarios
    }

    /// Find potential memory leaks
    public func findMemoryLeaks() async -> [Node] {
        let allNodes = await graphState.getAllNodes()
        let allRefs = await graphState.getAllReferences()

        var leakedNodes: [Node] = []

        for node in allNodes {
            if node.isReferenceType {
                let outgoingRefs = allRefs.filter { $0.from == node.id }
                let incomingRefs = allRefs.filter { $0.to == node.id }

                // Node with no outgoing references but still referenced might be leaked
                if outgoingRefs.isEmpty && !incomingRefs.isEmpty {
                    leakedNodes.append(node)
                }
            }
        }

        return leakedNodes
    }

    /// Find retain cycles
    public func findRetainCycles() async -> [[Reference]] {
        let allNodes = await graphState.getAllNodes()
        let allRefs = await graphState.getAllReferences()

        var cycles: [[Reference]] = []
        var visited = Set<String>()

        for node in allNodes.filter({ $0.isReferenceType }) {
            if !visited.contains(node.id) {
                let path = await findCycle(from: node.id, visited: &visited, path: [], allRefs: allRefs)
                if let cycle = path {
                    cycles.append(cycle)
                }
            }
        }

        return cycles
    }

    /// Find escaping references that could cause lifetime issues
    public func findEscapingReferences() async -> [Reference] {
        return await graphState.getAllEscapingReferences()
    }

    /// Check for exclusive access violations
    public func findExclusiveAccessViolations() async -> [(access1: Reference, access2: Reference)] {
        let allRefs = await graphState.getAllReferences()

        var violations: [(Reference, Reference)] = []

        // Group references by target
        let refsByTarget = Dictionary(grouping: allRefs) { $0.to }

        for (target, targetRefs) in refsByTarget {
            // Skip function calls and initializers - they can't have exclusive access violations
            // Function calls: analyze(sourceFile), foo(), Set<T>()
            guard !isFunctionCallOrInitializer(target) else { continue }
            
            // Skip 'self' - accessing self from different methods is not an exclusive access violation
            // Real exclusive access to self would be overlapping inout &self, which is rare
            guard target != "self" else { continue }
            
            // Skip non-storage targets (complex expressions, subscripts, etc.)
            guard isStoredPropertyOrVariable(target) else { continue }
            
            // Find multiple mutable accesses to the same target
            let mutableRefs = targetRefs.filter { isMutableReference($0) }
            if mutableRefs.count > 1 {
                // Check for overlapping access
                for i in 0..<mutableRefs.count {
                    for j in (i+1)..<mutableRefs.count {
                        let ref1 = mutableRefs[i]
                        let ref2 = mutableRefs[j]

                        if couldOverlap(ref1.location, ref2.location) {
                            violations.append((ref1, ref2))
                        }
                    }
                }
            }
        }

        return violations
    }
    
    /// Checks if a target string represents a function call or initializer
    private func isFunctionCallOrInitializer(_ target: String) -> Bool {
        // Function calls: analyze(sourceFile), foo(), bar.baz(), Set<T>()
        guard target.contains("(") && target.hasSuffix(")") else { return false }
        
        // Check for balanced parentheses
        var depth = 0
        for char in target {
            if char == "(" { depth += 1 }
            else if char == ")" { depth -= 1 }
            if depth < 0 { return false }
        }
        return depth == 0
    }
    
    /// Checks if a target represents a stored property or variable access
    private func isStoredPropertyOrVariable(_ target: String) -> Bool {
        // Simple identifier: count, items, foo
        let simpleIdentifier = target.range(of: #"^[a-zA-Z_][a-zA-Z0-9_]*$"#, options: .regularExpression) != nil
        if simpleIdentifier { return true }
        
        // Property access: self.property, object.property (one dot only)
        let propertyAccess = target.range(of: #"^[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*$"#, options: .regularExpression) != nil
        if propertyAccess { return true }
        
        return false
    }

    /// Clear the graph
    public func clear() async {
        await graphState.clear()
    }

    /// Merge another ownership graph
    public func merge(_ other: OwnershipGraph) async {
        let otherNodes = await other.allNodes
        let otherRefs = await other.allReferences
        // Note: escaping references are included in the regular references merge

        // Update current graph state with merged data
        for node in otherNodes {
            await graphState.addNode(node)
        }

        for reference in otherRefs {
            await graphState.addReference(reference)
        }
    }

    /// Get statistics about the graph
    public var statistics: OwnershipStatistics {
        get async {
            let allNodes = await graphState.getAllNodes()
            let allRefs = await graphState.getAllReferences()
            let escapingRefs = await graphState.getAllEscapingReferences()
            let cycles = await findRetainCycles()
            let leaks = await findMemoryLeaks()

            return OwnershipStatistics(
                nodeCount: allNodes.count,
                referenceCount: allRefs.count,
                escapingReferenceCount: escapingRefs.count,
                referenceTypeCount: ReferenceType.allCases.reduce(into: [:]) { counts, type in
                    counts[type] = allRefs.filter { $0.type == type }.count
                },
                retainCycleCount: cycles.count,
                memoryLeakCount: leaks.count
            )
        }
    }

    // MARK: - Private Helper Methods

    private func findCycle(from nodeId: String, visited: inout Set<String>, path: [Reference], allRefs: [Reference]) async -> [Reference]? {
        if visited.contains(nodeId) {
            return []
        }

        visited.insert(nodeId)
        let outgoingRefs = allRefs.filter { $0.from == nodeId }

        for ref in outgoingRefs {
            if ref.type == .strong || ref.type == .escaping {
                let newPath = path + [ref]
                if newPath.count > 1, let firstRef = newPath.first, firstRef.from == ref.to {
                    return newPath // Found cycle
                }

                if let cycle = await findCycle(from: ref.to, visited: &visited, path: newPath, allRefs: allRefs) {
                    return cycle
                }
            }
        }

        return nil
    }

    /// Determines if a reference represents a mutable (write) access to its TARGET.
    /// Note: `.assignment` means the SOURCE is being written to, but the TARGET is being READ.
    /// For exclusive access violations, we care about writes TO the target, not reads FROM it.
    private func isMutableReference(_ reference: Reference) -> Bool {
        switch reference.type {
        // These types indicate the SOURCE is written/captured, but TARGET is only READ
        case .assignment, .strong, .capture, .parameter, .returnValue:
            return false
        // Escaping references could potentially be mutated through the escaped reference
        case .escaping:
            return true
        // Weak/unowned are explicitly non-mutating
        case .weak, .unowned, .nonEscaping:
            return false
        }
    }

    private func couldOverlap(_ location1: Location, _ location2: Location) -> Bool {
        // Simple heuristic - if they're in the same function, they could overlap
        // In a real implementation, this would be more sophisticated with control flow analysis
        return abs(location1.line - location2.line) <= 10
    }
}

/// Statistics about the ownership graph
public struct OwnershipStatistics: Codable, Sendable {
    public let nodeCount: Int
    public let referenceCount: Int
    public let escapingReferenceCount: Int
    public let referenceTypeCount: [OwnershipGraph.ReferenceType: Int]
    public let retainCycleCount: Int
    public let memoryLeakCount: Int

    public init(nodeCount: Int, referenceCount: Int, escapingReferenceCount: Int, referenceTypeCount: [OwnershipGraph.ReferenceType: Int], retainCycleCount: Int, memoryLeakCount: Int) {
        self.nodeCount = nodeCount
        self.referenceCount = referenceCount
        self.escapingReferenceCount = escapingReferenceCount
        self.referenceTypeCount = referenceTypeCount
        self.retainCycleCount = retainCycleCount
        self.memoryLeakCount = memoryLeakCount
    }
}