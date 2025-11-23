import Foundation

/// Human-readable console reporter
public struct HumanReporter: Reporter {
    public init() {}

    public func generateReport(_ violations: [Violation]) throws -> String {
        guard !violations.isEmpty else {
            return "✅ No violations found.\n"
        }

        // Group violations by file for cleaner output
        let violationsByFile = Dictionary(grouping: violations) { $0.location.file.path }
            .sorted { $0.key < $1.key }

        var result = ""

        for (file, fileViolations) in violationsByFile {
            result += "\n📁 \(file)\n"
            result += String(repeating: "-", count: file.count + 2) + "\n"

            let sorted = fileViolations.sorted { lhs, rhs in
                if lhs.location.line != rhs.location.line {
                    return lhs.location.line < rhs.location.line
                }
                return lhs.location.column < rhs.location.column
            }

            for violation in sorted {
                let icon = severityIcon(violation.severity)
                result += "\(icon) \(String(describing: violation.severity).uppercased()) [\(String(describing: violation.category).uppercased()).\(violation.ruleId)]\n"
                result += "   Line \(violation.location.line): \(violation.message)\n"

                if !violation.suggestedFixes.isEmpty {
                    result += "   Suggested fixes:\n"
                    for fix in violation.suggestedFixes {
                        result += "     • \(fix)\n"
                    }
                }
            }
        }

        // Summary
        let errors = violations.filter { $0.severity == .error }.count
        let warnings = violations.filter { $0.severity == .warning }.count
        let others = violations.count - errors - warnings

        result += "\n📊 Summary: \(violations.count) violation(s)"
        if errors > 0 {
            result += " (\(errors) error(s))"
        }
        if warnings > 0 {
            result += " (\(warnings) warning(s))"
        }
        if others > 0 {
            result += " (\(others) other)"
        }
        result += "\n"

        return result
    }

    private func severityIcon(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .error: return "❌"
        case .warning: return "⚠️"
        case .info: return "ℹ️"
        case .hint: return "💡"
        }
    }
}