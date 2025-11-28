import Foundation

/// Xcode-compatible reporter that outputs warnings/errors in a format Xcode can parse
/// Format: <file>:<line>:<column>: <severity>: <message> [<ruleId>]
/// This allows StrictSwift findings to appear as inline warnings in Xcode's issue navigator
public struct XcodeReporter: Reporter {
    
    public init() {}
    
    public func generateReport(_ violations: [Violation]) throws -> String {
        return try generateReport(violations, metadata: nil)
    }
    
    public func generateReport(_ violations: [Violation], metadata: AnalysisMetadata?) throws -> String {
        let lines = violations.map { violation -> String in
            let severity = xcodeSeverity(from: violation.severity)
            let file = violation.location.file.path
            let line = violation.location.line
            let column = violation.location.column
            let message = violation.message
            let ruleId = violation.ruleId
            
            return "\(file):\(line):\(column): \(severity): \(message) [\(ruleId)]"
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func xcodeSeverity(from severity: DiagnosticSeverity) -> String {
        switch severity {
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .info, .hint:
            return "note"
        }
    }
}
