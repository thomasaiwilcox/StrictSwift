import Foundation

/// Represents a resolved type with its properties and relationships
public struct ResolvedType: Sendable {
    public let name: String
    public let kind: TypeKind
    public let module: String
    public var properties: [Property]
    public var methods: [Method]
    public var inheritanceChain: [String]
    public var conformances: [String]
    public let isPublic: Bool
    public let filePath: String

    // Ownership tracking properties
    public var isReferenceType: Bool = false
    public var hasWeakReferences: Bool = false
    public var hasUnownedReferences: Bool = false
    public var hasEscapingReferences: Bool = false
    public var estimatedSize: Int = 0
    public var isThreadSafe: Bool = true
    public var sendability: SendabilityLevel = .unknown
    public var lifetimeCategory: LifetimeCategory = .automatic
    public var ownershipComplexity: OwnershipComplexity = .low

    public init(
        name: String,
        kind: TypeKind,
        module: String,
        properties: [Property] = [],
        methods: [Method] = [],
        inheritanceChain: [String] = [],
        conformances: [String] = [],
        isPublic: Bool = false,
        filePath: String
    ) {
        self.name = name
        self.kind = kind
        self.module = module
        self.properties = properties
        self.methods = methods
        self.inheritanceChain = inheritanceChain
        self.conformances = conformances
        self.isPublic = isPublic
        self.filePath = filePath

        // Calculate ownership characteristics
        self.isReferenceType = Self.calculateIsReferenceType(kind: kind, properties: properties)
        self.hasWeakReferences = properties.contains { $0.type.hasPrefix("weak") || $0.type.hasPrefix("unowned") }
        self.hasUnownedReferences = properties.contains { $0.type.hasPrefix("unowned") }
        self.hasEscapingReferences = Self.calculateHasEscapingReferences(methods: methods)
        self.estimatedSize = Self.calculateEstimatedSize(properties: properties, kind: kind)
        self.isThreadSafe = Self.calculateIsThreadSafe(conformances: conformances, properties: properties)
        self.sendability = Self.calculateSendability(conformances: conformances)
        self.lifetimeCategory = Self.calculateLifetimeCategory(kind: kind)
        self.ownershipComplexity = Self.calculateOwnershipComplexity(properties: properties, methods: methods)
    }

    // MARK: - Static Helper Methods

    private static func calculateIsReferenceType(kind: TypeKind, properties: [Property]) -> Bool {
        return kind == .class
    }

    private static func calculateHasEscapingReferences(methods: [Method]) -> Bool {
        return methods.contains { method in
            method.returnType.contains("escaping") ||
            method.returnType.contains("@escaping") ||
            method.name.contains("completion") ||
            method.name.contains("handler")
        }
    }

    private static func calculateEstimatedSize(properties: [Property], kind: TypeKind) -> Int {
        var size = 8 // Base size for object header
        for property in properties {
            // Simple heuristic based on type
            if property.type.contains("String") {
                size += 16
            } else if property.type.contains("Int") || property.type.contains("Double") {
                size += 8
            } else if property.type.contains("Bool") {
                size += 1
            } else if property.type.contains("Array") {
                size += 24
            } else if property.type.contains("Dictionary") {
                size += 24
            } else {
                size += 8 // Default for unknown types
            }
        }
        return size
    }

    private static func calculateIsThreadSafe(conformances: [String], properties: [Property]) -> Bool {
        return conformances.contains("Sendable") ||
               conformances.contains("MainActor") ||
               properties.allSatisfy { $0.type.contains("let") }
    }

    private static func calculateSendability(conformances: [String]) -> SendabilityLevel {
        if conformances.contains("Sendable") {
            return .sendable
        } else if conformances.contains("MainActor") {
            return .mainActor
        } else {
            return .nonSendable
        }
    }

