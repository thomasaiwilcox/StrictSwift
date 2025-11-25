import Foundation
import SwiftSyntax
import SwiftParser

/// Applies structured fixes to source files
public actor FixApplier {
    
    /// Options for fix application
    public struct Options: Sendable {
        /// Only apply fixes with this confidence level or higher
        public let minimumConfidence: FixConfidence
        /// Whether to validate syntax after applying fixes
        public let validateSyntax: Bool
        /// Whether to format the code after applying fixes
        public let formatAfterFix: Bool
        /// Maximum number of fixes to apply per file
        public let maxFixesPerFile: Int?
        
        public init(
            minimumConfidence: FixConfidence = .suggested,
            validateSyntax: Bool = true,
            formatAfterFix: Bool = false,
            maxFixesPerFile: Int? = nil
        ) {
            self.minimumConfidence = minimumConfidence
            self.validateSyntax = validateSyntax
            self.formatAfterFix = formatAfterFix
            self.maxFixesPerFile = maxFixesPerFile
        }
        
        /// Default options for safe fixes only
        public static let safeOnly = Options(minimumConfidence: .safe)
        
        /// Default options for all suggested fixes
        public static let suggested = Options(minimumConfidence: .suggested)
        
        /// Default options for all fixes including experimental
        public static let all = Options(minimumConfidence: .experimental)
    }
    
    private let options: Options
    
    public init(options: Options = .suggested) {
        self.options = options
    }
    
    // MARK: - Public API
    
    /// Apply fixes to a single file
    public func applyFixes(
        _ fixes: [StructuredFix],
        to fileURL: URL
    ) async throws -> FixApplicationResult {
        // Read original content
        let originalContent = try String(contentsOf: fileURL, encoding: .utf8)
        
        // Filter fixes by confidence
        let eligibleFixes = fixes.filter { $0.confidence >= options.minimumConfidence }
        
        // Limit number of fixes if configured
        let fixesToApply: [StructuredFix]
        if let max = options.maxFixesPerFile {
            fixesToApply = Array(eligibleFixes.prefix(max))
        } else {
            fixesToApply = eligibleFixes
        }
        
        // Sort fixes by position (reverse order so we apply from end to start)
        let sortedFixes = sortFixesByPosition(fixesToApply)
        
        // Apply fixes
        var modifiedContent = originalContent
        var appliedFixes: [StructuredFix] = []
        var skippedFixes: [(fix: StructuredFix, reason: String)] = []
        
        for fix in sortedFixes {
            do {
                let result = try applyFix(fix, to: modifiedContent)
                modifiedContent = result
                appliedFixes.append(fix)
            } catch let error as FixError {
                skippedFixes.append((fix, error.localizedDescription))
            } catch {
                skippedFixes.append((fix, "Unexpected error: \(error.localizedDescription)"))
            }
        }
        
        // Validate syntax if configured
        if options.validateSyntax && !appliedFixes.isEmpty {
            // Parse the modified content to check for syntax errors
            // In SwiftSyntax 600+, we check for parsing issues by looking at the tree structure
            let tree = Parser.parse(source: modifiedContent)
            
            // Check if parsing produced any unexpected tokens (indicates syntax errors)
            let hasErrors = containsSyntaxErrors(tree)
            if hasErrors {
                // Rollback - syntax errors introduced
                return FixApplicationResult(
                    file: fileURL,
                    appliedCount: 0,
                    skippedCount: fixes.count,
                    originalContent: originalContent,
                    modifiedContent: originalContent,
                    appliedFixes: [],
                    skippedFixes: fixes.map { ($0, "Fix would introduce syntax errors") }
                )
            }
        }
        
        return FixApplicationResult(
            file: fileURL,
            appliedCount: appliedFixes.count,
            skippedCount: skippedFixes.count,
            originalContent: originalContent,
            modifiedContent: modifiedContent,
            appliedFixes: appliedFixes,
            skippedFixes: skippedFixes
        )
    }
    
    /// Apply fixes from violations to a file
    /// Only applies one fix per violation (preferring the preferred fix if it meets confidence threshold)
    public func applyFixes(
        from violations: [Violation],
        to fileURL: URL
    ) async throws -> FixApplicationResult {
        // Take only fixes that meet confidence threshold, preferring the preferred fix
        let fixes = violations.compactMap { violation -> StructuredFix? in
            // First try preferred fix if it meets confidence threshold
            if let preferred = violation.preferredFix,
               preferred.confidence >= options.minimumConfidence {
                return preferred
            }
            // Otherwise find first fix that meets confidence threshold
            return violation.structuredFixes.first {
                $0.confidence >= options.minimumConfidence
            }
        }
        return try await applyFixes(fixes, to: fileURL)
    }
    
    /// Apply fixes to multiple files
    public func applyFixes(
        _ fixesByFile: [URL: [StructuredFix]]
    ) async throws -> FixSummary {
        var results: [FixApplicationResult] = []
        
        for (fileURL, fixes) in fixesByFile {
            let result = try await applyFixes(fixes, to: fileURL)
            results.append(result)
        }
        
        return FixSummary(results: results)
    }
    
    /// Write fix results to disk
    public func writeResults(_ results: [FixApplicationResult]) async throws {
        for result in results where result.hasChanges {
            try result.modifiedContent.write(to: result.file, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Check if a syntax tree contains errors (unexpected tokens, missing tokens, etc.)
    private func containsSyntaxErrors(_ tree: SourceFileSyntax) -> Bool {
        // Walk the tree looking for unexpected or missing tokens
        let checker = SyntaxErrorChecker(viewMode: .sourceAccurate)
        checker.walk(tree)
        return checker.hasErrors
    }
    
    /// Sort fixes by position (end to start) to avoid offset issues
    private func sortFixesByPosition(_ fixes: [StructuredFix]) -> [StructuredFix] {
        return fixes.sorted { fix1, fix2 in
            guard let edit1 = fix1.edits.first, let edit2 = fix2.edits.first else {
                return false
            }
            // Sort by end position descending (apply from end to start)
            if edit1.range.endLine != edit2.range.endLine {
                return edit1.range.endLine > edit2.range.endLine
            }
            return edit1.range.endColumn > edit2.range.endColumn
        }
    }
    
    /// Apply a single fix to content
    private func applyFix(_ fix: StructuredFix, to content: String) throws -> String {
        var result = content
        
        // Sort edits by position (reverse order)
        let sortedEdits = fix.edits.sorted { edit1, edit2 in
            if edit1.range.endLine != edit2.range.endLine {
                return edit1.range.endLine > edit2.range.endLine
            }
            return edit1.range.endColumn > edit2.range.endColumn
        }
        
        for edit in sortedEdits {
            result = try applyEdit(edit, to: result)
        }
        
        return result
    }
    
    /// Apply a single fix to a string content (useful for testing)
    public func apply(fix: StructuredFix, to content: String) throws -> String {
        return try applyFix(fix, to: content)
    }
    
    /// Apply a single text edit to content
    private func applyEdit(_ edit: TextEdit, to content: String) throws -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        // Validate line numbers
        guard edit.range.startLine >= 1, edit.range.startLine <= lines.count else {
            throw FixError.invalidRange("Start line \(edit.range.startLine) out of range (1-\(lines.count))")
        }
        guard edit.range.endLine >= 1, edit.range.endLine <= lines.count else {
            throw FixError.invalidRange("End line \(edit.range.endLine) out of range (1-\(lines.count))")
        }
        
        // Convert to 0-indexed
        let startLineIdx = edit.range.startLine - 1
        let endLineIdx = edit.range.endLine - 1
        
        // Get the content before the edit
        var resultLines: [String] = []
        
        // Add lines before the edit
        for i in 0..<startLineIdx {
            resultLines.append(lines[i])
        }
        
        // Handle the edit
        let startLine = lines[startLineIdx]
        let endLine = lines[endLineIdx]
        
        // Validate column numbers
        let startColIdx = max(0, min(edit.range.startColumn - 1, startLine.count))
        let endColIdx = max(0, min(edit.range.endColumn - 1, endLine.count))
        
        // Build the modified line(s)
        let startIdx = startLine.index(startLine.startIndex, offsetBy: startColIdx, limitedBy: startLine.endIndex) ?? startLine.endIndex
        let endIdx = endLine.index(endLine.startIndex, offsetBy: endColIdx, limitedBy: endLine.endIndex) ?? endLine.endIndex
        
        let prefix = String(startLine[..<startIdx])
        let suffix = String(endLine[endIdx...])
        
        let newContent = prefix + edit.newText + suffix
        
        // Handle multi-line replacements
        let newContentLines = newContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        resultLines.append(contentsOf: newContentLines)
        
        // Add lines after the edit
        for i in (endLineIdx + 1)..<lines.count {
            resultLines.append(lines[i])
        }
        
        return resultLines.joined(separator: "\n")
    }
}

/// Errors that can occur during fix application
public enum FixError: Error, LocalizedError {
    case invalidRange(String)
    case conflictingEdits(String)
    case syntaxError(String)
    case fileNotFound(String)
    case writeError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidRange(let msg): return "Invalid range: \(msg)"
        case .conflictingEdits(let msg): return "Conflicting edits: \(msg)"
        case .syntaxError(let msg): return "Syntax error: \(msg)"
        case .fileNotFound(let msg): return "File not found: \(msg)"
        case .writeError(let msg): return "Write error: \(msg)"
        }
    }
}

