import Foundation

// MARK: - Configuration

/// Analysis mode for dead code detection
public enum DeadCodeMode: String, Codable, Sendable {
    /// Library mode: public/open symbols are entry points
    case library
    /// Executable mode: @main, main.swift are entry points
    case executable
    /// Hybrid mode: both library and executable entry points
    case hybrid
}

/// Configuration for dead code analysis
public struct DeadCodeConfiguration: Sendable {
    /// Analysis mode (library vs executable)
    public let mode: DeadCodeMode
    
    /// Whether to treat public symbols as entry points (default: true in library mode)
    public let treatPublicAsEntryPoint: Bool
    
    /// Whether to treat open symbols as entry points (default: true)
    public let treatOpenAsEntryPoint: Bool
    
    /// Attributes that mark symbols as entry points
    public let entryPointAttributes: Set<String>
    
    /// File patterns for entry point files (e.g., "**/main.swift")
    public let entryPointFilePatterns: [String]
    
    /// Qualified name patterns to ignore (glob-style)
    public let ignoredPatterns: [String]
    
    /// Symbol name prefixes to ignore (e.g., "_" for private helpers)
    public let ignoredPrefixes: [String]
    
    /// Method names to ignore (for framework callbacks like SwiftSyntax visitors)
    public let ignoredMethodNames: Set<String>
    
    /// Protocols whose conforming types have synthesized members marked live
    public let synthesizedMemberProtocols: Set<String>
    
    /// SwiftSyntax visitor methods called via dynamic dispatch
    private static let swiftSyntaxVisitorMethods: Set<String> = [
        "visit", "visitPost", "visitAny", "visitAnyPost",
        "visitChildren", "walk", "shouldVisit"
    ]
    
    /// ArgumentParser methods called via protocol conformance
    private static let argumentParserMethods: Set<String> = [
        "run", "validate"
    ]
    
    /// Combined framework callback methods
    private static let frameworkCallbackMethods: Set<String> = 
        swiftSyntaxVisitorMethods.union(argumentParserMethods)
    
    /// Default configuration for library mode
    public static let libraryDefault = DeadCodeConfiguration(
        mode: .library,
        treatPublicAsEntryPoint: true,
        treatOpenAsEntryPoint: true,
        entryPointAttributes: ["main", "UIApplicationMain", "NSApplicationMain", "objc", "IBAction", "IBOutlet", "IBInspectable", "IBDesignable", "NSManaged", "testable"],
        entryPointFilePatterns: [],
        ignoredPatterns: [],
        ignoredPrefixes: ["_"],
        ignoredMethodNames: frameworkCallbackMethods,
        synthesizedMemberProtocols: ["Codable", "Encodable", "Decodable", "Hashable", "Equatable", "CaseIterable", "RawRepresentable"]
    )
    
    /// Default configuration for executable mode
    public static let executableDefault = DeadCodeConfiguration(
        mode: .executable,
        treatPublicAsEntryPoint: false,
        treatOpenAsEntryPoint: false,
        entryPointAttributes: ["main", "UIApplicationMain", "NSApplicationMain", "objc", "IBAction", "IBOutlet", "IBInspectable", "IBDesignable", "NSManaged"],
        entryPointFilePatterns: ["**/main.swift", "**/AppDelegate.swift"],
        ignoredPatterns: [],
        ignoredPrefixes: ["_"],
        ignoredMethodNames: frameworkCallbackMethods,
        synthesizedMemberProtocols: ["Codable", "Encodable", "Decodable", "Hashable", "Equatable", "CaseIterable", "RawRepresentable"]
    )
    
    /// Default configuration for hybrid mode
    public static let hybridDefault = DeadCodeConfiguration(
        mode: .hybrid,
        treatPublicAsEntryPoint: true,
        treatOpenAsEntryPoint: true,
        entryPointAttributes: ["main", "UIApplicationMain", "NSApplicationMain", "objc", "IBAction", "IBOutlet", "IBInspectable", "IBDesignable", "NSManaged", "testable"],
        entryPointFilePatterns: ["**/main.swift", "**/AppDelegate.swift"],
        ignoredPatterns: [],
        ignoredPrefixes: ["_"],
        ignoredMethodNames: frameworkCallbackMethods,
        synthesizedMemberProtocols: ["Codable", "Encodable", "Decodable", "Hashable", "Equatable", "CaseIterable", "RawRepresentable"]
    )
    
