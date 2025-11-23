import Foundation

/// Represents a location in source code
public struct Location: Hashable, Codable, Sendable {
    public let file: URL
    public let line: Int
    public let column: Int

    public init(file: URL, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

/// Represents a range in source code
public struct Range: Hashable, Codable, Sendable {
    public let start: Location
    public let end: Location

    public init(start: Location, end: Location) {
        self.start = start
        self.end = end
    }
}