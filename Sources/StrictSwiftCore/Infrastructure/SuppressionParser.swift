import Foundation

/// Represents a suppression directive parsed from source comments
public struct Suppression: Sendable {
    public enum Kind: Sendable {
        /// Suppress the next line
        case nextLine
        /// Suppress the same line (inline comment)
        case sameLine
        /// Begin a suppression region
        case regionStart
        /// End a suppression region
        case regionEnd
        /// Suppress the entire file
        case file
    }
    
    public let kind: Kind
    public let ruleIds: Set<String>  // Empty or ["all"] means all rules
    public let line: Int
    public let reason: String?  // Optional reason after the rule IDs
    
    /// Check if this suppression applies to a given rule
    public func suppresses(ruleId: String) -> Bool {
        if ruleIds.isEmpty || ruleIds.contains("all") {
            return true
        }
        return ruleIds.contains(ruleId)
    }
}

/// Parses suppression comments from source code
///
/// Supported syntax:
/// - `// strictswift:ignore <rule-id>` - Ignore next line
/// - `// strictswift:ignore <rule-id> -- reason` - With optional reason
/// - `// strictswift:ignore rule1, rule2` - Multiple rules
/// - `// strictswift:ignore all` - All rules
/// - `// strictswift:ignore-start <rule-id>` - Begin region
/// - `// strictswift:ignore-end` - End region
/// - `// strictswift:ignore-file <rule-id>` - Entire file
///
/// Also supports inline: `let x = foo // strictswift:ignore force_unwrap`
public struct SuppressionParser: Sendable {
    
    /// Parse all suppressions from source code
    public static func parse(source: String) -> [Suppression] {
        var suppressions: [Suppression] = []
        let lines = source.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1  // 1-indexed
            
            // Check for suppression comments
            if let suppression = parseLine(line, lineNumber: lineNumber) {
                suppressions.append(suppression)
            }
        }
        
        return suppressions
    }
    
    /// Parse a single line for suppression directives
    private static func parseLine(_ line: String, lineNumber: Int) -> Suppression? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // Find the comment portion
        guard let commentStart = line.range(of: "//") else {
            return nil
        }
        
        let comment = String(line[commentStart.upperBound...]).trimmingCharacters(in: .whitespaces)
        
        // Check for strictswift directive
        guard comment.hasPrefix("strictswift:") else {
            return nil
        }
        
        let directive = String(comment.dropFirst("strictswift:".count))
        
        // Determine if this is an inline comment (code before //)
        let beforeComment = String(line[..<commentStart.lowerBound]).trimmingCharacters(in: .whitespaces)
        let isInline = !beforeComment.isEmpty
        
        // Parse the directive type
        if directive.hasPrefix("ignore-start") {
            let rest = String(directive.dropFirst("ignore-start".count)).trimmingCharacters(in: .whitespaces)
            let (ruleIds, reason) = parseRuleIdsAndReason(rest)
            return Suppression(kind: .regionStart, ruleIds: ruleIds, line: lineNumber, reason: reason)
        }
        
        if directive.hasPrefix("ignore-end") {
            return Suppression(kind: .regionEnd, ruleIds: [], line: lineNumber, reason: nil)
        }
        
        if directive.hasPrefix("ignore-file") {
            let rest = String(directive.dropFirst("ignore-file".count)).trimmingCharacters(in: .whitespaces)
            let (ruleIds, reason) = parseRuleIdsAndReason(rest)
            return Suppression(kind: .file, ruleIds: ruleIds, line: lineNumber, reason: reason)
        }
        
        if directive.hasPrefix("ignore") {
            let rest = String(directive.dropFirst("ignore".count)).trimmingCharacters(in: .whitespaces)
            let (ruleIds, reason) = parseRuleIdsAndReason(rest)
            let kind: Suppression.Kind = isInline ? .sameLine : .nextLine
            return Suppression(kind: kind, ruleIds: ruleIds, line: lineNumber, reason: reason)
        }
        
        return nil
    }
    
    /// Parse rule IDs and optional reason from directive content
    /// Format: "rule1, rule2 -- optional reason"
    private static func parseRuleIdsAndReason(_ content: String) -> (Set<String>, String?) {
        let parts = content.components(separatedBy: "--")
        let rulesPart = parts[0].trimmingCharacters(in: .whitespaces)
        let reason = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
        
        if rulesPart.isEmpty {
            return (["all"], reason)
        }
        
        let ruleIds = rulesPart
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        return (Set(ruleIds), reason)
    }
}

