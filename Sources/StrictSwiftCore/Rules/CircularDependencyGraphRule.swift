import Foundation
import SwiftSyntax

/// Enhanced circular dependency detection using GlobalReferenceGraph
///
/// This rule uses the actual symbol reference graph to detect cycles,
/// providing accurate cross-file dependency analysis.
///
/// Enable with `useEnhancedRules: true` in strictswift.yml
public final class CircularDependencyGraphRule: Rule {
    public var id: String { "circular_dependency_graph" }
    public var name: String { "Circular Dependency (Graph)" }
    public var description: String { "Detects circular dependencies using cross-file symbol graph" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { false } // Opt-in via useEnhancedRules

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        guard context.configuration.useEnhancedRules else { return [] }

        var violations: [Violation] = []
        let graph = context.globalGraph()

        // Check each type in this file for cycles
        for symbol in sourceFile.symbols where symbol.kind.isTypeDeclaration {
            if let cycle = detectCycle(from: symbol.id, in: graph) {
                let cycleDescription = formatCycle(cycle)
                
                let violation = ViolationBuilder(ruleId: id, category: category, location: symbol.location)
                    .message("Circular dependency detected: \(cycleDescription)")
                    .suggestFix("Break the cycle by extracting a shared protocol or removing one dependency")
                    .severity(defaultSeverity)
                    .build()
                violations.append(violation)
            }
        }

        return violations
    }

    /// Detects a cycle starting from the given symbol using DFS
    private func detectCycle(from startID: SymbolID, in graph: GlobalReferenceGraph) -> [SymbolID]? {
        var visited = Set<SymbolID>()
        var path: [SymbolID] = []
        var inPath = Set<SymbolID>()
        
        func dfs(_ current: SymbolID) -> [SymbolID]? {
            if inPath.contains(current) {
                // Found a cycle - extract the cycle from path
                if let cycleStart = path.firstIndex(where: { $0 == current }) {
                    return Array(path[cycleStart...]) + [current]
                }
                return nil
            }
            
            if visited.contains(current) { return nil }
            
            visited.insert(current)
            inPath.insert(current)
            path.append(current)
            
            // Only follow type references (not all references)
            let dependencies = graph.getReferences(current).filter { isTypeSymbol($0) }
            
            for dep in dependencies {
                if let cycle = dfs(dep) {
                    return cycle
                }
            }
            
            path.removeLast()
            inPath.remove(current)
            return nil
        }
        
        return dfs(startID)
    }

    /// Check if a symbol ID represents a type (class, struct, enum, actor)
    private func isTypeSymbol(_ id: SymbolID) -> Bool {
        let kind = id.kind
        return kind == .class || kind == .struct || kind == .enum || kind == .actor
    }

    /// Format cycle as readable string
    private func formatCycle(_ cycle: [SymbolID]) -> String {
        let names = cycle.map { $0.qualifiedName.components(separatedBy: ".").last ?? $0.qualifiedName }
        return names.joined(separator: " → ")
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}
