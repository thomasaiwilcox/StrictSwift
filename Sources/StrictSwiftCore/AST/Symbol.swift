import Foundation
import SwiftSyntax

/// Represents a symbol found in Swift source code
public struct Symbol: Hashable, Codable, Sendable {
    public let name: String
    public let kind: SymbolKind
    public let location: Location
    public let accessibility: Accessibility
    public let attributes: [Attribute]

    public init(
        name: String,
        kind: SymbolKind,
        location: Location,
        accessibility: Accessibility,
        attributes: [Attribute] = []
    ) {
        self.name = name
        self.kind = kind
        self.location = location
        self.accessibility = accessibility
        self.attributes = attributes
    }
}

/// Types of symbols in Swift
public enum SymbolKind: String, Hashable, Codable, CaseIterable, Sendable {
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case function
    case variable
    case `extension`
    case typeAlias
    case associatedType
    case `case`
    case initializer
    case deinitializer
    case `subscript`
}

/// Accessibility levels
public enum Accessibility: String, Hashable, Codable, CaseIterable, Sendable {
    case `private`
    case `fileprivate`
    case `internal`
    case `package`
    case `public`
    case `open`
}

/// Attributes on declarations
public struct Attribute: Hashable, Codable, Sendable {
    public let name: String
    public let arguments: [String]

    public init(name: String, arguments: [String] = []) {
        self.name = name
        self.arguments = arguments
    }
}