/// Tracks active suppressions and determines if a violation should be suppressed
public final class SuppressionTracker: Sendable {
    private let suppressions: [Suppression]
    private let fileLevelSuppressions: Set<String>  // Rule IDs suppressed for entire file
    private let regionSuppressions: [(startLine: Int, endLine: Int, ruleIds: Set<String>)]
    private let lineSuppressions: [Int: Set<String>]  // Line -> suppressed rule IDs
    
    public init(source: String) {
        let parsed = SuppressionParser.parse(source: source)
        self.suppressions = parsed
        
        // Extract file-level suppressions
        var fileLevel = Set<String>()
        for suppression in parsed where suppression.kind == .file {
            if suppression.ruleIds.isEmpty || suppression.ruleIds.contains("all") {
                fileLevel.insert("all")
            } else {
                fileLevel.formUnion(suppression.ruleIds)
            }
        }
        self.fileLevelSuppressions = fileLevel
        
        // Build region suppressions
        var regions: [(startLine: Int, endLine: Int, ruleIds: Set<String>)] = []
        var activeRegions: [(startLine: Int, ruleIds: Set<String>)] = []
        
        for suppression in parsed {
            switch suppression.kind {
            case .regionStart:
                activeRegions.append((suppression.line, suppression.ruleIds))
            case .regionEnd:
                if let lastRegion = activeRegions.popLast() {
                    regions.append((lastRegion.startLine, suppression.line, lastRegion.ruleIds))
                }
            default:
                break
            }
        }
        
        // Close any unclosed regions at end of file
        let maxLine = Int.max
        for region in activeRegions {
            regions.append((region.startLine, maxLine, region.ruleIds))
        }
        
        self.regionSuppressions = regions
        
        // Build line-level suppressions
        var lines: [Int: Set<String>] = [:]
        for suppression in parsed {
            switch suppression.kind {
            case .nextLine:
                let targetLine = suppression.line + 1
                var existing = lines[targetLine] ?? []
                if suppression.ruleIds.isEmpty || suppression.ruleIds.contains("all") {
                    existing.insert("all")
                } else {
                    existing.formUnion(suppression.ruleIds)
                }
                lines[targetLine] = existing
            case .sameLine:
                var existing = lines[suppression.line] ?? []
                if suppression.ruleIds.isEmpty || suppression.ruleIds.contains("all") {
                    existing.insert("all")
                } else {
                    existing.formUnion(suppression.ruleIds)
                }
                lines[suppression.line] = existing
            default:
                break
            }
        }
        self.lineSuppressions = lines
    }
    
    /// Check if a violation at the given line should be suppressed
    public func isSuppressed(ruleId: String, line: Int) -> Bool {
        // Check file-level suppressions
        if fileLevelSuppressions.contains("all") || fileLevelSuppressions.contains(ruleId) {
            return true
        }
        
        // Check line-level suppressions
        if let lineSuppression = lineSuppressions[line] {
            if lineSuppression.contains("all") || lineSuppression.contains(ruleId) {
                return true
            }
        }
        
        // Check region suppressions
        for region in regionSuppressions {
            if line >= region.startLine && line <= region.endLine {
                if region.ruleIds.isEmpty || region.ruleIds.contains("all") || region.ruleIds.contains(ruleId) {
                    return true
                }
            }
        }
        
        return false
    }
}
