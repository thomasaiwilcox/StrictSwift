import Foundation

/// Configuration options for agent reporter
public struct AgentReporterOptions: Sendable {
    /// Number of context lines to include around violations (0 = none)
    public let contextLines: Int
    /// Whether to include full structured fixes
    public let includeFixes: Bool
    /// Minimum severity to include
    public let minSeverity: DiagnosticSeverity?
    
    public init(
        contextLines: Int = 0,
        includeFixes: Bool = true,
        minSeverity: DiagnosticSeverity? = nil
    ) {
        self.contextLines = contextLines
        self.includeFixes = includeFixes
        self.minSeverity = minSeverity
    }
    
    public static let `default` = AgentReporterOptions()
}

/// Compact JSON reporter optimized for AI coding agents
///
/// Outputs machine-readable JSON with:
/// - Compact violation format with unique IDs
/// - Full structured fixes with TextEdit ranges
/// - Optional source context lines
/// - Fixable count in summary
public struct AgentReporter: Reporter {
    private let options: AgentReporterOptions
    
    public init(options: AgentReporterOptions = .default) {
        self.options = options
    }
    
    public func generateReport(_ violations: [Violation]) throws -> String {
        // Filter by severity if specified
        var filtered = violations
        if let minSeverity = options.minSeverity {
            filtered = violations.filter { severityRank($0.severity) >= severityRank(minSeverity) }
        }
        
        // Load file contents for context (if needed)
        var fileContents: [String: [String]] = [:]
        if options.contextLines > 0 {
            for violation in filtered {
                let path = violation.location.file.path
                if fileContents[path] == nil {
                    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                        fileContents[path] = content.components(separatedBy: .newlines)
                    }
                }
            }
        }
        
        let report = AgentReport(
            version: 1,
            format: "agent",
            summary: AgentSummary(
                total: filtered.count,
                fixable: filtered.filter { $0.hasAutoFix }.count,
                errors: filtered.filter { $0.severity == .error }.count,
                warnings: filtered.filter { $0.severity == .warning }.count,
                info: filtered.filter { $0.severity == .info }.count
            ),
            violations: filtered.enumerated().map { index, violation in
                agentViolation(from: violation, id: "v\(index + 1)", fileContents: fileContents)
            }
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    private func severityRank(_ severity: DiagnosticSeverity) -> Int {
        switch severity {
        case .error: return 4
        case .warning: return 3
        case .info: return 2
        case .hint: return 1
        }
    }
    
    private func agentViolation(
        from violation: Violation,
        id: String,
        fileContents: [String: [String]]
    ) -> AgentViolation {
        // Extract context lines if available
        var context: [String]? = nil
        if options.contextLines > 0,
           let lines = fileContents[violation.location.file.path] {
            let lineIndex = violation.location.line - 1
            let start = max(0, lineIndex - options.contextLines)
            let end = min(lines.count - 1, lineIndex + options.contextLines)
            if start <= end && lineIndex < lines.count {
                context = (start...end).map { lines[$0] }
            }
        }
        
        // Convert structured fixes to agent format
        var fixes: [AgentFix]? = nil
        if options.includeFixes && !violation.structuredFixes.isEmpty {
            fixes = violation.structuredFixes.map { fix in
                AgentFix(
                    title: fix.title,
                    kind: fix.kind.rawValue,
                    confidence: fix.confidence.rawValue,
                    isPreferred: fix.isPreferred,
                    edits: fix.edits.map { edit in
                        AgentEdit(
                            file: edit.range.file,
                            startLine: edit.range.startLine,
                            startColumn: edit.range.startColumn,
                            endLine: edit.range.endLine,
                            endColumn: edit.range.endColumn,
                            newText: edit.newText
                        )
                    }
                )
            }
        }
        
        return AgentViolation(
            id: id,
            rule: violation.ruleId,
            category: violation.category.rawValue,
            severity: violation.severity.rawValue,
            message: violation.message,
            file: violation.location.file.path,
            line: violation.location.line,
            column: violation.location.column,
            context: context,
            fixes: fixes
        )
    }
    
    // MARK: - JSON Structures (Compact)
    
    private struct AgentReport: Codable {
        let version: Int
        let format: String
        let summary: AgentSummary
        let violations: [AgentViolation]
    }
    
    private struct AgentSummary: Codable {
        let total: Int
        let fixable: Int
        let errors: Int
        let warnings: Int
        let info: Int
    }
    
    private struct AgentViolation: Codable {
        let id: String
        let rule: String
        let category: String
        let severity: String
        let message: String
        let file: String
        let line: Int
        let column: Int
        let context: [String]?
        let fixes: [AgentFix]?
    }
    
    private struct AgentFix: Codable {
        let title: String
        let kind: String
        let confidence: String
        let isPreferred: Bool
        let edits: [AgentEdit]
    }
    
    private struct AgentEdit: Codable {
        let file: String
        let startLine: Int
        let startColumn: Int
        let endLine: Int
        let endColumn: Int
        let newText: String
    }
}

// MARK: - Agent Fix Reporter

/// Reporter for fix command results in agent mode
public struct AgentFixReporter: Sendable {
    
    public init() {}
    
    /// Generate agent-friendly JSON output for fix results
    public func generateReport(_ results: [FixApplicationResult]) throws -> String {
        let applied = results.filter { $0.hasChanges }.map { result in
            AgentFixResult(
                file: result.file.path,
                fixes: result.appliedFixes.map { fix in
                    AgentAppliedFix(
                        rule: fix.ruleId,
                        title: fix.title,
                        kind: fix.kind.rawValue,
                        confidence: fix.confidence.rawValue
                    )
                },
                diff: result.generateDiff()
            )
        }
        
        let skipped = results.flatMap { result in
            result.skippedFixes.map { (fix, reason) in
                AgentSkippedFix(
                    file: result.file.path,
                    rule: fix.ruleId,
                    title: fix.title,
                    reason: reason
                )
            }
        }
        
        let report = AgentFixReport(
            version: 1,
            format: "agent-fix",
            summary: AgentFixSummary(
                applied: results.reduce(0) { $0 + $1.appliedCount },
                skipped: results.reduce(0) { $0 + $1.skippedCount },
                filesModified: results.filter { $0.hasChanges }.count,
                filesTotal: results.count
            ),
            applied: applied,
            skipped: skipped.isEmpty ? nil : skipped
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    // MARK: - JSON Structures
    
    private struct AgentFixReport: Codable {
        let version: Int
        let format: String
        let summary: AgentFixSummary
        let applied: [AgentFixResult]
        let skipped: [AgentSkippedFix]?
    }
    
    private struct AgentFixSummary: Codable {
        let applied: Int
        let skipped: Int
        let filesModified: Int
        let filesTotal: Int
    }
    
    private struct AgentFixResult: Codable {
        let file: String
        let fixes: [AgentAppliedFix]
        let diff: String
    }
    
    private struct AgentAppliedFix: Codable {
        let rule: String
        let title: String
        let kind: String
        let confidence: String
    }
    
    private struct AgentSkippedFix: Codable {
        let file: String
        let rule: String
        let title: String
        let reason: String
    }
}
