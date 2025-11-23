import Foundation
import SwiftSyntax
import SwiftParser
import SystemPackage

/// Represents a parsed Swift source file
public final class SourceFile: @unchecked Sendable {
    public let url: URL
    public let tree: SourceFileSyntax
    public let symbols: [Symbol]
    public let imports: [Import]

    private let _lock = NSLock()

    public init(url: URL) throws {
        self.url = url
        let source = try String(contentsOf: url, encoding: .utf8)
        self.tree = Parser.parse(source: source)

        let symbolCollector = SymbolCollector(fileURL: url, tree: tree)
        symbolCollector.walk(tree)
        self.symbols = symbolCollector.symbols

        let importTracker = ImportTracker(fileURL: url, tree: tree)
        importTracker.walk(tree)
        self.imports = importTracker.imports
    }

    /// Convenience initializer for testing
    public init(url: URL, source: String) {
        self.url = url
        self.tree = Parser.parse(source: source)

        let symbolCollector = SymbolCollector(fileURL: url, tree: tree)
        symbolCollector.walk(tree)
        self.symbols = symbolCollector.symbols

        let importTracker = ImportTracker(fileURL: url, tree: tree)
        importTracker.walk(tree)
        self.imports = importTracker.imports
    }

    /// Get the absolute path as string
    public var path: String {
        url.path
    }

    /// Get the relative path from a base directory
    public func relativePath(from base: URL) -> String {
        // For now, return the path - relative path calculation is complex
        return url.path
    }

    /// Get the source code as string
    public func source() -> String {
        tree.description
    }
}