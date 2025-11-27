import Foundation

// MARK: - Conditional Conformance Types

/// Represents a requirement in a where clause for conditional conformance
public enum WhereRequirement: Hashable, Codable, Sendable {
    /// Type parameter must conform to a protocol (e.g., `Element: Equatable`)
    case conformance(typeParam: String, protocolName: String)
    /// Type parameter must be same as concrete type (e.g., `Element == Int`)
    case sameType(typeParam: String, concreteType: String)
}

/// Represents a conditional conformance with its where clause requirements
public struct ConditionalConformance: Hashable, Codable, Sendable {
    /// The type that conditionally conforms
    public let conformingTypeID: SymbolID
    /// The protocol being conformed to
    public let protocolName: String
    /// The requirements that must be satisfied
    public let requirements: [WhereRequirement]
    /// Location of the extension declaring this conformance
    public let location: Location
    
    public init(
        conformingTypeID: SymbolID,
        protocolName: String,
        requirements: [WhereRequirement],
        location: Location
    ) {
        self.conformingTypeID = conformingTypeID
        self.protocolName = protocolName
        self.requirements = requirements
        self.location = location
    }
}

// MARK: - Global Reference Graph

/// A graph structure linking symbol definitions to their references across the entire codebase.
/// Used for dead code detection by enabling reachability analysis from entry points.
///
/// SAFETY: @unchecked Sendable is safe because all mutable state is protected by NSLock.
public final class GlobalReferenceGraph: @unchecked Sendable {
    private let lock = NSLock()
    
    // MARK: - Symbol Indexes
    
    /// Primary index: SymbolID → Symbol for O(1) lookup
    private var symbolsByID: [SymbolID: Symbol] = [:]
    
    /// Name-based index for resolution: simple name → [SymbolID]
    /// One name can map to multiple symbols (e.g., multiple types named "Config")
    private var symbolsByName: [String: [SymbolID]] = [:]
    
    /// Qualified name index for precise lookups: qualified name → [SymbolID]
    /// Handles overloads at same qualified name (different locationHash)
    private var symbolsByQualifiedName: [String: [SymbolID]] = [:]
    
    /// File-based index for incremental updates: file URL → [SymbolID]
    private var symbolsByFile: [URL: Set<SymbolID>] = [:]
    
    // MARK: - Reference Edges
    
    /// Incoming edges: target symbol → set of symbols that reference it
    private var referencedBy: [SymbolID: Set<SymbolID>] = [:]
    
    /// Outgoing edges: source symbol → set of symbols it references
    private var references: [SymbolID: Set<SymbolID>] = [:]
    
    /// File-based reference tracking for incremental updates
    private var referencesByFile: [URL: [SymbolReference]] = [:]
    
    // MARK: - Protocol Conformance
    
    /// Protocol method → implementing methods in conforming types
    private var protocolImplementations: [SymbolID: Set<SymbolID>] = [:]
    
    /// Type → protocols it implements (by SymbolID for protocols in codebase)
    private var implementsProtocol: [SymbolID: Set<SymbolID>] = [:]
    
    /// Type → protocol names it conforms to (for stdlib/external protocols)
    private var conformsToProtocolName: [SymbolID: Set<String>] = [:]
    
    // MARK: - Associated Types
    
    /// Conforming type → [associated type name → concrete type SymbolID]
    private var associatedTypeBindings: [SymbolID: [String: SymbolID]] = [:]
    
    // MARK: - Conditional Conformance
    
    /// Type → conditional conformances declared via extensions
    private var conditionalConformances: [SymbolID: [ConditionalConformance]] = [:]
    
    // MARK: - Sendable Conformance Cache
    
    /// Cache for Sendable conformance checks (performance optimization)
    private var sendableConformanceCache: [SymbolID: Bool] = [:]
    
    // MARK: - Diagnostics
    
    /// References that could not be resolved to any symbol
    private var _unresolvedReferences: [SymbolReference] = []
    
