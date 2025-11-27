import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// A rule violation found during analysis
public struct Violation: Codable, Hashable, Sendable {
    /// Unique identifier for the rule that generated this violation
    public let ruleId: String
    /// Category of the rule
    public let category: RuleCategory
    /// Severity of the violation
    public let severity: DiagnosticSeverity
    /// Human-readable message
    public let message: String
    /// Primary location of the violation
    public let location: Location
    /// Additional related locations (e.g., in circular dependencies)
    public let relatedLocations: [Location]
    /// Suggested fixes (human-readable descriptions)
    public let suggestedFixes: [String]
    /// Structured fixes that can be automatically applied
    public let structuredFixes: [StructuredFix]
    /// Context information for the violation
    public let context: [String: String]

    public init(
        ruleId: String,
        category: RuleCategory,
        severity: DiagnosticSeverity,
        message: String,
        location: Location,
        relatedLocations: [Location] = [],
        suggestedFixes: [String] = [],
        structuredFixes: [StructuredFix] = [],
        context: [String: String] = [:]
    ) {
        self.ruleId = ruleId
        self.category = category
        self.severity = severity
        self.message = message
        self.location = location
        self.relatedLocations = relatedLocations
        self.suggestedFixes = suggestedFixes
        self.structuredFixes = structuredFixes
        self.context = context
    }
    
    /// Whether this violation has any auto-fixable structured fixes
    public var hasAutoFix: Bool {
        return !structuredFixes.isEmpty
    }
    
    /// Get the preferred structured fix, if any
    public var preferredFix: StructuredFix? {
        return structuredFixes.first(where: { $0.isPreferred }) ?? structuredFixes.first
    }
    
    /// Get only safe fixes (confidence == .safe)
    public var safeFixes: [StructuredFix] {
        return structuredFixes.filter { $0.confidence == .safe }
    }
    
    /// Stable identifier for this violation that persists across runs.
    /// Used for tracking feedback and correlating violations over time.
    /// Format: 16-character hex string derived from hash of key properties.
    public var stableId: String {
        // Hash: ruleId + normalized file path + line + message
        // We use the file name (not full path) to be portable across machines
        let fileName = location.file.lastPathComponent
        let input = "\(ruleId)|\(fileName)|\(location.line)|\(message)"
        #if canImport(CryptoKit)
        let hash = SHA256.hash(data: Data(input.utf8))
        // Take first 8 bytes (16 hex chars) for a human-friendly ID
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        #else
        // Fallback: Use a simple DJB2-style hash for Linux
        // This is deterministic and produces consistent results
        var hashValue: UInt64 = 5381
        for byte in input.utf8 {
            hashValue = ((hashValue << 5) &+ hashValue) &+ UInt64(byte)
        }
        return String(format: "%016llx", hashValue)
        #endif
    }
}

/// Violation builder for easier construction
public struct ViolationBuilder {
    public let ruleId: String
    public let category: RuleCategory
    public let location: Location

    private var severity: DiagnosticSeverity = .warning
    private var message: String = ""
    private var relatedLocations: [Location] = []
    private var suggestedFixes: [String] = []
    private var structuredFixes: [StructuredFix] = []
    private var context: [String: String] = [:]

    public init(ruleId: String, category: RuleCategory, location: Location) {
        self.ruleId = ruleId
        self.category = category
        self.location = location
    }

    public func severity(_ severity: DiagnosticSeverity) -> ViolationBuilder {
        var builder = self
        builder.severity = severity
        return builder
    }

    public func message(_ message: String) -> ViolationBuilder {
        var builder = self
        builder.message = message
        return builder
    }

    public func addRelatedLocation(_ location: Location) -> ViolationBuilder {
        var builder = self
        builder.relatedLocations.append(location)
        return builder
    }

    public func suggestFix(_ fix: String) -> ViolationBuilder {
        var builder = self
        builder.suggestedFixes.append(fix)
        return builder
    }
    
    /// Add a structured fix that can be automatically applied
    public func addStructuredFix(_ fix: StructuredFix) -> ViolationBuilder {
        var builder = self
        builder.structuredFixes.append(fix)
        return builder
    }
    
    /// Add a structured fix using a builder closure
    public func addStructuredFix(
        title: String,
        kind: FixKind,
        configure: (inout StructuredFixBuilder) -> Void
    ) -> ViolationBuilder {
        var fixBuilder = StructuredFixBuilder(title: title, kind: kind, ruleId: ruleId)
        configure(&fixBuilder)
        return addStructuredFix(fixBuilder.build())
    }

    public func addContext(key: String, value: String) -> ViolationBuilder {
        var builder = self
        builder.context[key] = value
        return builder
    }

    public func build() -> Violation {
        Violation(
            ruleId: ruleId,
            category: category,
            severity: severity,
            message: message,
            location: location,
            relatedLocations: relatedLocations,
            suggestedFixes: suggestedFixes,
            structuredFixes: structuredFixes,
            context: context
        )
    }
}