// MARK: - Fix Generators

/// Protocol for rules that can generate structured fixes
public protocol FixGenerator {
    /// Generate structured fixes for a violation
    func generateFixes(
        for node: some SyntaxProtocol,
        in sourceFile: SourceFile,
        violation: Violation
    ) -> [StructuredFix]
}

/// Utility for generating common fix patterns
public struct FixPatterns {
    
    /// Generate an if-let fix for force unwrap
    public static func ifLetFix(
        for expression: String,
        bindingName: String,
        at range: SourceRange,
        ruleId: String
    ) -> StructuredFix {
        let newText = "if let \(bindingName) = \(expression) {\n    // Use \(bindingName) here\n}"
        
        return StructuredFix(
            title: "Use if-let binding",
            kind: .insertIfLet,
            edits: [TextEdit(range: range, newText: newText)],
            isPreferred: true,
            confidence: .suggested,
            description: "Replace force unwrap with optional binding",
            ruleId: ruleId
        )
    }
    
    /// Generate a guard-let fix for force unwrap
    public static func guardLetFix(
        for expression: String,
        bindingName: String,
        at range: SourceRange,
        ruleId: String
    ) -> StructuredFix {
        let newText = "guard let \(bindingName) = \(expression) else {\n    return // or handle error\n}\n// Use \(bindingName) here"
        
        return StructuredFix(
            title: "Use guard-let binding",
            kind: .insertGuard,
            edits: [TextEdit(range: range, newText: newText)],
            isPreferred: false,
            confidence: .suggested,
            description: "Replace force unwrap with guard statement",
            ruleId: ruleId
        )
    }
    