    public init(
        mode: DeadCodeMode,
        treatPublicAsEntryPoint: Bool,
        treatOpenAsEntryPoint: Bool,
        entryPointAttributes: Set<String>,
        entryPointFilePatterns: [String],
        ignoredPatterns: [String],
        ignoredPrefixes: [String],
        ignoredMethodNames: Set<String> = [],
        synthesizedMemberProtocols: Set<String>
    ) {
        self.mode = mode
        self.treatPublicAsEntryPoint = treatPublicAsEntryPoint
        self.treatOpenAsEntryPoint = treatOpenAsEntryPoint
        self.entryPointAttributes = entryPointAttributes
        self.entryPointFilePatterns = entryPointFilePatterns
        self.ignoredPatterns = ignoredPatterns
        self.ignoredPrefixes = ignoredPrefixes
        self.ignoredMethodNames = ignoredMethodNames
        self.synthesizedMemberProtocols = synthesizedMemberProtocols
    }
    
    /// Create configuration from YAML parameters
    /// Supports parameters:
    /// - mode: "library" | "executable" | "hybrid"
    /// - treatPublicAsEntryPoint: Bool
    /// - treatOpenAsEntryPoint: Bool
    /// - entryPointAttributes: [String]
    /// - entryPointFilePatterns: [String]
    /// - ignoredPatterns: [String]
    /// - ignoredPrefixes: [String]
    public static func from(parameters: [String: Any]) -> DeadCodeConfiguration {
        // Determine base configuration from mode
        let modeString = parameters["mode"] as? String ?? "library"
        let baseConfig: DeadCodeConfiguration
        
        switch modeString.lowercased() {
        case "executable":
            baseConfig = .executableDefault
        case "hybrid":
            baseConfig = .hybridDefault
        default:
            baseConfig = .libraryDefault
        }
        
        // Override with provided parameters
        let treatPublicAsEntryPoint = parameters["treatPublicAsEntryPoint"] as? Bool ?? baseConfig.treatPublicAsEntryPoint
        let treatOpenAsEntryPoint = parameters["treatOpenAsEntryPoint"] as? Bool ?? baseConfig.treatOpenAsEntryPoint
        
        // Handle arrays - can be provided as [String] or comma-separated string
        let entryPointAttributes: Set<String>
        if let attrs = parameters["entryPointAttributes"] as? [String] {
            entryPointAttributes = Set(attrs)
        } else if let attrString = parameters["entryPointAttributes"] as? String {
            entryPointAttributes = Set(attrString.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) })
        } else {
            entryPointAttributes = baseConfig.entryPointAttributes
        }
        
        let entryPointFilePatterns: [String]
        if let patterns = parameters["entryPointFilePatterns"] as? [String] {
            entryPointFilePatterns = patterns
        } else if let patternString = parameters["entryPointFilePatterns"] as? String {
            entryPointFilePatterns = patternString.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        } else {
            entryPointFilePatterns = baseConfig.entryPointFilePatterns
        }
        
        let ignoredPatterns: [String]
        if let patterns = parameters["ignoredPatterns"] as? [String] {
            ignoredPatterns = patterns
        } else if let patternString = parameters["ignoredPatterns"] as? String {
            ignoredPatterns = patternString.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        } else {
            ignoredPatterns = baseConfig.ignoredPatterns
        }
        
        let ignoredPrefixes: [String]
        if let prefixes = parameters["ignoredPrefixes"] as? [String] {
            ignoredPrefixes = prefixes
        } else if let prefixString = parameters["ignoredPrefixes"] as? String {
            ignoredPrefixes = prefixString.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        } else {
            ignoredPrefixes = baseConfig.ignoredPrefixes
        }
        
        // Handle ignoredMethodNames - merge with defaults from baseConfig
        let ignoredMethodNames: Set<String>
        if let methods = parameters["ignoredMethodNames"] as? [String] {
            ignoredMethodNames = baseConfig.ignoredMethodNames.union(methods)
        } else if let methodString = parameters["ignoredMethodNames"] as? String {
            let customMethods = methodString.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            ignoredMethodNames = baseConfig.ignoredMethodNames.union(customMethods)
        } else {
            ignoredMethodNames = baseConfig.ignoredMethodNames
        }
        
        let mode = DeadCodeMode(rawValue: modeString.lowercased()) ?? baseConfig.mode
        
        return DeadCodeConfiguration(
            mode: mode,
            treatPublicAsEntryPoint: treatPublicAsEntryPoint,
            treatOpenAsEntryPoint: treatOpenAsEntryPoint,
            entryPointAttributes: entryPointAttributes,
            entryPointFilePatterns: entryPointFilePatterns,
            ignoredPatterns: ignoredPatterns,
            ignoredPrefixes: ignoredPrefixes,
            ignoredMethodNames: ignoredMethodNames,
            synthesizedMemberProtocols: baseConfig.synthesizedMemberProtocols
        )
    }
}

