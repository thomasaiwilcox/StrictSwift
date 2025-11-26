import Foundation
import SwiftSyntax

// MARK: - Location Converter

/// Extension to easily create ReferenceLocation from SwiftSyntax nodes
public extension SemanticTypeResolver.ReferenceLocation {
    /// Create a reference location from a SwiftSyntax node
    /// - Parameters:
    ///   - node: The syntax node to get location from
    ///   - sourceFile: The source file containing the node
    ///   - identifier: The identifier name being referenced
    init(from node: SyntaxProtocol, in sourceFile: SourceFile, identifier: String) {
        let location = sourceFile.location(of: node)
        self.init(
            file: sourceFile.url.path,
            line: location.line,
            column: location.column,
            identifier: identifier
        )
    }
    
    /// Create a reference location from a position
    /// - Parameters:
    ///   - position: The absolute position in the source
    ///   - sourceFile: The source file
    ///   - identifier: The identifier name being referenced
    init(from position: AbsolutePosition, in sourceFile: SourceFile, identifier: String) {
        let location = sourceFile.location(for: position)
        self.init(
            file: sourceFile.url.path,
            line: location.line,
            column: location.column,
            identifier: identifier
        )
    }
}

// MARK: - Type Safety Checker

/// Helper for checking type safety properties using semantic resolution
public struct TypeSafetyChecker: Sendable {
    
    // MARK: - Known Types
    
    /// Types known to be Sendable (built-in)
    public static let knownSendableTypes: Set<String> = [
        // Value types
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Float", "Double", "Float16", "Float80",
        "Bool", "String", "Character",
        "UUID", "URL", "Date", "Data",
        "Decimal", "CGFloat", "CGPoint", "CGSize", "CGRect",
        
        // Optionals of value types are Sendable
        "Optional", "Int?", "String?", "Bool?", "Double?",
        
        // Collections of Sendable are Sendable
        "Array", "Dictionary", "Set",
        
        // Atomics
        "Atomic", "AtomicInteger", "AtomicBool",
        "ManagedAtomic", "UnsafeAtomic",
        
        // Actor types
        "MainActor", "GlobalActor",
        
        // Result and other common Sendable types
        "Result", "Never", "Void", "()"
    ]
    
    /// Types known to be non-Sendable
    public static let knownNonSendableTypes: Set<String> = [
        // UIKit/AppKit types
        "UIView", "UIViewController", "UILabel", "UIButton", "UIImageView",
        "UITextField", "UITextView", "UITableView", "UICollectionView",
        "UINavigationController", "UITabBarController", "UIWindow",
        "NSView", "NSViewController", "NSWindow", "NSApplication",
        "CALayer", "CAAnimation",
        
        // Foundation mutable types
        "NSObject", "NSMutableArray", "NSMutableDictionary", "NSMutableSet",
        "NSMutableString", "NSMutableData", "NSMutableAttributedString",
        
        // Core Data
        "NSManagedObject", "NSManagedObjectContext", "NSPersistentContainer",
        
        // Other common non-Sendable types
        "Timer", "UserDefaults", "URLSession", "URLSessionTask",
        "URLSessionDataTask", "URLSessionDownloadTask",
        "FileHandle", "Stream", "InputStream", "OutputStream",
        "NotificationCenter", "RunLoop",
        "DispatchSource", "DispatchIO",
        
        // Core Graphics
        "CGContext", "CGImage", "CGColorSpace", "CGPath", "CGMutablePath"
    ]
    
    /// Types that are thread-safe (can be accessed from concurrent contexts)
    public static let knownThreadSafeTypes: Set<String> = [
        // Atomics
        "Atomic", "AtomicInteger", "AtomicBool", "AtomicReference",
        "ManagedAtomic", "UnsafeAtomic",
        "OSAllocatedUnfairLock", "NSLock", "NSRecursiveLock",
        
        // Actor types
        "Actor", "MainActor", "GlobalActor",
        
        // Thread-safe collections
        "NSCache", "DispatchQueue", "DispatchSemaphore",
        
        // Immutable reference types
        "NSNumber", "NSString", "NSArray", "NSDictionary", "NSSet"
    ]
    
    // MARK: - Type Checking Methods
    
    /// Check if a type name is known to be Sendable
    public static func isKnownSendable(_ typeName: String) -> Bool {
        let baseName = extractBaseName(typeName)
        return knownSendableTypes.contains(baseName)
    }
    
    /// Check if a type name is known to be non-Sendable
    public static func isKnownNonSendable(_ typeName: String) -> Bool {
        let baseName = extractBaseName(typeName)
        return knownNonSendableTypes.contains(baseName)
    }
    
    /// Check if a type is known to be thread-safe
    public static func isKnownThreadSafe(_ typeName: String) -> Bool {
        let baseName = extractBaseName(typeName)
        return knownThreadSafeTypes.contains(baseName)
    }
    
