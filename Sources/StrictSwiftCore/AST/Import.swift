import Foundation
import SwiftSyntax

/// Represents an import statement
public struct Import: Hashable, Codable, Sendable {
    public let moduleName: String
    public let kind: ImportKind
    public let location: Location

    public init(moduleName: String, kind: ImportKind = .regular, location: Location) {
        self.moduleName = moduleName
        self.kind = kind
        self.location = location
    }
}

/// Types of import statements
public enum ImportKind: String, Hashable, Codable, CaseIterable, Sendable {
    case regular
    case `typealias`
    case `struct`
    case `class`
    case `enum`
    case `protocol`
    case `var`
    case `func`
    case `let`
}