import Foundation
import SwiftSyntax

/// Measures and reports coupling metrics using GlobalReferenceGraph
///
/// Metrics calculated:
/// - Afferent Coupling (Ca): Number of types that depend on this module/type
/// - Efferent Coupling (Ce): Number of types this module/type depends on
/// - Instability (I): Ce / (Ca + Ce) - ranges from 0 (stable) to 1 (unstable)
///
/// Enable with `useEnhancedRules: true` in strictswift.yml
public final class CouplingMetricsRule: Rule {
    public var id: String { "coupling_metrics" }
    public var name: String { "Coupling Metrics" }
    public var description: String { "Detects types with problematic coupling characteristics" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { false } // Opt-in via useEnhancedRules

    // Thresholds for violation reporting
    private let maxAfferentCoupling: Int = 15  // Too many dependents = fragile
    private let maxEfferentCoupling: Int = 12  // Too many dependencies = unstable
    private let instabilityWarningThreshold: Double = 0.8  // High instability concern

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        guard context.configuration.useEnhancedRules else { return [] }

        var violations: [Violation] = []
        let graph = context.globalGraph()

        for symbol in sourceFile.symbols where symbol.kind.isTypeDeclaration {
            let afferent = graph.getReferencedBy(symbol.id).count
            let efferent = graph.getReferences(symbol.id).count
            let total = afferent + efferent
            
            // Calculate instability (Ce / (Ca + Ce))
            let instability: Double = total > 0 ? Double(efferent) / Double(total) : 0.0

            var issues: [String] = []
            
            // Check for problematic coupling patterns
            if afferent > maxAfferentCoupling {
                issues.append("high afferent coupling (\(afferent) dependents) - changes here affect many types")
            }
            
            if efferent > maxEfferentCoupling {
                issues.append("high efferent coupling (\(efferent) dependencies) - fragile to changes in dependencies")
            }
            
            // High instability with high afferent coupling is particularly problematic
            if instability > instabilityWarningThreshold && afferent > 5 {
                issues.append(String(format: "unstable (I=%.2f) with many dependents - violates Stable Dependencies Principle", instability))
            }

            guard !issues.isEmpty else { continue }

            let violation = ViolationBuilder(ruleId: id, category: category, location: symbol.location)
                .message("\(symbol.kind) '\(symbol.name)': \(issues.joined(separator: "; "))")
                .suggestFix("Consider extracting stable abstractions or reducing dependencies")
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
