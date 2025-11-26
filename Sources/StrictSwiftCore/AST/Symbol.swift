import Foundation
import SwiftSyntax

// MARK: - Symbol ID

/// A unique identifier for a symbol, stable across analysis runs for the same source.
/// Format: "moduleName::qualifiedName::kind::locationHash"
public struct SymbolID: Hashable, Codable, Sendable, CustomStringConvertible {
    /// The module name where the symbol is defined
    public let moduleName: String
    
    /// The fully qualified name (e.g., "MyClass.NestedStruct.method")
    public let qualifiedName: String
    
    /// The kind of symbol
    public let kind: SymbolKind
    
    /// Hash of the file path and line number for disambiguation
    public let locationHash: String
    
    /// The string representation of this ID
    public var id: String {
        "\(moduleName)::\(qualifiedName)::\(kind.rawValue)::\(locationHash)"
    }
    
    public var description: String { id }
    
    public init(moduleName: String, qualifiedName: String, kind: SymbolKind, locationHash: String) {
        self.moduleName = moduleName
        self.qualifiedName = qualifiedName
        self.kind = kind
        self.locationHash = locationHash
    }
    
    /// Creates a SymbolID from location information
    public static func create(
        moduleName: String,
        qualifiedName: String,
        kind: SymbolKind,
        filePath: String,
        line: Int
    ) -> SymbolID {
        // Create a stable hash from file path and line number
        let locationString = "\(filePath):\(line)"
        let hash = locationString.utf8.reduce(0) { result, byte in
            result &+ Int(byte) &* 31
        }
        let locationHash = String(format: "%08x", abs(hash) % 0xFFFFFFFF)
        
        return SymbolID(
            moduleName: moduleName,
            qualifiedName: qualifiedName,
            kind: kind,
            locationHash: locationHash
        )
    }
}

// MARK: - Symbol

/// Represents a symbol found in Swift source code
public struct Symbol: Hashable, Codable, Sendable {
    /// Unique identifier for this symbol
    public let id: SymbolID
    
    /// The simple name of the symbol
    public let name: String
    
    /// The fully qualified name including parent scopes
    public let qualifiedName: String
    
    /// The kind of symbol (class, struct, function, etc.)
    public let kind: SymbolKind
    
    /// Source location of this symbol
    public let location: Location
    
    /// Accessibility level (private, internal, public, etc.)
    public let accessibility: Accessibility
    
    /// Attributes applied to this symbol (@available, @MainActor, etc.)
    public let attributes: [Attribute]
    
    /// The ID of the parent symbol, if this symbol is nested
    public let parentID: SymbolID?

    public init(
        id: SymbolID,
        name: String,
        qualifiedName: String,
        kind: SymbolKind,
        location: Location,
        accessibility: Accessibility,
        attributes: [Attribute] = [],
        parentID: SymbolID? = nil
    ) {
        self.id = id
        self.name = name
        self.qualifiedName = qualifiedName
        self.kind = kind
        self.location = location
        self.accessibility = accessibility
        self.attributes = attributes
        self.parentID = parentID
    }
    
    /// Convenience initializer that auto-generates the symbol ID
    public init(
        moduleName: String,
        name: String,
        qualifiedName: String,
        kind: SymbolKind,
        location: Location,
        accessibility: Accessibility,
        attributes: [Attribute] = [],
        parentID: SymbolID? = nil
    ) {
        self.id = SymbolID.create(
            moduleName: moduleName,
            qualifiedName: qualifiedName,
            kind: kind,
            filePath: location.file.path,
            line: location.line
        )
        self.name = name
        self.qualifiedName = qualifiedName
        self.kind = kind
        self.location = location
        self.accessibility = accessibility
        self.attributes = attributes
        self.parentID = parentID
    }
}

/// Types of symbols in Swift
public enum SymbolKind: String, Hashable, Codable, CaseIterable, Sendable {
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case actor
    case function
    case variable
    case `extension`
    case typeAlias
    case associatedType
    case `case`
    case initializer
    case deinitializer
    case `subscript`
    case `operator`
    case precedenceGroup
    case macro
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

// MARK: - Symbol References (Phase 3)

/// The kind of reference to a symbol
public enum ReferenceKind: String, Hashable, Codable, CaseIterable, Sendable {
    /// Function or method call (e.g., `foo()`, `obj.method()`)
    case functionCall
    /// Property or field access (e.g., `obj.property`)
    case propertyAccess
    /// Type reference in annotations (e.g., `let x: MyType`)
    case typeReference
    /// Superclass inheritance (e.g., `class Foo: Bar`)
    case inheritance
    /// Protocol conformance (e.g., `struct Foo: Equatable`)
    case conformance
    /// Bare identifier reference (e.g., `myVar`)
    case identifier
    /// Extension target type (e.g., `extension MyType`)
    case extensionTarget
    /// Enum case reference (e.g., `MyEnum.value`)
    case enumCase
    /// Initializer call (e.g., `MyType()`)
    case initializer
    /// Generic type parameter (e.g., `Array<MyType>`)
    case genericArgument
}

/// Represents a reference to a symbol found in source code
public struct SymbolReference: Hashable, Codable, Sendable {
    /// The simple name being referenced (e.g., "method", "MyType")
    public let referencedName: String
    
    /// The full expression for context (e.g., "object.method", "MyModule.MyType")
    public let fullExpression: String
    
    /// The kind of reference
    public let kind: ReferenceKind
    
    /// Location where the reference occurs in source
    public let location: Location
    
    /// The scope context where this reference appears (e.g., "MyClass.myMethod")
    /// Used to help resolve which symbol is being referenced
    public let scopeContext: String
    
    /// The inferred type of the base expression, if determinable
    /// For `obj.method()`, this would be the type of `obj`
    public let inferredBaseType: String?
    
    public init(
        referencedName: String,
        fullExpression: String,
        kind: ReferenceKind,
        location: Location,
        scopeContext: String,
        inferredBaseType: String? = nil
    ) {
        self.referencedName = referencedName
        self.fullExpression = fullExpression
        self.kind = kind
        self.location = location
        self.scopeContext = scopeContext
        self.inferredBaseType = inferredBaseType
    }
}