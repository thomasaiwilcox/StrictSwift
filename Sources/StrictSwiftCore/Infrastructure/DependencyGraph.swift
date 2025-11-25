import Foundation

/// Represents a dependency between two modules or components
public struct Dependency: Hashable, Sendable {
    public let from: String  // Source module/component
    public let to: String    // Target module/component
    public let type: DependencyType
    public let strength: DependencyStrength

    public init(from: String, to: String, type: DependencyType, strength: DependencyStrength) {
        self.from = from
        self.to = to
        self.type = type
        self.strength = strength
    }
}

/// Types of dependencies that can be detected
public enum DependencyType: String, CaseIterable, Sendable {
    case importModule = "import_module"
    case classInheritance = "class_inheritance"
    case protocolConformance = "protocol_conformance"
    case composition = "composition"
    case functionCall = "function_call"
    case propertyAccess = "property_access"
    case `extension` = "extension"
    case typeReference = "type_reference"
}

/// Strength of dependency relationship
public enum DependencyStrength: Int, CaseIterable, Sendable {
    case weak = 1      // Optional or loosely coupled
    case medium = 2    // Standard coupling
    case strong = 3    // Required, tightly coupled
}

/// A node in the dependency graph representing a module or component
public struct DependencyNode: Hashable, Sendable {
    public let name: String
    public let type: NodeType
    public let filePath: String
    public var dependencies: Set<Dependency>
    public var dependents: Set<String>  // Nodes that depend on this node

    public init(name: String, type: NodeType, filePath: String) {
        self.name = name
        self.type = type
        self.filePath = filePath
        self.dependencies = []
        self.dependents = []
    }
}

/// Types of nodes in the dependency graph
public enum NodeType: String, CaseIterable, Sendable {
    case module = "module"
    case file = "file"
    case `class` = "class"
    case `struct` = "struct"
    case `protocol` = "protocol"
    case `enum` = "enum"
    case function = "function"
    case `extension` = "extension"
}

/// Dependency graph for analyzing relationships between code components
/// SAFETY: @unchecked Sendable is safe because all mutable state (nodes, dependencies)
/// is protected by NSLock for thread-safe access.
public final class DependencyGraph: @unchecked Sendable {
    private let lock = NSLock()
    private var nodes: [String: DependencyNode] = [:]
    private var dependencies: Set<Dependency> = []

    public init() {}

    /// Add a node to the graph
    public func addNode(_ node: DependencyNode) {
        lock.lock()
        defer { lock.unlock() }
        nodes[node.name] = node
    }

    /// Add a dependency between two nodes
    public func addDependency(_ dependency: Dependency) {
        lock.lock()
        defer { lock.unlock() }

        dependencies.insert(dependency)

        // Update source node's dependencies
        if var sourceNode = nodes[dependency.from] {
            sourceNode.dependencies.insert(dependency)
            nodes[dependency.from] = sourceNode
        }

        // Update target node's dependents
        if var targetNode = nodes[dependency.to] {
            targetNode.dependents.insert(dependency.from)
            nodes[dependency.to] = targetNode
        }
    }

    /// Get all nodes in the graph
    public var allNodes: [DependencyNode] {
        lock.lock()
        defer { lock.unlock() }
        return Array(nodes.values)
    }

    /// Get all dependencies in the graph
    public var allDependencies: Set<Dependency> {
        lock.lock()
        defer { lock.unlock() }
        return dependencies
    }

    /// Find circular dependencies in the graph
    public func findCycles() -> [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return findCyclesUnsafe()
    }

    /// Internal implementation that doesn't acquire the lock (caller must hold the lock)
    private func findCyclesUnsafe() -> [[String]] {
        var cycles: [[String]] = []
        var visited: Set<String> = []
        var recursionStack: Set<String> = []
        var path: [String] = []

        for node in nodes.keys {
            if !visited.contains(node) {
                findCyclesFromNode(
                    node: node,
                    visited: &visited,
                    recursionStack: &recursionStack,
                    path: &path,
                    cycles: &cycles
                )
            }
        }

        return cycles
    }

    private func findCyclesFromNode(
        node: String,
        visited: inout Set<String>,
        recursionStack: inout Set<String>,
        path: inout [String],
        cycles: inout [[String]]
    ) {
        visited.insert(node)
        recursionStack.insert(node)
        path.append(node)

        if let dependencies = nodes[node]?.dependencies {
            for dependency in dependencies {
                let target = dependency.to

                if !visited.contains(target) {
                    findCyclesFromNode(
                        node: target,
                        visited: &visited,
                        recursionStack: &recursionStack,
                        path: &path,
                        cycles: &cycles
                    )
                } else if recursionStack.contains(target) {
                    // Found a cycle
                    if let startIndex = path.firstIndex(of: target) {
                        let cycle = Array(path[startIndex...])
                        cycles.append(cycle)
                    }
                }
            }
        }

        recursionStack.remove(node)
        path.removeLast()
    }

