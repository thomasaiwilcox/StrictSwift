import Foundation
import SwiftSyntax

/// Base protocol for all analysis rules
public protocol Rule: Sendable {
    /// Unique identifier for this rule
    var id: String { get }

    /// Human-readable name
    var name: String { get }

    /// Description of what this rule checks
    var description: String { get }

    /// Category of this rule
    var category: RuleCategory { get }

    /// Default severity for violations
    var defaultSeverity: DiagnosticSeverity { get }

    /// Whether this rule is enabled by default
    var enabledByDefault: Bool { get }

    /// Analyze a source file for violations
    func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation]

    /// Check if a file should be analyzed by this rule
    func shouldAnalyze(_ sourceFile: SourceFile) -> Bool
}

/// Extension providing default implementation
public extension Rule {
    var defaultSeverity: DiagnosticSeverity { .warning }
    var enabledByDefault: Bool { true }

    func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        // By default, analyze all .swift files
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Context information for analysis
public final class AnalysisContext: @unchecked Sendable {
    /// Configuration for the analysis
    public let configuration: Configuration
    /// Project root directory
    public let projectRoot: URL
    /// All source files being analyzed
    private var _sourceFiles: [URL: SourceFile] = [:]
    private let lock = NSLock()

    public init(configuration: Configuration, projectRoot: URL) {
        self.configuration = configuration
        self.projectRoot = projectRoot
    }

    /// Get or add a source file
    public func sourceFile(at url: URL) -> SourceFile? {
        lock.lock()
        defer { lock.unlock() }
        return _sourceFiles[url]
    }

    /// Add a source file to the context
    public func addSourceFile(_ sourceFile: SourceFile) {
        lock.lock()
        defer { lock.unlock() }
        _sourceFiles[sourceFile.url] = sourceFile
    }

    /// Get all source files
    public var allSourceFiles: [SourceFile] {
        lock.lock()
        defer { lock.unlock() }
        return Array(_sourceFiles.values)
    }

    /// Check if a path is included in the analysis
    public func isIncluded(_ path: String) -> Bool {
        // Apply include patterns
        if !configuration.include.isEmpty {
            let included = configuration.include.contains { pattern in
                path.matchesGlob(pattern)
            }
            if !included {
                return false
            }
        }

        // Apply exclude patterns
        for pattern in configuration.exclude {
            if path.matchesGlob(pattern) {
                return false
            }
        }

        return true
    }
}

/// Helper for glob matching
private extension String {
    func matchesGlob(_ pattern: String) -> Bool {
        // Simple glob matching - in a real implementation, we'd use a more sophisticated library
        // For now, support * and ** wildcards
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }

        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
}