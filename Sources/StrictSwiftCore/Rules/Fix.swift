import Foundation

/// Represents a source range for text edits
public struct SourceRange: Codable, Hashable, Sendable {
    /// Start line (1-indexed)
    public let startLine: Int
    /// Start column (1-indexed)
    public let startColumn: Int
    /// End line (1-indexed)
    public let endLine: Int
    /// End column (1-indexed)
    public let endColumn: Int
    /// File path
    public let file: String
    
    public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int, file: String) {
        self.startLine = startLine
        self.startColumn = startColumn
        self.endLine = endLine
        self.endColumn = endColumn
        self.file = file
    }
    
    /// Create a range from a Location (single point)
    public init(location: Location) {
        self.startLine = location.line
        self.startColumn = location.column
        self.endLine = location.line
        self.endColumn = location.column
        self.file = location.file.path
    }
    
    /// Create a range spanning two locations
    public init(start: Location, end: Location) {
        self.startLine = start.line
        self.startColumn = start.column
        self.endLine = end.line
        self.endColumn = end.column
        self.file = start.file.path
    }
    
    /// Check if this range overlaps with another
    public func overlaps(with other: SourceRange) -> Bool {
        guard file == other.file else { return false }
        
        // Check if one range starts after the other ends
        if startLine > other.endLine || (startLine == other.endLine && startColumn > other.endColumn) {
            return false
        }
        if other.startLine > endLine || (other.startLine == endLine && other.startColumn > endColumn) {
            return false
        }
        return true
    }
    
    /// Check if this range contains another
    public func contains(_ other: SourceRange) -> Bool {
        guard file == other.file else { return false }
        
        let startsAfterOrAt = other.startLine > startLine ||
            (other.startLine == startLine && other.startColumn >= startColumn)
        let endsBeforeOrAt = other.endLine < endLine ||
            (other.endLine == endLine && other.endColumn <= endColumn)
        
        return startsAfterOrAt && endsBeforeOrAt
    }
}

/// A single text edit (replacement)
public struct TextEdit: Codable, Hashable, Sendable {
    /// The range to replace
    public let range: SourceRange
    /// The new text to insert (empty string for deletion)
    public let newText: String
    
    public init(range: SourceRange, newText: String) {
        self.range = range
        self.newText = newText
    }
    
    /// Create an insertion at a location
    public static func insert(at location: Location, text: String) -> TextEdit {
        return TextEdit(range: SourceRange(location: location), newText: text)
    }
    
    /// Create a deletion of a range
    public static func delete(range: SourceRange) -> TextEdit {
        return TextEdit(range: range, newText: "")
    }
}

/// The type/category of fix
public enum FixKind: String, Codable, Sendable, CaseIterable {
    /// Direct text replacement
    case replace = "replace"
    /// Insert guard statement
    case insertGuard = "insert_guard"
    /// Insert if-let binding
    case insertIfLet = "insert_if_let"
    /// Add annotation (e.g., @Sendable)
    case addAnnotation = "add_annotation"
    /// Remove code
    case removeCode = "remove_code"
    /// Wrap in conditional compilation
    case wrapConditional = "wrap_conditional"
    /// Add do-catch block
    case addDoCatch = "add_do_catch"
    /// Replace with try?
    case replaceWithTryOptional = "replace_try_optional"
    /// General refactoring
    case refactor = "refactor"
}

/// Confidence level for automated fixes
public enum FixConfidence: String, Codable, Sendable, CaseIterable, Comparable {
    /// Always safe to apply - semantically equivalent
    case safe = "safe"
    /// Usually correct but may change behavior slightly
    case suggested = "suggested"
    /// May require manual review
    case experimental = "experimental"
    