    public var unresolvedReferences: [SymbolReference] {
        lock.lock()
        defer { lock.unlock() }
        return _unresolvedReferences
    }
    
    // MARK: - Statistics
    
    public var symbolCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return symbolsByID.count
    }
    
    public var edgeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return references.values.reduce(0) { $0 + $1.count }
    }
    
    /// Get all symbols in the graph
    public func allSymbols() -> [Symbol] {
        lock.lock()
        defer { lock.unlock() }
        return Array(symbolsByID.values)
    }
    
    public init() {}
    
    // MARK: - Symbol Registration
    
    /// Register a symbol in all indexes
    public func registerSymbol(_ symbol: Symbol) {
        lock.lock()
        defer { lock.unlock() }
        
        // Primary index
        symbolsByID[symbol.id] = symbol
        
        // Name index
        symbolsByName[symbol.name, default: []].append(symbol.id)
        
        // Qualified name index
        symbolsByQualifiedName[symbol.qualifiedName, default: []].append(symbol.id)
        
        // File index
        symbolsByFile[symbol.location.file, default: []].insert(symbol.id)
    }
    
    /// Look up a symbol by its ID
    public func symbol(for id: SymbolID) -> Symbol? {
        lock.lock()
        defer { lock.unlock() }
        return symbolsByID[id]
    }
    
    /// Find all symbols with a given simple name
    public func symbols(named name: String) -> [Symbol] {
        lock.lock()
        defer { lock.unlock() }
        guard let ids = symbolsByName[name] else { return [] }
        return ids.compactMap { symbolsByID[$0] }
    }
    
    /// Find all symbols with a given qualified name
    public func symbols(qualifiedName: String) -> [Symbol] {
        lock.lock()
        defer { lock.unlock() }
        guard let ids = symbolsByQualifiedName[qualifiedName] else { return [] }
        return ids.compactMap { symbolsByID[$0] }
    }
    
    /// Get all symbols within a scope (matching qualified name prefix)
    public func symbolsInScope(_ scope: String) -> [Symbol] {
        lock.lock()
        defer { lock.unlock() }
        
        let prefix = scope.isEmpty ? "" : scope + "."
        return symbolsByID.values.filter { symbol in
            scope.isEmpty || symbol.qualifiedName.hasPrefix(prefix) || symbol.qualifiedName == scope
        }
    }
    
    /// Get all symbols from a specific file
    public func symbols(inFile url: URL) -> [Symbol] {
        lock.lock()
        defer { lock.unlock() }
        guard let ids = symbolsByFile[url] else { return [] }
        return ids.compactMap { symbolsByID[$0] }
    }
    
    // MARK: - Edge Management
    
    /// Add a reference edge from source to target
    public func addEdge(from source: SymbolID, to target: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        
        references[source, default: []].insert(target)
        referencedBy[target, default: []].insert(source)
    }
    
    /// Get all symbols that reference the given symbol
    public func getReferencedBy(_ symbolID: SymbolID) -> Set<SymbolID> {
        lock.lock()
        defer { lock.unlock() }
        return referencedBy[symbolID] ?? []
    }
    
    /// Get all symbols that the given symbol references
    public func getReferences(_ symbolID: SymbolID) -> Set<SymbolID> {
        lock.lock()
        defer { lock.unlock() }
        return references[symbolID] ?? []
    }
    
    // MARK: - Protocol Conformance
    
    /// Record that a type implements a protocol
    public func addProtocolConformance(type typeID: SymbolID, protocol protocolID: SymbolID) {
        lock.lock()
        defer { lock.unlock() }
        implementsProtocol[typeID, default: []].insert(protocolID)
    }
    
    /// Record that a type conforms to a protocol by name (for stdlib/external protocols)
    public func addProtocolConformanceByName(type typeID: SymbolID, protocolName: String) {
        lock.lock()
        defer { lock.unlock() }
        conformsToProtocolName[typeID, default: []].insert(protocolName)
    }
    
    /// Record that a method implements a protocol requirement
    public func addProtocolImplementation(
        protocolMethod: SymbolID,
        implementingMethod: SymbolID
    ) {
        lock.lock()
        defer { lock.unlock() }
        protocolImplementations[protocolMethod, default: []].insert(implementingMethod)
    }
    
    /// Get all protocols a type conforms to
    public func getConformedProtocols(_ typeID: SymbolID) -> Set<SymbolID> {
        lock.lock()
        defer { lock.unlock() }
        return implementsProtocol[typeID] ?? []
    }
    
    /// Get all protocol names a type conforms to (including stdlib/external protocols)
    public func getConformedProtocolNames(_ typeID: SymbolID) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return conformsToProtocolName[typeID] ?? []
    }
    
    /// Get all methods that implement a protocol requirement
    public func getImplementingMethods(_ protocolMethodID: SymbolID) -> Set<SymbolID> {
        lock.lock()
        defer { lock.unlock() }
        return protocolImplementations[protocolMethodID] ?? []
    }
    
    /// Get all requirements (methods, properties) of a protocol
    public func getProtocolRequirements(_ protocolID: SymbolID) -> [Symbol] {
        lock.lock()
        defer { lock.unlock() }
        
        // Find all symbols whose parent is this protocol
        return symbolsByID.values.filter { $0.parentID == protocolID }
    }
    
    /// Check if a type conforms to Sendable (directly or via inheritance)
    /// Results are cached for performance
    public func conformsToSendable(_ typeID: SymbolID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // Check cache first
        if let cached = sendableConformanceCache[typeID] {
            return cached
        }
        
        // Check direct Sendable conformance by name
        if let protocolNames = conformsToProtocolName[typeID],
           protocolNames.contains("Sendable") {
            sendableConformanceCache[typeID] = true
            return true
        }
        
        // Check if any conformed protocol is Sendable
        if let conformedProtocols = implementsProtocol[typeID] {
            for protocolID in conformedProtocols {
                if let protocolSymbol = symbolsByID[protocolID],
                   protocolSymbol.name == "Sendable" {
                    sendableConformanceCache[typeID] = true
                    return true
                }
            }
        }
        
        // Check superclass (for class types)
        if let symbol = symbolsByID[typeID],
           symbol.kind == .class,
           let parentID = symbol.parentID,
           let parent = symbolsByID[parentID],
           parent.kind == .class {
            // Recursively check parent class - release lock temporarily
            lock.unlock()
            let parentConforms = conformsToSendable(parentID)
            lock.lock()
            if parentConforms {
                sendableConformanceCache[typeID] = true
                return true
            }
        }
        
        // Structs and enums with all Sendable members are implicitly Sendable
        // This is a simplification - full check would analyze all stored properties
        if let symbol = symbolsByID[typeID],
           (symbol.kind == .struct || symbol.kind == .enum) {
            // Check if explicitly marked @unchecked Sendable
            if symbol.attributes.contains(where: { $0.name == "unchecked" }) {
                sendableConformanceCache[typeID] = true
                return true
            }
        }
        
        sendableConformanceCache[typeID] = false
        return false
    }
    
    // MARK: - Associated Types
    
    /// Record an associated type binding for a conforming type
    public func addAssociatedTypeBinding(
        conformingType: SymbolID,
        associatedTypeName: String,
        concreteType: SymbolID
    ) {
        lock.lock()
        defer { lock.unlock() }
        associatedTypeBindings[conformingType, default: [:]][associatedTypeName] = concreteType
    }
    
    /// Get the concrete type bound to an associated type for a conforming type
    public func getAssociatedTypeBinding(
        _ conformingType: SymbolID,
        associatedType: String
    ) -> SymbolID? {
        lock.lock()
        defer { lock.unlock() }
        return associatedTypeBindings[conformingType]?[associatedType]
    }
    
    // MARK: - Conditional Conformance
    
    /// Add a conditional conformance for a type
    public func addConditionalConformance(_ conformance: ConditionalConformance) {
        lock.lock()
        defer { lock.unlock() }
        conditionalConformances[conformance.conformingTypeID, default: []].append(conformance)
    }
    
    /// Get all conditional conformances for a type
    public func getConditionalConformances(_ typeID: SymbolID) -> [ConditionalConformance] {
        lock.lock()
        defer { lock.unlock() }
        return conditionalConformances[typeID] ?? []
    }
    
    // MARK: - Reference Resolution
    
    /// Resolve a reference to potential matching symbols
    /// Returns all candidates that could match (conservative approach for dead code detection)
    public func resolveReference(
        _ ref: SymbolReference,
        fromFile file: SourceFile
    ) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        
        // Step 1: Get all symbols with matching name
        guard let nameMatches = symbolsByName[ref.referencedName], !nameMatches.isEmpty else {
            return []
        }
        
        var candidates = nameMatches
        
        // Step 2: Filter by kind compatibility
        candidates = candidates.filter { id in
            guard let symbol = symbolsByID[id] else { return false }
            return isKindCompatible(referenceKind: ref.kind, symbolKind: symbol.kind)
        }
        
        if candidates.isEmpty {
            return []
        }
        
        // Step 3: If inferredBaseType is available, prioritize type matches
        if let baseType = ref.inferredBaseType {
            let typeMatches = candidates.filter { id in
                guard let symbol = symbolsByID[id] else { return false }
                // Check if symbol is a member of the base type
                // Handle both "Type.member" and "Module.Type.member" patterns
                let qualifiedName = symbol.qualifiedName
                
                // Direct match: "BaseType.member"
                if qualifiedName.hasPrefix(baseType + ".") {
                    return true
                }
                
                // Module-qualified match: "*.BaseType.member"
                // Check if qualified name contains ".BaseType." anywhere
                if qualifiedName.contains("." + baseType + ".") {
                    return true
                }
                
                // Also check if the parent's name matches the base type
                if let parentID = symbol.parentID,
                   let parent = symbolsByID[parentID],
                   parent.name == baseType {
                    return true
                }
                
                return false
            }
            if !typeMatches.isEmpty {
                return typeMatches
            }
        }
        
        // Step 4: Use scope context for same-scope prioritization
        if !ref.scopeContext.isEmpty {
            let scopeMatches = candidates.filter { id in
                guard let symbol = symbolsByID[id] else { return false }
                // Check if symbol is in the same scope or a parent scope
                return isScopeCompatible(referenceScope: ref.scopeContext, symbolQualifiedName: symbol.qualifiedName)
            }
            if !scopeMatches.isEmpty {
                return scopeMatches
            }
        }
        
        // Step 5: Use imports to filter external module candidates
        let moduleMatches = filterByImports(candidates, fileImports: file.imports)
        if !moduleMatches.isEmpty {
            return moduleMatches
        }
        
        // Step 6: Return all remaining candidates (conservative approach)
        return candidates
    }
    
    /// Check if a reference kind is compatible with a symbol kind
    private func isKindCompatible(referenceKind: ReferenceKind, symbolKind: SymbolKind) -> Bool {
        switch referenceKind {
        case .functionCall:
            return symbolKind == .function || symbolKind == .initializer
        case .initializer:
            return symbolKind == .class || symbolKind == .struct || 
                   symbolKind == .enum || symbolKind == .actor
        case .propertyAccess:
            return symbolKind == .variable || symbolKind == .case
        case .typeReference, .inheritance, .conformance, .extensionTarget, .genericArgument:
            return symbolKind == .class || symbolKind == .struct || 
                   symbolKind == .enum || symbolKind == .protocol || 
                   symbolKind == .actor || symbolKind == .typeAlias
        case .enumCase:
            return symbolKind == .case
        case .identifier:
            // Could be anything - function, variable, type
            return true
        }
    }
    
    /// Check if symbol's scope is compatible with reference scope
    private func isScopeCompatible(referenceScope: String, symbolQualifiedName: String) -> Bool {
        // Symbol is in same scope if its qualified name starts with the scope
        // Or if it's at a parent scope level
        let scopeParts = referenceScope.split(separator: ".")
        
        // Check if symbol could be accessed from reference scope
        // (same scope, parent scope, or sibling type's scope)
        for i in 0...scopeParts.count {
            let checkScope = scopeParts.prefix(i).joined(separator: ".")
            if symbolQualifiedName.hasPrefix(checkScope) {
                return true
            }
        }
        
        return false
    }
    
    /// Filter candidates by module imports
    private func filterByImports(_ candidates: [SymbolID], fileImports: [Import]) -> [SymbolID] {
        let importedModules = Set(fileImports.map { $0.moduleName })
        
        return candidates.filter { id in
            // Include if symbol's module is imported or is the same module
            importedModules.contains(id.moduleName) || id.moduleName == "Unknown"
        }
    }
    
    // MARK: - Graph Construction
    
    /// Build the reference graph from a collection of source files
    public func build(from files: [SourceFile]) {
        // Pass 1: Register all symbols
        for file in files {
            for symbol in file.symbols {
                registerSymbol(symbol)
            }
        }
        
        // Pass 2: Build protocol conformance mappings
        buildProtocolConformances(from: files)
        
        // Pass 3: Build associated type bindings
        buildAssociatedTypeBindings(from: files)
        
        // Pass 4: Build conditional conformance mappings
        buildConditionalConformances(from: files)
        
        // Pass 5: Collect references and resolve edges
        for file in files {
            collectAndResolveReferences(from: file)
        }
    }
    
    /// Build protocol conformance mappings from conformance references
    private func buildProtocolConformances(from files: [SourceFile]) {
        lock.lock()
        defer { lock.unlock() }
        
        for file in files {
            // Run reference collector to find conformance references
            let collector = ReferenceCollector(fileURL: file.url, tree: file.tree, moduleName: file.moduleName)
            collector.walk(file.tree)
            
            for ref in collector.references where ref.kind == .conformance {
                // Find the conforming type (scope context)
                let conformingTypes = symbolsByQualifiedName[ref.scopeContext] ?? 
                                     symbolsByName[ref.scopeContext.split(separator: ".").last.map(String.init) ?? ref.scopeContext] ?? []
                
                // Find the protocol
                let protocols = symbolsByName[ref.referencedName]?.filter { id in
                    symbolsByID[id]?.kind == .protocol
                } ?? []
                
                // Create conformance relationships
                for typeID in conformingTypes {
                    // Always store the protocol name for stdlib/external protocol support
                    conformsToProtocolName[typeID, default: []].insert(ref.referencedName)
                    
                    for protocolID in protocols {
                        implementsProtocol[typeID, default: []].insert(protocolID)
                        
                        // Link protocol requirements to implementing methods
                        let requirements = symbolsByID.values.filter { $0.parentID == protocolID }
                        for requirement in requirements {
                            // Find matching method in conforming type
                            let implementingMethods = symbolsByID.values.filter { symbol in
                                symbol.parentID == typeID && symbol.name == requirement.name
                            }
                            for impl in implementingMethods {
                                protocolImplementations[requirement.id, default: []].insert(impl.id)
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Build associated type bindings from typealias declarations
    private func buildAssociatedTypeBindings(from files: [SourceFile]) {
        lock.lock()
        defer { lock.unlock() }
        
        for file in files {
            for symbol in file.symbols where symbol.kind == .typeAlias {
                // Check if this typealias is inside a type that conforms to a protocol
                guard let parentID = symbol.parentID,
                      let conformedProtocols = implementsProtocol[parentID] else {
                    continue
                }
                
                // Check if any conformed protocol has an associated type with this name
                for protocolID in conformedProtocols {
                    let protocolRequirements = symbolsByID.values.filter { 
                        $0.parentID == protocolID && $0.kind == .associatedType 
                    }
                    
                    for req in protocolRequirements where req.name == symbol.name {
                        // This typealias binds the associated type
                        // Note: We'd need to parse the typealias's underlying type
                        // For now, we record the typealias itself as the binding
                        associatedTypeBindings[parentID, default: [:]][symbol.name] = symbol.id
                    }
                }
            }
        }
    }
    
    /// Build conditional conformance mappings from extension where clauses
    private func buildConditionalConformances(from files: [SourceFile]) {
        // This requires parsing GenericWhereClauseSyntax from extensions
        // We'll need to enhance SymbolCollector or create a separate visitor
        // For now, this is a placeholder for the structure
        
        // TODO: Implement where clause parsing in SymbolCollector
        // and pass the information through Symbol or a separate structure
    }
    
    /// Collect references from a file and resolve them to edges
    private func collectAndResolveReferences(from file: SourceFile) {
        let collector = ReferenceCollector(fileURL: file.url, tree: file.tree, moduleName: file.moduleName)
        collector.walk(file.tree)
        
        lock.lock()
        // Store references for incremental updates
        referencesByFile[file.url] = collector.references
        lock.unlock()
        
        // Find the scope context symbol for each reference
        for ref in collector.references {
            let resolved = resolveReference(ref, fromFile: file)
            
            if resolved.isEmpty {
                lock.lock()
                _unresolvedReferences.append(ref)
                lock.unlock()
            } else {
                // Find the source symbol (the one containing this reference)
                let sourceSymbols = findContainingSymbol(for: ref, in: file)
                
                for sourceID in sourceSymbols {
                    for targetID in resolved {
                        addEdge(from: sourceID, to: targetID)
                    }
                }
            }
        }
    }
    
    /// Find the symbol that contains a reference (based on scope context)
    private func findContainingSymbol(for ref: SymbolReference, in file: SourceFile) -> [SymbolID] {
        lock.lock()
        defer { lock.unlock() }
        
        if ref.scopeContext.isEmpty {
            // Top-level reference - might be in a top-level function or global
            return []
        }
        
        // Find symbols matching the scope context
        return symbolsByQualifiedName[ref.scopeContext] ?? []
    }
    
    // MARK: - Incremental Updates
    
    /// Add a file to the graph (incremental update)
    public func addFile(_ file: SourceFile) {
        // Register symbols
        for symbol in file.symbols {
            registerSymbol(symbol)
        }
        
        // Collect and resolve references
        collectAndResolveReferences(from: file)
    }
    
    /// Remove a file from the graph (incremental update)
    public func removeFile(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        
        // Get symbols in this file
        guard let symbolIDs = symbolsByFile[url] else { return }
        
        // Remove symbols from all indexes
        for symbolID in symbolIDs {
            if let symbol = symbolsByID[symbolID] {
                // Remove from name index
                symbolsByName[symbol.name]?.removeAll { $0 == symbolID }
                if symbolsByName[symbol.name]?.isEmpty == true {
                    symbolsByName.removeValue(forKey: symbol.name)
                }
                
                // Remove from qualified name index
                symbolsByQualifiedName[symbol.qualifiedName]?.removeAll { $0 == symbolID }
                if symbolsByQualifiedName[symbol.qualifiedName]?.isEmpty == true {
                    symbolsByQualifiedName.removeValue(forKey: symbol.qualifiedName)
                }
                
                // Remove from primary index
                symbolsByID.removeValue(forKey: symbolID)
            }
            
            // Remove edges involving this symbol
            references.removeValue(forKey: symbolID)
            referencedBy.removeValue(forKey: symbolID)
            
            // Remove from other symbols' edge lists
            for (otherID, _) in references {
                references[otherID]?.remove(symbolID)
            }
            for (otherID, _) in referencedBy {
                referencedBy[otherID]?.remove(symbolID)
            }
            
            // Remove protocol conformance data
            implementsProtocol.removeValue(forKey: symbolID)
            protocolImplementations.removeValue(forKey: symbolID)
            associatedTypeBindings.removeValue(forKey: symbolID)
            conditionalConformances.removeValue(forKey: symbolID)
        }
        
        // Remove file tracking
        symbolsByFile.removeValue(forKey: url)
        referencesByFile.removeValue(forKey: url)
        
        // Remove unresolved references from this file
        _unresolvedReferences.removeAll { $0.location.file == url }
    }
    
    /// Update a file in the graph (atomic remove + add)
    public func updateFile(_ file: SourceFile) {
        removeFile(file.url)
        addFile(file)
    }
    
    /// Clear the entire graph
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        symbolsByID.removeAll()
        symbolsByName.removeAll()
        symbolsByQualifiedName.removeAll()
        symbolsByFile.removeAll()
        references.removeAll()
        referencedBy.removeAll()
        referencesByFile.removeAll()
        protocolImplementations.removeAll()
        implementsProtocol.removeAll()
        associatedTypeBindings.removeAll()
        conditionalConformances.removeAll()
        _unresolvedReferences.removeAll()
    }
    
    // MARK: - Semantic Enhancement
    
    /// Result of semantic enhancement
    public struct SemanticEnhancementResult: Sendable {
        /// Number of previously unresolved references now resolved
        public let newlyResolved: Int
        /// Number of references with improved precision (fewer candidates)
        public let improvedPrecision: Int
        /// Number of edges added
        public let edgesAdded: Int
        /// Number of edges removed (incorrect)
        public let edgesRemoved: Int
    }
    
    /// Enhance the reference graph using semantic type information
    /// 
    /// In hybrid/full mode, this method re-resolves unresolved references
    /// and improves precision on ambiguous references using SourceKit type data.
    /// 
    /// - Parameters:
    ///   - resolver: The semantic type resolver to use
    ///   - files: Source files to enhance (all files if nil)
    /// - Returns: Statistics about the enhancement
    public func enhanceWithSemantics(
        using resolver: SemanticTypeResolver,
        for files: [SourceFile]? = nil
    ) async -> SemanticEnhancementResult {
        // Extract data synchronously first
        let (unresolvedRefs, filesToProcess) = extractDataForEnhancement(files: files)
        
        var newlyResolved = 0
        var improvedPrecision = 0
        var edgesAdded = 0
        var edgesRemoved = 0
        
        // Group unresolved references by file for batch querying
        let refsByFile = Dictionary(grouping: unresolvedRefs) { $0.location.file }
        
        for file in filesToProcess {
            guard let fileRefs = refsByFile[file.url] else { continue }
            
            // Convert to resolver locations for batch query
            let locations = fileRefs.map { ref in
                SemanticTypeResolver.ReferenceLocation(
                    file: file.url.path,
                    line: ref.location.line,
                    column: ref.location.column,
                    identifier: ref.referencedName
                )
            }
            
            // Batch resolve types
            let resolvedTypes = await resolver.resolveTypes(at: locations)
            
            // Process results - apply enhancements synchronously
            for (index, ref) in fileRefs.enumerated() {
                let location = locations[index]
                
                guard let resolvedType = resolvedTypes[location] else { continue }
                
                // Try to find matching symbols using the resolved type info
                let result = applyEnhancement(ref: ref, resolvedType: resolvedType, file: file)
                
                if result.wasResolved {
                    newlyResolved += 1
                }
                if result.precisionImproved {
                    improvedPrecision += 1
                }
                edgesAdded += result.edgesAdded
                edgesRemoved += result.edgesRemoved
            }
        }
        
        return SemanticEnhancementResult(
            newlyResolved: newlyResolved,
            improvedPrecision: improvedPrecision,
            edgesAdded: edgesAdded,
            edgesRemoved: edgesRemoved
        )
    }
    
    /// Extract data needed for enhancement (synchronous, can use locks)
    private func extractDataForEnhancement(files: [SourceFile]?) -> ([SymbolReference], [SourceFile]) {
        lock.lock()
        defer { lock.unlock() }
        let unresolvedRefs = _unresolvedReferences
        let filesToProcess = files ?? []
        return (unresolvedRefs, filesToProcess)
    }
    
    /// Apply enhancement to a single reference (synchronous, can use locks)
    private func applyEnhancement(
        ref: SymbolReference,
        resolvedType: SemanticTypeResolver.ResolvedType,
        file: SourceFile
    ) -> ReferenceEnhancementResult {
        lock.lock()
        defer { lock.unlock() }
        return enhanceReference(ref, with: resolvedType, in: file)
    }
    
    /// Enhancement result for a single reference
    private struct ReferenceEnhancementResult {
        var wasResolved: Bool = false
        var precisionImproved: Bool = false
        var edgesAdded: Int = 0
        var edgesRemoved: Int = 0
    }
    
    /// Enhance a single reference using semantic type info
    /// Called with lock held
    private func enhanceReference(
        _ ref: SymbolReference,
        with resolvedType: SemanticTypeResolver.ResolvedType,
        in file: SourceFile
    ) -> ReferenceEnhancementResult {
        var result = ReferenceEnhancementResult()
        
        // Find symbols matching the resolved type's fully qualified name
        var candidates: [SymbolID] = []
        
        // Search by fully qualified name first
        if let matches = symbolsByQualifiedName[resolvedType.fullyQualifiedName] {
            candidates = matches
        }
        
        // Also search by simple name within the module
        if candidates.isEmpty, let moduleName = resolvedType.moduleName {
            let moduleQualified = "\(moduleName).\(resolvedType.simpleName)"
            if let matches = symbolsByQualifiedName[moduleQualified] {
                candidates = matches
            }
        }
        
        // Try matching by simple name + type filtering
        if candidates.isEmpty, let nameMatches = symbolsByName[resolvedType.simpleName] {
            candidates = nameMatches.filter { id in
                guard let symbol = symbolsByID[id] else { return false }
                return isKindCompatibleWithResolvedType(symbol.kind, resolvedType.kind)
            }
        }
        
        guard !candidates.isEmpty else { return result }
        
        // Find the source symbol (who is referencing)
        let sourceID: SymbolID?
        if !ref.scopeContext.isEmpty {
            // Find the symbol at this scope
            sourceID = symbolsByQualifiedName[ref.scopeContext]?.first
        } else {
            sourceID = nil
        }
        
        // If we have a single clear match, it's high confidence
        if candidates.count == 1, let targetID = candidates.first {
            let wasUnresolved = _unresolvedReferences.contains(ref)
            
            // Add the edge
            if let sourceID = sourceID {
                if references[sourceID] == nil {
                    references[sourceID] = []
                }
                let wasNew = references[sourceID]?.insert(targetID).inserted ?? false
                if wasNew {
                    result.edgesAdded += 1
                }
                
                if referencedBy[targetID] == nil {
                    referencedBy[targetID] = []
                }
                referencedBy[targetID]?.insert(sourceID)
            }
            
            // Remove from unresolved
            if wasUnresolved {
                _unresolvedReferences.removeAll { $0 == ref }
                result.wasResolved = true
            }
        }
        
        return result
    }
    
    /// Check if symbol kind is compatible with resolved type kind
    private func isKindCompatibleWithResolvedType(
        _ symbolKind: SymbolKind,
        _ typeKind: SemanticTypeResolver.ResolvedType.TypeKind
    ) -> Bool {
        switch typeKind {
        case .class:
            return symbolKind == .class
        case .struct:
            return symbolKind == .struct
        case .enum:
            return symbolKind == .enum
        case .protocol:
            return symbolKind == .protocol
        case .function:
            return symbolKind == .function || symbolKind == .initializer
        case .property:
            return symbolKind == .variable
        case .unknown:
            return true // Accept any
        }
    }
}