    private static func calculateLifetimeCategory(kind: TypeKind) -> LifetimeCategory {
        switch kind {
        case .class:
            return .reference
        case .struct:
            return .value
        case .enum:
            return .value
        case .protocol:
            return .unknown
        case .extension:
            return .unknown
        case .function:
            return .automatic
        case .actor:
            return .reference  // Actors are reference types
        }
    }

    private static func calculateOwnershipComplexity(properties: [Property], methods: [Method]) -> OwnershipComplexity {
        var complexityScore = 0

        // Factor in reference type properties
        let referenceTypeProperties = properties.filter { property in
            property.type.hasPrefix("class") || property.type.hasPrefix("Protocol") ||
            property.type.contains("Object") || property.type.contains("Controller")
        }
        complexityScore += referenceTypeProperties.count * 2

        // Factor in escaping parameters
        let escapingParameters = methods.flatMap { $0.parameters }.filter { $0.type.hasPrefix("@escaping") }
        complexityScore += escapingParameters.count * 3

        // Factor in closure parameters
        let closureParameters = methods.flatMap { $0.parameters }.filter { $0.type.hasPrefix("()") || $0.type.hasPrefix("->") }
        complexityScore += closureParameters.count * 2

        switch complexityScore {
        case 0..<5:
            return .low
        case 5..<15:
            return .medium
        case 15..<30:
            return .high
        default:
            return .critical
        }
    }
}

/// Kind of type
public enum TypeKind: String, CaseIterable, Sendable {
    case `class` = "class"
    case `struct` = "struct"
    case `protocol` = "protocol"
    case `enum` = "enum"
    case `extension` = "extension"
    case function = "function"
    case actor = "actor"
}

/// Represents a property of a type
public struct Property: Sendable {
    public let name: String
    public let type: String
    public let isMutable: Bool
    public let isOptional: Bool
    public let isStatic: Bool
    public let accessLevel: AccessLevel

    public init(name: String, type: String, isMutable: Bool, isOptional: Bool, isStatic: Bool, accessLevel: AccessLevel) {
        self.name = name
        self.type = type
        self.isMutable = isMutable
        self.isOptional = isOptional
        self.isStatic = isStatic
        self.accessLevel = accessLevel
    }
}

/// Represents a method of a type
public struct Method: Sendable {
    public let name: String
    public let parameters: [Parameter]
    public let returnType: String
    public let isStatic: Bool
    public let isAsync: Bool
    public let throwsError: Bool
    public let accessLevel: AccessLevel

    public init(
        name: String,
        parameters: [Parameter] = [],
        returnType: String = "Void",
        isStatic: Bool = false,
        isAsync: Bool = false,
        throwsError: Bool = false,
        accessLevel: AccessLevel = .internal
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.isStatic = isStatic
        self.isAsync = isAsync
        self.throwsError = throwsError
        self.accessLevel = accessLevel
    }
}

/// Represents a method parameter
public struct Parameter: Sendable {
    public let name: String
    public let type: String
    public let isOptional: Bool
    public let hasDefaultValue: Bool

    public init(name: String, type: String, isOptional: Bool = false, hasDefaultValue: Bool = false) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
        self.hasDefaultValue = hasDefaultValue
    }
}

/// Access levels in Swift
public enum AccessLevel: String, CaseIterable, Sendable, Codable {
    case `private` = "private"
    case `fileprivate` = "fileprivate"
    case `internal` = "internal"
    case `public` = "public"
    case `open` = "open"
}

/// Ownership complexity levels
public enum OwnershipComplexity: String, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

/// Sendability level for types
public enum SendabilityLevel: String, CaseIterable, Sendable {
    case unknown = "unknown"
    case sendable = "sendable"
    case actor = "actor"
    case mainActor = "main_actor"
    case nonSendable = "non_sendable"
}

/// Lifetime category for objects
public enum LifetimeCategory: String, CaseIterable, Sendable {
    case reference = "reference"
    case value = "value"
    case unknown = "unknown"
    case automatic = "automatic"
    case stack = "stack"
    case heap = "heap"
    case none = "none"
    case manual = "manual"
}