    /// Check if a dependency exists between two nodes
    public func hasDependency(from: String, to: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return dependencies.contains { $0.from == from && $0.to == to }
    }

    /// Get all dependencies from a specific node
    public func dependencies(from: String) -> Set<Dependency> {
        lock.lock()
        defer { lock.unlock() }
        return nodes[from]?.dependencies ?? []
    }

    /// Get all nodes that depend on a specific node
    public func dependents(on: String) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return nodes[on]?.dependents ?? []
    }

    /// Calculate the depth of a node in the dependency hierarchy
    public func dependencyDepth(for node: String) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var visited: Set<String> = []
        return calculateDepth(node: node, visited: &visited)
    }

    private func calculateDepth(node: String, visited: inout Set<String>) -> Int {
        if visited.contains(node) { return 0 }
        visited.insert(node)

        guard let nodeDependencies = nodes[node]?.dependencies else { return 0 }

        let maxDepth = nodeDependencies.map { dependency in
            calculateDepth(node: dependency.to, visited: &visited) + 1
        }.max() ?? 0

        return maxDepth
    }

    /// Find the longest dependency chain in the graph
    public func longestDependencyChain() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var longestChain: [String] = []

        for node in nodes.keys {
            let chain = findLongestChain(from: node, visited: Set())
            if chain.count > longestChain.count {
                longestChain = chain
            }
        }

        return longestChain
    }

    private func findLongestChain(from node: String, visited: Set<String>) -> [String] {
        if visited.contains(node) { return [] }

        guard let nodeDependencies = nodes[node]?.dependencies else { return [node] }

        var longestChain: [String] = [node]
        let newVisited = visited.union([node])

        for dependency in nodeDependencies {
            let chain = findLongestChain(from: dependency.to, visited: newVisited)
            if chain.count > longestChain.count - 1 {
                longestChain = [node] + chain
            }
        }

        return longestChain
    }

    /// Generate a textual representation of the dependency graph
    public func generateDescription() -> String {
        lock.lock()
        defer { lock.unlock() }

        var description = "Dependency Graph:\n"
        description += "Nodes: \(nodes.count)\n"
        description += "Dependencies: \(dependencies.count)\n\n"

        for (name, node) in nodes.sorted(by: { $0.key < $1.key }) {
            description += "\(name) (\(node.type.rawValue))\n"

            if !node.dependencies.isEmpty {
                description += "  depends on:\n"
                for dependency in node.dependencies.sorted(by: { $0.to < $1.to }) {
                    description += "    - \(dependency.to) (\(dependency.type.rawValue), strength: \(dependency.strength.rawValue))\n"
                }
            }

            if !node.dependents.isEmpty {
                description += "  dependents:\n"
                for dependent in node.dependents.sorted() {
                    description += "    - \(dependent)\n"
                }
            }
            description += "\n"
        }

        let cycles = findCyclesUnsafe()
        if !cycles.isEmpty {
            description += "Circular Dependencies:\n"
            for (index, cycle) in cycles.enumerated() {
                let firstElement = cycle.first ?? ""
                description += "  Cycle \(index + 1): \(cycle.joined(separator: " -> ")) -> \(firstElement)\n"
            }
        }

        return description
    }

    /// Clear the entire graph
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        nodes.removeAll()
        dependencies.removeAll()
    }

    /// Merge another dependency graph into this one
    public func merge(_ other: DependencyGraph) {
        lock.lock()
        defer { lock.unlock() }
        other.lock.lock()
        defer { other.lock.unlock() }

        // Merge nodes
        for (_, node) in other.nodes {
            if nodes[node.name] == nil {
                nodes[node.name] = node
            } else if var existingNode = nodes[node.name] {
                // Merge dependencies for existing node
                existingNode.dependencies.formUnion(node.dependencies)
                existingNode.dependents.formUnion(node.dependents)
                nodes[node.name] = existingNode
            }
        }

        // Merge dependencies
        dependencies.formUnion(other.dependencies)
    }

    /// Remove a specific dependency (for testing purposes)
    internal func removeDependency(_ dependency: Dependency) {
        lock.lock()
        defer { lock.unlock() }
        dependencies.remove(dependency)

        // Update source node's dependencies
        if var sourceNode = nodes[dependency.from] {
            sourceNode.dependencies.remove(dependency)
            nodes[dependency.from] = sourceNode
        }

        // Update target node's dependents
        if var targetNode = nodes[dependency.to] {
            targetNode.dependents.remove(dependency.from)
            nodes[dependency.to] = targetNode
        }
    }
}