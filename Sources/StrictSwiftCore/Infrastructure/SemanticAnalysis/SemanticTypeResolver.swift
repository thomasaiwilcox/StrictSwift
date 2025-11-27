import Foundation
import SwiftSyntax

// strictswift:ignore-file circular_dependency_graph -- SemanticTypeResolver↔ResolutionStats is intentional helper pattern

// MARK: - Semantic Type Resolver

/// Orchestrates semantic type resolution based on the configured mode
///
/// This is the main entry point for semantic analysis. It:
/// 1. Detects ambiguous references in the code
/// 2. Queries SourceKit for type information (in hybrid/full mode)
/// 3. Caches results for performance
/// 4. Provides resolved type information to rules
public actor SemanticTypeResolver {
    
    // MARK: - Types
    
    /// Resolved type information for a reference
    public struct ResolvedType: Sendable, Hashable {
        /// Fully qualified type name (e.g., "MyModule.MyClass")
        public let fullyQualifiedName: String
        
        /// Just the type name (e.g., "MyClass")
        public let simpleName: String
        
        /// The module where the type is defined
        public let moduleName: String?
        
        /// Whether this type is defined in the project (not external)
        public let isInternal: Bool
        
        /// The kind of type
        public let kind: TypeKind
        
        /// Confidence in the resolution (1.0 = certain from SourceKit)
        public let confidence: Double
        
        /// How the type was resolved
        public let source: ResolutionSource
        
        public enum TypeKind: String, Sendable {
            case `class`
            case `struct`
            case `enum`
            case `protocol`
            case function
            case property
            case unknown
        }
        
        public enum ResolutionSource: String, Sendable {
            /// Resolved from SourceKit query
            case sourceKit
            /// Resolved from syntactic analysis with explicit type annotation
            case explicitAnnotation
            /// Inferred from known type relationships
            case inferred
            /// Could not be resolved
            case unresolved
        }
        
        public init(
            fullyQualifiedName: String,
            simpleName: String? = nil,
            moduleName: String? = nil,
            isInternal: Bool = false,
            kind: TypeKind = .unknown,
            confidence: Double = 1.0,
            source: ResolutionSource = .sourceKit
        ) {
            self.fullyQualifiedName = fullyQualifiedName
            self.simpleName = simpleName ?? Self.extractSimpleName(from: fullyQualifiedName)
            self.moduleName = moduleName ?? Self.extractModuleName(from: fullyQualifiedName)
            self.isInternal = isInternal
            self.kind = kind
            self.confidence = confidence
            self.source = source
        }
        
        private static func extractSimpleName(from fqn: String) -> String {
            fqn.components(separatedBy: ".").last ?? fqn
        }
        
        private static func extractModuleName(from fqn: String) -> String? {
            let parts = fqn.components(separatedBy: ".")
            return parts.count > 1 ? parts.first : nil
        }
    }
    
    /// A reference location to resolve
    public struct ReferenceLocation: Hashable, Sendable {
        public let file: String
        public let line: Int
        public let column: Int
        public let identifier: String
        
        public init(file: String, line: Int, column: Int, identifier: String) {
            self.file = file
            self.line = line
            self.column = column
            self.identifier = identifier
        }
    }
    
    /// Statistics about resolution performance
    public struct ResolutionStats: Sendable {
        public var totalReferences: Int = 0
        public var resolvedFromSourceKit: Int = 0
        public var resolvedFromAnnotation: Int = 0
        public var resolvedFromInference: Int = 0
        public var unresolved: Int = 0
        public var sourceKitQueries: Int = 0
        public var cacheHits: Int = 0
        public var elapsedTime: TimeInterval = 0
        
        public var resolutionRate: Double {
            guard totalReferences > 0 else { return 0 }
            return Double(totalReferences - unresolved) / Double(totalReferences)
        }
        
        public var cacheHitRate: Double {
            let total = sourceKitQueries + cacheHits
            guard total > 0 else { return 0 }
            return Double(cacheHits) / Double(total)
        }
    }
    
    // MARK: - State
    
    private let mode: SemanticMode
    private let sourceKitClient: SourceKitClient?
    private let ambiguityDetector: AmbiguityDetector
    private let projectRoot: URL
    
    /// Cache of resolved types
    private var typeCache: [ReferenceLocation: ResolvedType] = [:]
    
    /// Known types from the codebase (for quick lookup)
    private var knownTypes: [String: ResolvedType] = [:]
    
    /// Resolution statistics
    private var stats = ResolutionStats()
    
    // MARK: - Initialization
    
    /// Initialize the resolver
    /// - Parameters:
    ///   - mode: The semantic analysis mode
    ///   - sourceKitClient: SourceKit client (required for hybrid/full modes)
    ///   - projectRoot: Root of the project
    public init(
        mode: SemanticMode,
        sourceKitClient: SourceKitClient?,
        projectRoot: URL
    ) {
        self.mode = mode
        self.sourceKitClient = sourceKitClient
        self.projectRoot = projectRoot
        self.ambiguityDetector = AmbiguityDetector()
    }
    
    /// Create a resolver based on resolved configuration
    public static func create(
        config: SemanticModeResolver.ResolvedConfiguration,
        capabilities: SemanticCapabilities,
        projectRoot: URL
    ) async throws -> SemanticTypeResolver {
        let client: SourceKitClient?
        if config.hasSemantic {
            client = try SourceKitClient.create(for: projectRoot, capabilities: capabilities)
        } else {
            client = nil
        }
        
        return SemanticTypeResolver(
            mode: config.effectiveMode,
            sourceKitClient: client,
            projectRoot: projectRoot
        )
    }
    
    // MARK: - Type Resolution
    
    /// Resolve the type of a reference
    /// - Parameter location: The reference location
    /// - Returns: Resolved type or nil if unresolvable
    public func resolveType(at location: ReferenceLocation) async -> ResolvedType? {
        stats.totalReferences += 1
        
        // Check cache first
        if let cached = typeCache[location] {
            stats.cacheHits += 1
            return cached
        }
        
        let resolved: ResolvedType?
        
        switch mode {
        case .off:
            // In off mode, we only use syntactic information
            resolved = resolveFromSyntax(at: location)
            
        case .hybrid:
            // In hybrid mode, first try syntactic, then query for ambiguous cases
            if let syntactic = resolveFromSyntax(at: location), 
               syntactic.confidence >= 0.9 {
                resolved = syntactic
            } else {
                resolved = await resolveFromSourceKit(at: location)
            }
            
        case .full:
            // In full mode, always query SourceKit
            resolved = await resolveFromSourceKit(at: location)
            
        case .auto:
            // Auto should be resolved to a concrete mode before this
            resolved = resolveFromSyntax(at: location)
        }
        
        // Update stats
        if let resolved = resolved {
            switch resolved.source {
            case .sourceKit: stats.resolvedFromSourceKit += 1
            case .explicitAnnotation: stats.resolvedFromAnnotation += 1
            case .inferred: stats.resolvedFromInference += 1
            case .unresolved: stats.unresolved += 1
            }
            typeCache[location] = resolved
        } else {
            stats.unresolved += 1
        }
        
        return resolved
    }
    
    /// Resolve types for multiple references (batch operation)
    /// - Parameter locations: The reference locations
    /// - Returns: Dictionary of resolved types
    public func resolveTypes(
        at locations: [ReferenceLocation]
    ) async -> [ReferenceLocation: ResolvedType] {
        var results: [ReferenceLocation: ResolvedType] = [:]
        
        // Separate cached vs uncached
        var uncachedLocations: [ReferenceLocation] = []
        
        for location in locations {
            if let cached = typeCache[location] {
                results[location] = cached
                stats.cacheHits += 1
            } else {
                uncachedLocations.append(location)
            }
        }
        
        stats.totalReferences += locations.count
        
        switch mode {
        case .off, .auto:
            // Syntactic only
            for location in uncachedLocations {
                if let resolved = resolveFromSyntax(at: location) {
                    results[location] = resolved
                    typeCache[location] = resolved
                }
            }
            
        case .hybrid:
            // Try syntactic first, then SourceKit for ambiguous
            var needsSourceKit: [ReferenceLocation] = []
            
            for location in uncachedLocations {
                if let syntactic = resolveFromSyntax(at: location),
                   syntactic.confidence >= 0.9 {
                    results[location] = syntactic
                    typeCache[location] = syntactic
                    stats.resolvedFromAnnotation += 1
                } else {
                    needsSourceKit.append(location)
                }
            }
            
            // Batch query SourceKit
            if !needsSourceKit.isEmpty, let client = sourceKitClient {
                let sourceKitResults = await batchQuerySourceKit(
                    locations: needsSourceKit,
                    client: client
                )
                for (location, resolved) in sourceKitResults {
                    results[location] = resolved
                    typeCache[location] = resolved
                }
            }
            
        case .full:
            // Query SourceKit for all
            if let client = sourceKitClient {
                let sourceKitResults = await batchQuerySourceKit(
                    locations: uncachedLocations,
                    client: client
                )
                for (location, resolved) in sourceKitResults {
                    results[location] = resolved
                    typeCache[location] = resolved
                }
            }
        }
        
        return results
    }
    
    /// Analyze a file and identify which references need semantic resolution
    /// - Parameters:
    ///   - syntax: The parsed syntax tree
    ///   - filePath: Path to the source file
    /// - Returns: List of ambiguous references
    public func detectAmbiguousReferences(
        in syntax: SourceFileSyntax,
        filePath: String
    ) -> [AmbiguityDetector.AmbiguousReference] {
        return ambiguityDetector.detectAmbiguities(
            in: syntax,
            filePath: filePath,
            knownTypes: Set(knownTypes.keys)
        )
    }
    
    /// Register known types from the codebase
    /// - Parameter types: Dictionary of type name to resolved type
    public func registerKnownTypes(_ types: [String: ResolvedType]) {
        for (name, type) in types {
            knownTypes[name] = type
        }
    }
    
    /// Get resolution statistics
    public func getStatistics() -> ResolutionStats {
        return stats
    }
    
    /// Clear caches and reset statistics
    public func reset() {
        typeCache.removeAll()
        stats = ResolutionStats()
    }
    
    // MARK: - Private Resolution Methods
    
    private func resolveFromSyntax(at location: ReferenceLocation) -> ResolvedType? {
        // First check if this is a known type
        if let known = knownTypes[location.identifier] {
            return ResolvedType(
                fullyQualifiedName: known.fullyQualifiedName,
                simpleName: known.simpleName,
                moduleName: known.moduleName,
                isInternal: known.isInternal,
                kind: known.kind,
                confidence: 0.9, // High but not 100% (could be shadowed)
                source: .inferred
            )
        }
        
        // Check if it's a standard library type
        if let stdType = resolveStandardLibraryType(location.identifier) {
            return stdType
        }
        
        // Can't resolve syntactically
        return nil
    }
    
    private func resolveFromSourceKit(at location: ReferenceLocation) async -> ResolvedType? {
        guard let client = sourceKitClient else { return nil }
        
        stats.sourceKitQueries += 1
        
        do {
            let info = try await client.cursorInfo(
                file: location.file,
                line: location.line,
                column: location.column
            )
            
            guard let cursorInfo = info else { return nil }
            
            let kind: ResolvedType.TypeKind
            switch cursorInfo.kind {
            case .class: kind = .class
            case .struct: kind = .struct
            case .enum: kind = .enum
            case .protocol: kind = .protocol
            case .function, .method, .staticMethod, .classMethod, .initializer:
                kind = .function
            case .property, .staticProperty, .classProperty, .globalVariable, .localVariable, .parameter:
                kind = .property
            default: kind = .unknown
            }
            
            return ResolvedType(
                fullyQualifiedName: cursorInfo.typeName ?? cursorInfo.usr ?? location.identifier,
                moduleName: cursorInfo.moduleName,
                isInternal: cursorInfo.isInternal,
                kind: kind,
                confidence: 1.0,
                source: .sourceKit
            )
        } catch {
            StrictSwiftLogger.debug("SourceKit query failed for \(location.identifier): \(error)")
            return nil
        }
    }
    
    private func batchQuerySourceKit(
        locations: [ReferenceLocation],
        client: SourceKitClient
    ) async -> [ReferenceLocation: ResolvedType] {
        var results: [ReferenceLocation: ResolvedType] = [:]
        
        // Convert to SourceKitClient locations
        let sourceKitLocations = locations.map { loc in
            SourceKitClient.Location(file: loc.file, line: loc.line, column: loc.column)
        }
        
        do {
            let infos = try await client.batchCursorInfo(locations: sourceKitLocations)
            
            // Map back to ReferenceLocations
            for location in locations {
                let skLocation = SourceKitClient.Location(
                    file: location.file,
                    line: location.line,
                    column: location.column
                )
                
                if let info = infos[skLocation] {
                    let kind: ResolvedType.TypeKind
                    switch info.kind {
                    case .class: kind = .class
                    case .struct: kind = .struct
                    case .enum: kind = .enum
                    case .protocol: kind = .protocol
                    case .function, .method, .staticMethod, .classMethod, .initializer:
                        kind = .function
                    case .property, .staticProperty, .classProperty, .globalVariable, .localVariable, .parameter:
                        kind = .property
                    default: kind = .unknown
                    }
                    
                    results[location] = ResolvedType(
                        fullyQualifiedName: info.typeName ?? info.usr ?? location.identifier,
                        moduleName: info.moduleName,
                        isInternal: info.isInternal,
                        kind: kind,
                        confidence: 1.0,
                        source: .sourceKit
                    )
                    
                    stats.resolvedFromSourceKit += 1
                }
            }
            
            stats.sourceKitQueries += locations.count
            
        } catch {
            // Only log at debug level - SourceKit failures are expected for multi-file projects
            // without full build context. Syntactic fallback will be used.
            StrictSwiftLogger.debug("Batch SourceKit query failed (falling back to syntactic): \(error)")
        }
        
        return results
    }
    
    private func resolveStandardLibraryType(_ name: String) -> ResolvedType? {
        let stdTypes: Set<String> = [
            "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Float", "Double", "String", "Bool",
            "Array", "Dictionary", "Set", "Optional",
            "Result", "Error", "Void", "Never"
        ]
        
        guard stdTypes.contains(name) else { return nil }
        
        let kind: ResolvedType.TypeKind
        switch name {
        case "Error": kind = .protocol
        case "Result", "Optional": kind = .enum
        default: kind = .struct
        }
        
        return ResolvedType(
            fullyQualifiedName: "Swift.\(name)",
            simpleName: name,
            moduleName: "Swift",
            isInternal: false,
            kind: kind,
            confidence: 1.0,
            source: .inferred
        )
    }
}

// MARK: - Logging

extension SemanticTypeResolver.ResolutionStats {
    public var summary: String {
        """
        Semantic Resolution Statistics:
          Total references: \(totalReferences)
          Resolved:
            - SourceKit: \(resolvedFromSourceKit)
            - Annotation: \(resolvedFromAnnotation)
            - Inference: \(resolvedFromInference)
          Unresolved: \(unresolved)
          Resolution rate: \(String(format: "%.1f%%", resolutionRate * 100))
          Cache hit rate: \(String(format: "%.1f%%", cacheHitRate * 100))
          SourceKit queries: \(sourceKitQueries)
          Elapsed time: \(String(format: "%.2fs", elapsedTime))
        """
    }
}
