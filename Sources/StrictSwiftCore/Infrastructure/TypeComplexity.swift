import Foundation

/// Represents the complexity metrics of a type
public struct TypeComplexity: Sendable {
    public let propertyCount: Int
    public let methodCount: Int
    public let inheritanceDepth: Int
    public let protocolCount: Int
    public let publicMembersCount: Int

    public init(
        propertyCount: Int,
        methodCount: Int,
        inheritanceDepth: Int,
        protocolCount: Int,
        publicMembersCount: Int
    ) {
        self.propertyCount = propertyCount
        self.methodCount = methodCount
        self.inheritanceDepth = inheritanceDepth
        self.protocolCount = protocolCount
        self.publicMembersCount = publicMembersCount
    }

    /// Calculate a simple complexity score
    public var complexityScore: Int {
        return propertyCount * 2 + methodCount + inheritanceDepth * 3 + protocolCount * 2 + publicMembersCount
    }

    /// Determine if the type is likely a "God Class"
    public var isGodClass: Bool {
        return complexityScore > 50 || methodCount > 20 || propertyCount > 15
    }

    /// Determine if the type has high cyclomatic complexity
    public var hasHighComplexity: Bool {
        return methodCount > 15 && propertyCount > 10
    }
}
