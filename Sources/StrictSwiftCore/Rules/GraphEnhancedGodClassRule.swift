import Foundation
import SwiftSyntax

/// Enhanced God Class detection using GlobalReferenceGraph for cross-file analysis
///
/// This rule extends the basic GodClassRule with additional coupling metrics:
/// - Afferent coupling: How many types depend on this class
/// - Efferent coupling: How many types this class depends on
/// - Total coupling score for more accurate detection
///
/// Enable with `useEnhancedRules: true` in strictswift.yml
public final class GraphEnhancedGodClassRule: Rule {
    public var id: String { "god_class_enhanced" }
    public var name: String { "God Class (Enhanced)" }
    public var description: String { "Detects god classes using cross-file coupling analysis" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { false } // Opt-in via useEnhancedRules

    // Configuration thresholds
    private let maxMethods: Int = 15
    private let maxProperties: Int = 10
    private let maxAfferentCoupling: Int = 10
    private let maxEfferentCoupling: Int = 12
    private let maxTotalCoupling: Int = 20

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        guard context.configuration.useEnhancedRules else { return [] }

        var violations: [Violation] = []
        let graph = context.globalGraph()

        // Find type symbols and their children
        for symbol in sourceFile.symbols where symbol.kind.isTypeDeclaration {
            // Count children (methods and properties)
            let children = sourceFile.symbols.filter { $0.parentID == symbol.id }
            let methodCount = children.filter { $0.kind == .function }.count
            let propertyCount = children.filter { $0.kind == .variable }.count

            // Get coupling from graph
            let afferent = graph.getReferencedBy(symbol.id).count
            let efferent = graph.getReferences(symbol.id).count
            let totalCoupling = afferent + efferent

            var issues: [String] = []
            if methodCount > maxMethods { issues.append("methods: \(methodCount)") }
            if propertyCount > maxProperties { issues.append("properties: \(propertyCount)") }
            if afferent > maxAfferentCoupling { issues.append("afferent: \(afferent)") }
            if efferent > maxEfferentCoupling { issues.append("efferent: \(efferent)") }
            if totalCoupling > maxTotalCoupling { issues.append("coupling: \(totalCoupling)") }

            guard issues.count >= 2 else { continue }

            let violation = ViolationBuilder(ruleId: id, category: category, location: symbol.location)
                .message("\(symbol.kind) '\(symbol.name)' has too many responsibilities: \(issues.joined(separator: ", "))")
                .suggestFix("Consider breaking '\(symbol.name)' into smaller, focused types")
                .severity(defaultSeverity)
                .build()
            violations.append(violation)
        }

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

extension SymbolKind {
    var isTypeDeclaration: Bool {
        switch self {
        case .class, .struct, .actor: return true
        default: return false
        }
    }
}