    public static func < (lhs: FixConfidence, rhs: FixConfidence) -> Bool {
        let order: [FixConfidence] = [.experimental, .suggested, .safe]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// A structured fix that can be automatically applied
public struct StructuredFix: Codable, Hashable, Sendable {
    /// Human-readable title for the fix
    public let title: String
    /// The kind of fix
    public let kind: FixKind
    /// Text edits to apply
    public let edits: [TextEdit]
    /// Whether this is the preferred/recommended fix
    public let isPreferred: Bool
    /// Confidence level for this fix
    public let confidence: FixConfidence
    /// Optional description of what the fix does
    public let description: String?
    /// The rule ID this fix is for
    public let ruleId: String
    
    public init(
        title: String,
        kind: FixKind,
        edits: [TextEdit],
        isPreferred: Bool = false,
        confidence: FixConfidence = .suggested,
        description: String? = nil,
        ruleId: String
    ) {
        self.title = title
        self.kind = kind
        self.edits = edits
        self.isPreferred = isPreferred
        self.confidence = confidence
        self.description = description
        self.ruleId = ruleId
    }
    
    /// Check if this fix conflicts with another (overlapping edits)
    public func conflicts(with other: StructuredFix) -> Bool {
        for edit in edits {
            for otherEdit in other.edits {
                if edit.range.overlaps(with: otherEdit.range) {
                    return true
                }
            }
        }
        return false
    }
}

/// Builder for creating structured fixes
public struct StructuredFixBuilder {
    private var title: String
    private var kind: FixKind
    private var edits: [TextEdit] = []
    private var isPreferred: Bool = false
    private var confidence: FixConfidence = .suggested
    private var description: String?
    private let ruleId: String
    
    public init(title: String, kind: FixKind, ruleId: String) {
        self.title = title
        self.kind = kind
        self.ruleId = ruleId
    }
    
    /// Add a text edit
    public mutating func addEdit(_ edit: TextEdit) {
        edits.append(edit)
    }
    
    /// Add a replacement edit
    public mutating func addReplacement(range: SourceRange, newText: String) {
        edits.append(TextEdit(range: range, newText: newText))
    }
    
    /// Mark this fix as preferred
    public mutating func markPreferred() {
        isPreferred = true
    }
    
    /// Set the confidence level
    public mutating func setConfidence(_ level: FixConfidence) {
        confidence = level
    }
    
    /// Set the description
    public mutating func setDescription(_ desc: String) {
        description = desc
    }
    
    /// Build the structured fix
    public func build() -> StructuredFix {
        return StructuredFix(
            title: title,
            kind: kind,
            edits: edits,
            isPreferred: isPreferred,
            confidence: confidence,
            description: description,
            ruleId: ruleId
        )
    }
}

// MARK: - Fix Application Result

/// Result of applying fixes to a file
public struct FixApplicationResult: Sendable {
    /// The file that was modified
    public let file: URL
    /// Number of fixes applied
    public let appliedCount: Int
    /// Number of fixes skipped (conflicts, errors)
    public let skippedCount: Int
    /// The original content
    public let originalContent: String
    /// The modified content
    public let modifiedContent: String
    /// Fixes that were applied
    public let appliedFixes: [StructuredFix]
    /// Fixes that were skipped with reasons
    public let skippedFixes: [(fix: StructuredFix, reason: String)]
    
    public init(
        file: URL,
        appliedCount: Int,
        skippedCount: Int,
        originalContent: String,
        modifiedContent: String,
        appliedFixes: [StructuredFix],
        skippedFixes: [(fix: StructuredFix, reason: String)]
    ) {
        self.file = file
        self.appliedCount = appliedCount
        self.skippedCount = skippedCount
        self.originalContent = originalContent
        self.modifiedContent = modifiedContent
        self.appliedFixes = appliedFixes
        self.skippedFixes = skippedFixes
    }
    
    /// Whether any changes were made
    public var hasChanges: Bool {
        return appliedCount > 0
    }
    
    /// Generate a unified diff of the changes
    public func generateDiff() -> String {
        // Simple line-by-line diff
        let originalLines = originalContent.split(separator: "\n", omittingEmptySubsequences: false)
        let modifiedLines = modifiedContent.split(separator: "\n", omittingEmptySubsequences: false)
        
        var diff = "--- \(file.lastPathComponent)\n+++ \(file.lastPathComponent)\n"
        
        var i = 0, j = 0
        while i < originalLines.count || j < modifiedLines.count {
            if i < originalLines.count && j < modifiedLines.count && originalLines[i] == modifiedLines[j] {
                i += 1
                j += 1
            } else if i < originalLines.count && (j >= modifiedLines.count || originalLines[i] != modifiedLines[j]) {
                diff += "-\(originalLines[i])\n"
                i += 1
            } else if j < modifiedLines.count {
                diff += "+\(modifiedLines[j])\n"
                j += 1
            }
        }
        
        return diff
    }
}

/// Summary of fix operations across multiple files
public struct FixSummary: Sendable {
    /// Total files processed
    public let totalFiles: Int
    /// Files that were modified
    public let modifiedFiles: Int
    /// Total fixes applied
    public let totalApplied: Int
    /// Total fixes skipped
    public let totalSkipped: Int
    /// Per-file results
    public let results: [FixApplicationResult]
    
    public init(results: [FixApplicationResult]) {
        self.results = results
        self.totalFiles = results.count
        self.modifiedFiles = results.filter { $0.hasChanges }.count
        self.totalApplied = results.reduce(0) { $0 + $1.appliedCount }
        self.totalSkipped = results.reduce(0) { $0 + $1.skippedCount }
    }
}