// MARK: - Confidence Level

/// Confidence level for dead code detection
public enum DeadCodeConfidence: String, Codable, Sendable, Comparable {
    /// High confidence: Private/fileprivate symbol with no references
    case high
    /// Medium confidence: Internal symbol with no direct references
    case medium
    /// Low confidence: Public/open symbol with no references in analyzed code (might be used externally)
    case low
    
    public static func < (lhs: DeadCodeConfidence, rhs: DeadCodeConfidence) -> Bool {
        let order: [DeadCodeConfidence] = [.low, .medium, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// A dead symbol with its confidence level
public struct DeadSymbolInfo: Sendable {
    public let symbol: Symbol
    public let confidence: DeadCodeConfidence
    
    public init(symbol: Symbol, confidence: DeadCodeConfidence) {
        self.symbol = symbol
        self.confidence = confidence
    }
}

// MARK: - Result

/// Result of dead code analysis
public struct DeadCodeResult: Sendable {
    /// Symbols identified as entry points
    public let entryPoints: [Symbol]
    
    /// Symbols reachable from entry points (live code)
    public let liveSymbols: Set<SymbolID>
    
    /// Symbols not reachable from any entry point (dead code) with confidence levels
    public let deadSymbolsWithConfidence: [DeadSymbolInfo]
    
    /// Symbols not reachable from any entry point (dead code) - convenience accessor
    public var deadSymbols: [Symbol] {
        deadSymbolsWithConfidence.map { $0.symbol }
    }
    
    /// Symbols that were ignored based on configuration
    public let ignoredSymbols: [Symbol]
    
    /// Statistics about the analysis
    public let statistics: AnalysisStatistics
    
    public struct AnalysisStatistics: Sendable {
        public let totalSymbols: Int
        public let entryPointCount: Int
        public let liveCount: Int
        public let deadCount: Int
        public let ignoredCount: Int
        public let analysisTimeMs: Double
        
        /// Dead symbols grouped by confidence level
        public let byConfidence: ConfidenceBreakdown
        
        /// Dead symbols grouped by kind
        public let byKind: [String: Int]
        
        public struct ConfidenceBreakdown: Sendable {
            public let high: Int
            public let medium: Int
            public let low: Int
        }
    }
}

// MARK: - Analyzer

/// Analyzes code reachability to detect dead (unused) code
public final class DeadCodeAnalyzer: Sendable {
    private let graph: GlobalReferenceGraph
    private let configuration: DeadCodeConfiguration
    
    public init(graph: GlobalReferenceGraph, configuration: DeadCodeConfiguration = .libraryDefault) {
        self.graph = graph
        self.configuration = configuration
    }
    
    /// Perform dead code analysis
    public func analyze() -> DeadCodeResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let allSymbols = graph.allSymbols()
        
        // Step 1: Identify entry points and ignored symbols
        var entryPoints: [Symbol] = []
        var ignored: [Symbol] = []
        var ignoredButLive: [Symbol] = []  // Framework callbacks that should be treated as live
        
        for symbol in allSymbols {
            if shouldIgnore(symbol) {
                ignored.append(symbol)
                // If ignored due to being a framework callback method (ignoredMethodNames),
                // treat it as live so internal references get followed
                if symbol.kind == .function && configuration.ignoredMethodNames.contains(symbol.name) {
                    ignoredButLive.append(symbol)
                }
            } else if isEntryPoint(symbol) {
                entryPoints.append(symbol)
            }
        }
        
        // Step 2: BFS from entry points AND ignored-but-live symbols to find all reachable symbols
        var visited = Set<SymbolID>()
        var queue = entryPoints.map { $0.id } + ignoredButLive.map { $0.id }
        
        while !queue.isEmpty {
            let current = queue.removeFirst()
            
            if visited.contains(current) {
                continue
            }
            visited.insert(current)
            
            // Follow outgoing reference edges
            for referenced in graph.getReferences(current) {
                if !visited.contains(referenced) {
                    queue.append(referenced)
                }
            }
            
            // Mark children as live if parent is live
            markChildrenLive(of: current, visited: &visited, queue: &queue)
            
            // Mark protocol implementations as live
            markProtocolImplementationsLive(for: current, visited: &visited, queue: &queue)
            
            // Mark synthesized members as live for special protocols
            markSynthesizedMembersLive(for: current, visited: &visited, queue: &queue)
        }
        
        // Step 3: Identify dead symbols (not visited and not ignored)
        let ignoredIDs = Set(ignored.map { $0.id })
        let deadSymbols = allSymbols.filter { symbol in
            !visited.contains(symbol.id) && !ignoredIDs.contains(symbol.id)
        }
        
        // Step 4: Calculate confidence levels for dead symbols
        let deadSymbolsWithConfidence = deadSymbols.map { symbol in
            DeadSymbolInfo(symbol: symbol, confidence: calculateConfidence(for: symbol))
        }
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        // Calculate statistics with confidence breakdown
        let confidenceBreakdown = DeadCodeResult.AnalysisStatistics.ConfidenceBreakdown(
            high: deadSymbolsWithConfidence.filter { $0.confidence == .high }.count,
            medium: deadSymbolsWithConfidence.filter { $0.confidence == .medium }.count,
            low: deadSymbolsWithConfidence.filter { $0.confidence == .low }.count
        )
        
        // Calculate kind breakdown
        var kindCounts: [String: Int] = [:]
        for symbol in deadSymbols {
            kindCounts[symbol.kind.rawValue, default: 0] += 1
        }
        
        let statistics = DeadCodeResult.AnalysisStatistics(
            totalSymbols: allSymbols.count,
            entryPointCount: entryPoints.count,
            liveCount: visited.count,
            deadCount: deadSymbols.count,
            ignoredCount: ignored.count,
            analysisTimeMs: elapsed,
            byConfidence: confidenceBreakdown,
            byKind: kindCounts
        )
        
        return DeadCodeResult(
            entryPoints: entryPoints,
            liveSymbols: visited,
            deadSymbolsWithConfidence: deadSymbolsWithConfidence,
            ignoredSymbols: ignored,
            statistics: statistics
        )
    }
    
    // MARK: - Confidence Calculation
    
    /// Calculate confidence level for a dead symbol
    private func calculateConfidence(for symbol: Symbol) -> DeadCodeConfidence {
        switch symbol.accessibility {
        case .private, .fileprivate:
            // Private symbols with no references are definitely dead
            return .high
        case .internal, .package:
            // Internal/package symbols might be used via reflection or in tests
            return .medium
        case .public, .open:
            // Public symbols might be used by external consumers not in analyzed scope
            return .low
        }
    }
    
    // MARK: - Entry Point Detection
    
    /// Check if a symbol is an entry point
    public func isEntryPoint(_ symbol: Symbol) -> Bool {
        // Check accessibility-based entry points
        if configuration.treatOpenAsEntryPoint && symbol.accessibility == .open {
            return true
        }
        
        if configuration.treatPublicAsEntryPoint && symbol.accessibility == .public {
            return true
        }
        
        // Check attribute-based entry points
        for attribute in symbol.attributes {
            if configuration.entryPointAttributes.contains(attribute.name) {
                return true
            }
        }
        
        // Check file pattern-based entry points
        let filePath = symbol.location.file.path
        for pattern in configuration.entryPointFilePatterns {
            if matchesGlobPattern(filePath, pattern: pattern) {
                return true
            }
        }
        
        // XCTest classes and test methods are entry points
        if isTestSymbol(symbol) {
            return true
        }
        
        return false
    }
    
    /// Check if a symbol should be ignored from dead code analysis
    public func shouldIgnore(_ symbol: Symbol) -> Bool {
        // Check ignored prefixes
        for prefix in configuration.ignoredPrefixes {
            if symbol.name.hasPrefix(prefix) {
                return true
            }
        }
        
        // Check ignored method names (for framework callbacks like SwiftSyntax visitors)
        // Functions with a parent are methods
        if symbol.kind == .function {
            if configuration.ignoredMethodNames.contains(symbol.name) {
                return true
            }
        }
        
        // Check ignored patterns
        for pattern in configuration.ignoredPatterns {
            if matchesGlobPattern(symbol.qualifiedName, pattern: pattern) {
                return true
            }
        }
        
        // Protocol requirements should be ignored - they are implicitly live if the protocol is live
        // and their implementations are tracked separately
        if let parentID = symbol.parentID,
           let parent = graph.symbol(for: parentID),
           parent.kind == .protocol {
            return true
        }
        
        // Associated types are protocol requirements
        if symbol.kind == .associatedType {
            return true
        }
        
        // Extensions themselves are not "dead" - their members can be
        if symbol.kind == .extension {
            return true
        }
        
        // Deinitializers are always called automatically
        if symbol.kind == .deinitializer {
            return true
        }
        
        return false
    }
    
    // MARK: - Reachability Helpers
    
    /// Mark children of a symbol as live
    private func markChildrenLive(of symbolID: SymbolID, visited: inout Set<SymbolID>, queue: inout [SymbolID]) {
        guard let symbol = graph.symbol(for: symbolID) else { return }
        
        // If a type is live, its members accessed from within are also potentially live
        // We traverse the entire scope to find children
        let children = graph.symbolsInScope(symbol.qualifiedName)
        
        // Check if this type has @main attribute
        let hasMainAttribute = symbol.attributes.contains { $0.name == "main" }
        
        for child in children where child.id != symbolID {
            // Check if child's parent is this symbol
            if child.parentID == symbolID && !visited.contains(child.id) {
                // Mark initializers as live if type is live (they're implicitly used)
                if child.kind == .initializer {
                    queue.append(child.id)
                }
                // Deinitializers are always live if the type is live
                if child.kind == .deinitializer {
                    queue.append(child.id)
                }
                // If type has @main, mark static main() function as live
                if hasMainAttribute && child.kind == .function && child.name == "main" {
                    queue.append(child.id)
                }
            }
        }
    }
    
    /// Mark protocol requirement implementations as live
    private func markProtocolImplementationsLive(for symbolID: SymbolID, visited: inout Set<SymbolID>, queue: inout [SymbolID]) {
        guard let symbol = graph.symbol(for: symbolID) else { return }
        
        // If this is a type, check its protocol conformances
        if isTypeKind(symbol.kind) {
            let conformedProtocols = graph.getConformedProtocols(symbolID)
            
            for protocolID in conformedProtocols {
                // Get all requirements of this protocol
                let requirements = graph.getProtocolRequirements(protocolID)
                
                for requirement in requirements {
                    // Find implementations of this requirement in the conforming type
                    let implementations = graph.getImplementingMethods(requirement.id)
                    
                    for implID in implementations {
                        if let impl = graph.symbol(for: implID),
                           impl.parentID == symbolID,
                           !visited.contains(implID) {
                            queue.append(implID)
                        }
                    }
                }
            }
        }
        
        // If this is a protocol method, mark all implementations
        if symbol.kind == .function || symbol.kind == .variable {
            if let parentID = symbol.parentID,
               let parent = graph.symbol(for: parentID),
               parent.kind == .protocol {
                let implementations = graph.getImplementingMethods(symbolID)
                for implID in implementations where !visited.contains(implID) {
                    queue.append(implID)
                }
            }
        }
    }
    
    /// Mark synthesized members as live for special protocols (Codable, Equatable, etc.)
    private func markSynthesizedMembersLive(for symbolID: SymbolID, visited: inout Set<SymbolID>, queue: inout [SymbolID]) {
        guard let symbol = graph.symbol(for: symbolID) else { return }
        guard isTypeKind(symbol.kind) else { return }
        
        // Get conformance from both SymbolID-based and name-based tracking
        // Name-based is needed for stdlib protocols like CaseIterable
        let conformedProtocols = graph.getConformedProtocols(symbolID)
        let conformedProtocolNames = graph.getConformedProtocolNames(symbolID)
        
        // Combine: get names from both sources
        var allProtocolNames = conformedProtocolNames
        for protocolID in conformedProtocols {
            if let protocolSymbol = graph.symbol(for: protocolID) {
                allProtocolNames.insert(protocolSymbol.name)
            }
        }
        
        // Check each protocol name
        for protocolName in allProtocolNames {
            // Check if this is a protocol with synthesized members
            if configuration.synthesizedMemberProtocols.contains(protocolName) {
                // Mark synthesized members as live
                let children = graph.symbolsInScope(symbol.qualifiedName)
                
                for child in children where child.parentID == symbolID {
                    // CodingKeys enum for Codable
                    if child.name == "CodingKeys" && child.kind == .enum {
                        if !visited.contains(child.id) {
                            queue.append(child.id)
                        }
                    }
                    
                    // encode(to:) and init(from:) for Codable, plus all stored properties
                    if protocolName == "Codable" || protocolName == "Encodable" || protocolName == "Decodable" {
                        // Mark encode/init methods
                        if child.name == "encode" || child.name == "init" {
                            if !visited.contains(child.id) {
                                queue.append(child.id)
                            }
                        }
                        // Mark stored properties as live (they're encoded/decoded)
                        if child.kind == .variable {
                            if !visited.contains(child.id) {
                                queue.append(child.id)
                            }
                        }
                    }
                    
                    // == operator for Equatable
                    if child.name == "==" && protocolName == "Equatable" {
                        if !visited.contains(child.id) {
                            queue.append(child.id)
                        }
                    }
                    
                    // hash(into:) for Hashable
                    if child.name == "hash" && protocolName == "Hashable" {
                        if !visited.contains(child.id) {
                            queue.append(child.id)
                        }
                    }
                    
                    // allCases for CaseIterable - also mark all enum cases as live
                    if protocolName == "CaseIterable" {
                        if child.name == "allCases" {
                            if !visited.contains(child.id) {
                                queue.append(child.id)
                            }
                        }
                        // Mark all enum cases as live when CaseIterable is conformed
                        if child.kind == .case {
                            if !visited.contains(child.id) {
                                queue.append(child.id)
                            }
                        }
                    }
                    
                    // rawValue for RawRepresentable
                    if (child.name == "rawValue" || child.name == "init") && protocolName == "RawRepresentable" {
                        if !visited.contains(child.id) {
                            queue.append(child.id)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Utility Methods
    
    /// Check if a symbol kind represents a type
    private func isTypeKind(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .struct, .enum, .actor:
            return true
        default:
            return false
        }
    }
    
    /// Check if a symbol is a test (XCTest class or test method)
    private func isTestSymbol(_ symbol: Symbol) -> Bool {
        // Check if it's a test class (ends with Tests or Test)
        if symbol.kind == .class {
            if symbol.name.hasSuffix("Tests") || symbol.name.hasSuffix("Test") {
                return true
            }
        }
        
        // Check if it's a test method (starts with test)
        if symbol.kind == .function && symbol.name.hasPrefix("test") {
            return true
        }
        
        return false
    }
    
    /// Simple glob pattern matching
    private func matchesGlobPattern(_ string: String, pattern: String) -> Bool {
        // Convert glob to regex
        var regex = "^"
        for char in pattern {
            switch char {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            case ".":
                regex += "\\."
            case "/":
                regex += "/"
            default:
                regex += String(char)
            }
        }
        regex += "$"
        
        // Handle ** for recursive directory matching
        regex = regex.replacingOccurrences(of: ".*.*", with: ".*")
        
        guard let re = try? NSRegularExpression(pattern: regex, options: []) else {
            return false
        }
        
        let range = NSRange(string.startIndex..., in: string)
        return re.firstMatch(in: string, options: [], range: range) != nil
    }
}
