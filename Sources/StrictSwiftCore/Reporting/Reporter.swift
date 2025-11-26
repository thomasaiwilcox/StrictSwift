import Foundation

/// Metadata about the analysis run
public struct AnalysisMetadata: Sendable {
    /// The semantic analysis mode that was used
    public let semanticMode: SemanticMode
    
    /// Where the mode was configured from
    public let modeSource: String
    
    /// Whether the mode was degraded from a higher request
    public let degradedFrom: SemanticMode?
    
    /// Reason for degradation if any
    public let degradationReason: String?
    
    public init(
        semanticMode: SemanticMode,
        modeSource: String,
        degradedFrom: SemanticMode? = nil,
        degradationReason: String? = nil
    ) {
        self.semanticMode = semanticMode
        self.modeSource = modeSource
        self.degradedFrom = degradedFrom
        self.degradationReason = degradationReason
    }
    
    /// Create from SemanticModeResolver.ResolvedConfiguration
    public init(from resolved: SemanticModeResolver.ResolvedConfiguration) {
        self.semanticMode = resolved.effectiveMode
        self.modeSource = resolved.modeSource.rawValue
        self.degradedFrom = resolved.degradation?.requestedMode
        self.degradationReason = resolved.degradation?.reason
    }
    
    /// Default metadata when semantic analysis is not configured
    public static let `default` = AnalysisMetadata(
        semanticMode: .off,
        modeSource: "Default"
    )
}

/// Protocol for formatting and outputting analysis results
public protocol Reporter: Sendable {
    /// Generate report for violations
    func generateReport(_ violations: [Violation]) throws -> String
    
    /// Generate report for violations with analysis metadata
    func generateReport(_ violations: [Violation], metadata: AnalysisMetadata?) throws -> String
}

/// Default implementation for backward compatibility
extension Reporter {
    public func generateReport(_ violations: [Violation], metadata: AnalysisMetadata?) throws -> String {
        // Default: ignore metadata, just call the basic method
        return try generateReport(violations)
    }
}