    /// Generate a try? fix for force try
    public static func tryOptionalFix(
        for expression: String,
        at range: SourceRange,
        ruleId: String
    ) -> StructuredFix {
        return StructuredFix(
            title: "Use try? instead",
            kind: .replaceWithTryOptional,
            edits: [TextEdit(range: range, newText: "try? \(expression)")],
            isPreferred: false,
            confidence: .suggested,
            description: "Replace force try with optional try",
            ruleId: ruleId
        )
    }
    
    /// Generate a do-catch fix for force try
    public static func doCatchFix(
        for expression: String,
        at range: SourceRange,
        ruleId: String
    ) -> StructuredFix {
        let newText = """
            do {
                try \(expression)
            } catch {
                // Handle error
            }
            """
        
        return StructuredFix(
            title: "Wrap in do-catch",
            kind: .addDoCatch,
            edits: [TextEdit(range: range, newText: newText)],
            isPreferred: true,
            confidence: .suggested,
            description: "Wrap expression in do-catch block",
            ruleId: ruleId
        )
    }
    
    /// Generate a #if DEBUG wrapper fix
    public static func debugConditionalFix(
        for code: String,
        at range: SourceRange,
        ruleId: String
    ) -> StructuredFix {
        let newText = "#if DEBUG\n\(code)\n#endif"
        
        return StructuredFix(
            title: "Wrap in #if DEBUG",
            kind: .wrapConditional,
            edits: [TextEdit(range: range, newText: newText)],
            isPreferred: true,
            confidence: .safe,
            description: "Wrap in conditional compilation for debug builds only",
            ruleId: ruleId
        )
    }
    
    /// Generate a removal fix
    public static func removeFix(
        at range: SourceRange,
        description: String,
        ruleId: String
    ) -> StructuredFix {
        return StructuredFix(
            title: "Remove code",
            kind: .removeCode,
            edits: [TextEdit.delete(range: range)],
            isPreferred: false,
            confidence: .experimental,
            description: description,
            ruleId: ruleId
        )
    }
}

// MARK: - Syntax Error Checker

/// Walks a syntax tree to detect parsing errors
private class SyntaxErrorChecker: SyntaxVisitor {
    var hasErrors = false
    
    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        // Check for missing tokens (presence == .missing)
        if token.presence == .missing {
            hasErrors = true
            return .skipChildren
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: UnexpectedNodesSyntax) -> SyntaxVisitorContinueKind {
        hasErrors = true
        return .skipChildren
    }
}
