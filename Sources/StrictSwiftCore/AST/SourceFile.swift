import Foundation
import SwiftSyntax
import SwiftParser
import SystemPackage

/// Represents a parsed Swift source file
/// SAFETY: @unchecked Sendable is safe because all stored properties (url, tree, symbols, imports)
/// are immutable after initialization. The _lock exists for potential future extensions.
public final class SourceFile: @unchecked Sendable {
    public let url: URL
    public let tree: SourceFileSyntax
    public let symbols: [Symbol]
    public let imports: [Import]
    
    /// Hash of the source content for caching
    public let contentHash: UInt64
    /// File modification date at parse time
    public let modificationDate: Date
    /// File size in bytes
    public let fileSize: Int64

    private let _lock = NSLock()

    public init(url: URL) throws {
        self.url = url
        let source = try String(contentsOf: url, encoding: .utf8)
        self.tree = Parser.parse(source: source)
        
        // Compute fingerprint data
        self.contentHash = FileFingerprint.fnv1aHash(source)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        self.modificationDate = attributes[.modificationDate] as? Date ?? Date()
        self.fileSize = attributes[.size] as? Int64 ?? Int64(source.utf8.count)

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
        
        // Compute fingerprint data from source
        self.contentHash = FileFingerprint.fnv1aHash(source)
        self.modificationDate = Date()
        self.fileSize = Int64(source.utf8.count)

        let symbolCollector = SymbolCollector(fileURL: url, tree: tree)
        symbolCollector.walk(tree)
        self.symbols = symbolCollector.symbols

        let importTracker = ImportTracker(fileURL: url, tree: tree)
        importTracker.walk(tree)
        self.imports = importTracker.imports
    }
    
    /// Get the file fingerprint for caching
    public var fingerprint: FileFingerprint {
        return FileFingerprint(
            path: url.path,
            contentHash: contentHash,
            modificationDate: modificationDate,
            size: fileSize
        )
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

    // MARK: - Location Helpers

    /// Get a Location from an AST position
    public func location(for position: AbsolutePosition) -> Location {
        let converter = SourceLocationConverter(fileName: url.path, tree: tree)
        let loc = converter.location(for: position)
        return Location(
            file: url,
            line: loc.line,
            column: loc.column
        )
    }
    
    /// Get a Location from a syntax node, skipping leading trivia (newlines, whitespace)
    /// This gives the actual position of the code, not including preceding whitespace
    public func location(of node: some SyntaxProtocol) -> Location {
        return location(for: node.positionAfterSkippingLeadingTrivia)
    }
    
    /// Get a Location for the end of a syntax node
    public func location(endOf node: some SyntaxProtocol) -> Location {
        return location(for: node.endPosition)
    }

    /// Find the location of a function by name
    public func locationOfFunction(named functionName: String) -> Location? {
        class FunctionFinder: SyntaxAnyVisitor {
            let targetName: String
            var foundPosition: AbsolutePosition?

            init(targetName: String) {
                self.targetName = targetName
                super.init(viewMode: .sourceAccurate)
            }

            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
                if node.name.text == targetName {
                    foundPosition = node.position
                    return .skipChildren
                }
                return .visitChildren
            }
        }

        let finder = FunctionFinder(targetName: functionName)
        finder.walk(tree)

        if let position = finder.foundPosition {
            return location(for: position)
        }

        return nil
    }
}