    /// Check if a resolved type has value semantics (struct or enum)
    public static func hasValueSemantics(_ resolvedType: SemanticTypeResolver.ResolvedType) -> Bool {
        return resolvedType.kind == .struct || resolvedType.kind == .enum
    }
    
    /// Check if a resolved type is an actor
    public static func isActor(_ resolvedType: SemanticTypeResolver.ResolvedType) -> Bool {
        // Check kind directly
        if case .unknown = resolvedType.kind {
            // Fall back to name-based detection
            let name = resolvedType.simpleName
            return name.hasSuffix("Actor") || name == "MainActor"
        }
        // For now, actors show up as .class in SourceKit, so also check name
        let name = resolvedType.simpleName
        return name.hasSuffix("Actor") || name == "MainActor" ||
               resolvedType.fullyQualifiedName.contains("Actor")
    }
    
    /// Check if a resolved type is likely Sendable based on its properties
    public static func isLikelySendable(_ resolvedType: SemanticTypeResolver.ResolvedType) -> Bool {
        // Value types are Sendable if their properties are Sendable
        if hasValueSemantics(resolvedType) {
            return true // Assume value types are Sendable unless proven otherwise
        }
        
        // Actors are always Sendable
        if isActor(resolvedType) {
            return true
        }
        
        // Check known types
        if isKnownSendable(resolvedType.simpleName) {
            return true
        }
        
        return false
    }
    
    /// Check if a resolved type is likely non-Sendable
    public static func isLikelyNonSendable(_ resolvedType: SemanticTypeResolver.ResolvedType) -> Bool {
        // Check known non-Sendable types first
        if isKnownNonSendable(resolvedType.simpleName) {
            return true
        }
        
        // Classes are non-Sendable by default unless marked
        if resolvedType.kind == .class && !isKnownSendable(resolvedType.simpleName) {
            return true
        }
        
        return false
    }
    
    // MARK: - Helpers
    
    /// Extract the base type name (without generics, optionals, etc.)
    private static func extractBaseName(_ typeName: String) -> String {
        var name = typeName
        
        // Remove optional suffix
        if name.hasSuffix("?") || name.hasSuffix("!") {
            name = String(name.dropLast())
        }
        
        // Remove generic parameters
        if let angleBracket = name.firstIndex(of: "<") {
            name = String(name[..<angleBracket])
        }
        
        // Remove module prefix
        if let dot = name.lastIndex(of: ".") {
            name = String(name[name.index(after: dot)...])
        }
        
        return name
    }
}

// MARK: - Batch Resolution Helper

/// Helper for efficiently resolving multiple types in a rule
public struct BatchTypeResolver {
    
    /// Resolve types for multiple locations, with fallback for failures
    /// - Parameters:
    ///   - locations: Array of reference locations to resolve
    ///   - resolver: The semantic type resolver
    /// - Returns: Dictionary mapping locations to resolved types (only successful resolutions)
    public static func resolveTypes(
        at locations: [SemanticTypeResolver.ReferenceLocation],
        using resolver: SemanticTypeResolver
    ) async -> [SemanticTypeResolver.ReferenceLocation: SemanticTypeResolver.ResolvedType] {
        guard !locations.isEmpty else { return [:] }
        
        // Use batch resolution for efficiency
        return await resolver.resolveTypes(at: locations)
    }
}

// MARK: - Capture Extraction

/// Helper for extracting captured variables from closures
public struct CaptureExtractor {
    
    /// Represents a captured variable in a closure
    public struct CapturedVariable {
        public let name: String
        public let node: SyntaxProtocol
        public let isWeak: Bool
        public let isUnowned: Bool
        
        public init(name: String, node: SyntaxProtocol, isWeak: Bool = false, isUnowned: Bool = false) {
            self.name = name
            self.node = node
            self.isWeak = isWeak
            self.isUnowned = isUnowned
        }
    }
    
    /// Extract captured variables from a closure's capture list
    public static func extractCaptures(from closure: ClosureExprSyntax) -> [CapturedVariable] {
        var captures: [CapturedVariable] = []
        
        guard let signature = closure.signature,
              let captureClause = signature.capture else {
            return captures
        }
        
        for item in captureClause.items {
            let itemText = item.trimmedDescription
            let isWeak = itemText.hasPrefix("weak ")
            let isUnowned = itemText.hasPrefix("unowned ")
            
            // Extract the variable name
            let expr = item.expression
            let name = extractIdentifier(from: expr)
            if !name.isEmpty {
                captures.append(CapturedVariable(
                    name: name,
                    node: item,
                    isWeak: isWeak,
                    isUnowned: isUnowned
                ))
            }
        }
        
        return captures
    }
    
    /// Extract identifier name from an expression
    private static func extractIdentifier(from expr: ExprSyntax) -> String {
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
        // For "self" captures
        let text = expr.trimmedDescription
        if text == "self" || text.hasSuffix(".self") {
            return "self"
        }
        return text
    }
}
