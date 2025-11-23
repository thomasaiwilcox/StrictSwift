import Foundation

/// Configuration for baseline files that track known violations
public struct BaselineConfiguration: Codable, Equatable, Sendable {
    /// Version of the baseline format
    public let version: Int
    /// When the baseline was created
    public let created: Date
    /// Optional expiry date for temporary exceptions
    public let expires: Date?
    /// Known violations with fingerprints
    public let violations: [ViolationFingerprint]

    public init(
        version: Int = 1,
        created: Date = Date(),
        expires: Date? = nil,
        violations: [ViolationFingerprint] = []
    ) {
        self.version = version
        self.created = created
        self.expires = expires
        self.violations = violations
    }

    /// Load baseline from file
    public static func load(from url: URL) throws -> BaselineConfiguration {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BaselineConfiguration.self, from: data)
    }

    /// Save baseline to file
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    /// Check if baseline has expired
    public var isExpired: Bool {
        guard let expires = expires else { return false }
        return Date() > expires
    }

    /// Add a new violation to the baseline
    public func adding(violation: ViolationFingerprint) -> BaselineConfiguration {
        var violations = self.violations
        // Remove existing violation with same fingerprint if present
        violations.removeAll { $0 == violation }
        violations.append(violation)
        violations.sort()
        return BaselineConfiguration(
            version: version,
            created: created,
            expires: expires,
            violations: violations
        )
    }

    /// Remove violations that are no longer present
    public func removing(violations: [ViolationFingerprint]) -> BaselineConfiguration {
        let remainingViolations = self.violations.filter { !violations.contains($0) }
        return BaselineConfiguration(
            version: version,
            created: created,
            expires: expires,
            violations: remainingViolations
        )
    }
}

/// Unique fingerprint for a violation
public struct ViolationFingerprint: Codable, Hashable, Comparable, Sendable {
    /// Rule that generated the violation
    public let ruleId: String
    /// File path relative to project root
    public let file: String
    /// Line number
    public let line: Int
    /// SHA-256 hash of normalized content
    public let fingerprint: String

    public init(ruleId: String, file: String, line: Int, fingerprint: String) {
        self.ruleId = ruleId
        self.file = file
        self.line = line
        self.fingerprint = fingerprint
    }

    /// Create fingerprint from a violation
    public init(violation: Violation, projectRoot: URL) {
        self.ruleId = violation.ruleId
        self.file = violation.location.file.path
            .replacingOccurrences(of: projectRoot.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.line = violation.location.line
        self.fingerprint = Self.fingerprint(for: violation)
    }

    /// Generate fingerprint for a violation using deterministic hashing
    private static func fingerprint(for violation: Violation) -> String {
        let content = "\(violation.ruleId):\(violation.location.file.path):\(violation.location.line):\(violation.message)"
        let data = Data(content.utf8)

        // Simple deterministic hash function (FNV-1a 64-bit variant)
        // This provides a stable hash across processes and platforms
        let fnvOffsetBasis: UInt64 = 14695981039346656037
        let fnvPrime: UInt64 = 1099511628211

        var hash = fnvOffsetBasis
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }

        return String(hash, radix: 16, uppercase: false)
    }

    public static func < (lhs: ViolationFingerprint, rhs: ViolationFingerprint) -> Bool {
        if lhs.file != rhs.file {
            return lhs.file < rhs.file
        }
        if lhs.line != rhs.line {
            return lhs.line < rhs.line
        }
        return lhs.ruleId < rhs.ruleId
    }
}