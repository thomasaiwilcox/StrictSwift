import Foundation

// MARK: - SourceKit Client

/// A client for querying SourceKit for type information
///
/// This client uses the SourceKit C API (via dlopen) and provides methods for:
/// - Cursor info queries (get type of expression at location)
/// - Document structure queries (get symbol tree)
/// - Code completion (for checking available members)
///
/// The client uses caching to avoid redundant queries for the same location.
public actor SourceKitClient {
    
    // MARK: - Types
    
    /// Result of a cursor info query
    public struct CursorInfo: Sendable {
        /// The fully qualified type name (e.g., "Swift.String", "MyModule.MyClass")
        public let typeName: String?
        
        /// The USR (Unified Symbol Resolution) identifier
        public let usr: String?
        
        /// The kind of symbol (function, property, class, etc.)
        public let kind: SymbolKind?
        
        /// Whether the symbol is defined in the project or external
        public let isInternal: Bool
        
        /// The module where the symbol is defined
        public let moduleName: String?
        
        /// Declaration text (for functions, includes signature)
        public let declaration: String?
        
        /// Documentation comment if available
        public let documentation: String?
        
        public enum SymbolKind: String, Sendable {
            case `class` = "source.lang.swift.decl.class"
            case `struct` = "source.lang.swift.decl.struct"
            case `enum` = "source.lang.swift.decl.enum"
            case `protocol` = "source.lang.swift.decl.protocol"
            case actor = "source.lang.swift.decl.actor"
            case function = "source.lang.swift.decl.function.free"
            case method = "source.lang.swift.decl.function.method.instance"
            case staticMethod = "source.lang.swift.decl.function.method.static"
            case classMethod = "source.lang.swift.decl.function.method.class"
            case property = "source.lang.swift.decl.var.instance"
            case staticProperty = "source.lang.swift.decl.var.static"
            case classProperty = "source.lang.swift.decl.var.class"
            case globalVariable = "source.lang.swift.decl.var.global"
            case localVariable = "source.lang.swift.decl.var.local"
            case parameter = "source.lang.swift.decl.var.parameter"
            case `typealias` = "source.lang.swift.decl.typealias"
            case associatedType = "source.lang.swift.decl.associatedtype"
            case genericTypeParam = "source.lang.swift.decl.generic_type_param"
            case `extension` = "source.lang.swift.decl.extension"
            case enumCase = "source.lang.swift.decl.enumelement"
            case initializer = "source.lang.swift.decl.function.constructor"
            case `deinit` = "source.lang.swift.decl.function.destructor"
            case `subscript` = "source.lang.swift.decl.function.subscript"
            case accessor = "source.lang.swift.decl.function.accessor.getter"
            case unknown
            
            public init(rawValue: String) {
                switch rawValue {
                case "source.lang.swift.decl.class": self = .class
                case "source.lang.swift.decl.struct": self = .struct
                case "source.lang.swift.decl.enum": self = .enum
                case "source.lang.swift.decl.protocol": self = .protocol
                case "source.lang.swift.decl.actor": self = .actor
                case "source.lang.swift.decl.function.free": self = .function
                case "source.lang.swift.decl.function.method.instance": self = .method
                case "source.lang.swift.decl.function.method.static": self = .staticMethod
                case "source.lang.swift.decl.function.method.class": self = .classMethod
                case "source.lang.swift.decl.var.instance": self = .property
                case "source.lang.swift.decl.var.static": self = .staticProperty
                case "source.lang.swift.decl.var.class": self = .classProperty
                case "source.lang.swift.decl.var.global": self = .globalVariable
                case "source.lang.swift.decl.var.local": self = .localVariable
                case "source.lang.swift.decl.var.parameter": self = .parameter
                case "source.lang.swift.decl.typealias": self = .typealias
                case "source.lang.swift.decl.associatedtype": self = .associatedType
                case "source.lang.swift.decl.generic_type_param": self = .genericTypeParam
                case "source.lang.swift.decl.extension": self = .extension
                case "source.lang.swift.decl.enumelement": self = .enumCase
                case "source.lang.swift.decl.function.constructor": self = .initializer
                case "source.lang.swift.decl.function.destructor": self = .deinit
                case "source.lang.swift.decl.function.subscript": self = .subscript
                default:
                    if rawValue.contains("accessor") {
                        self = .accessor
                    } else {
                        self = .unknown
                    }
                }
            }
        }
    }
    
    /// Query location
    public struct Location: Hashable, Sendable {
        public let file: String
        public let line: Int
        public let column: Int
        
        public init(file: String, line: Int, column: Int) {
            self.file = file
            self.line = line
            self.column = column
        }
    }
    
    /// Error types for SourceKit operations
    public enum SourceKitError: Error, Sendable {
        case notAvailable(String)
        case loadFailed(String)
        case queryFailed(String)
        case parseError(String)
        case timeout
    }
    
    // MARK: - State
    
    private let projectRoot: URL
    private let compilerArguments: [String]
    
    /// The underlying SourceKit service (uses C API)
    private var service: SourceKitDService?
    
    /// Cache of cursor info queries
    private var cursorCache: [Location: CursorInfo] = [:]
    
    /// Cache hit/miss statistics
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    
    /// Whether SourceKit has been initialized
    private var isInitialized: Bool = false
    
    // MARK: - Initialization
    
    /// Initialize the SourceKit client
    /// - Parameters:
    ///   - projectRoot: Root of the Swift project
    ///   - compilerArguments: Additional compiler arguments (e.g., from Package.swift)
    public init(
        projectRoot: URL,
        compilerArguments: [String] = []
    ) {
        self.projectRoot = projectRoot
        self.compilerArguments = compilerArguments
    }
    
    /// Legacy initializer for compatibility
    /// - Parameters:
    ///   - sourceKitPath: Path to sourcekit (ignored, uses C API now)
    ///   - projectRoot: Root of the Swift project
    ///   - compilerArguments: Additional compiler arguments
    @available(*, deprecated, message: "sourceKitPath is no longer used; use init(projectRoot:compilerArguments:)")
    public init(
        sourceKitPath: String,
        projectRoot: URL,
        compilerArguments: [String] = []
    ) {
        self.projectRoot = projectRoot
        self.compilerArguments = compilerArguments
    }
    
    /// Create a SourceKitClient using auto-detected configuration
    public static func create(
        for projectRoot: URL,
        capabilities: SemanticCapabilities
    ) throws -> SourceKitClient? {
        // Check if SourceKit is available via C API
        guard capabilities.sourceKitAvailable else {
            return nil
        }
        
        // Build compiler arguments from Package.swift if available
        let args = buildCompilerArguments(for: projectRoot, capabilities: capabilities)
        
        return SourceKitClient(
            projectRoot: projectRoot,
            compilerArguments: args
        )
    }
    
    /// Initialize the SourceKit service (lazy initialization)
    private func ensureInitialized() async throws {
        guard !isInitialized else { return }
        
        let svc = SourceKitDService()
        try await svc.initialize()
        self.service = svc
        self.isInitialized = true
    }
    
    // MARK: - Queries
    
    /// Get type information for a location in a source file
    /// - Parameters:
    ///   - file: Path to the source file
    ///   - line: 1-indexed line number
    ///   - column: 1-indexed column number
    /// - Returns: CursorInfo if available
    public func cursorInfo(
        file: String,
        line: Int,
        column: Int
    ) async throws -> CursorInfo? {
        let location = Location(file: file, line: line, column: column)
        
        // Check cache first
        if let cached = cursorCache[location] {
            cacheHits += 1
            return cached
        }
        
        cacheMisses += 1
        
        // Ensure SourceKit is initialized
        try await ensureInitialized()
        
        // Run cursor info query via C API
        let result = try await runCursorInfoQuery(location: location)
        
        // Cache the result
        cursorCache[location] = result
        
        return result
    }
    
    /// Batch query for multiple locations (more efficient than individual queries)
    public func batchCursorInfo(
        locations: [Location]
    ) async throws -> [Location: CursorInfo] {
        var results: [Location: CursorInfo] = [:]
        
        // First check cache for all locations
        var uncachedLocations: [Location] = []
        for location in locations {
            if let cached = cursorCache[location] {
                results[location] = cached
                cacheHits += 1
            } else {
                uncachedLocations.append(location)
            }
        }
        
        // Ensure SourceKit is initialized
        try await ensureInitialized()
        
        // Query uncached locations
        // Group by file for potential batch optimization
        let locationsByFile = Dictionary(grouping: uncachedLocations) { $0.file }
        
        for (_, fileLocations) in locationsByFile {
            for location in fileLocations {
                cacheMisses += 1
                if let info = try await runCursorInfoQuery(location: location) {
                    results[location] = info
                    cursorCache[location] = info
                }
            }
        }
        
        return results
    }
    
    /// Clear the query cache
    public func clearCache() {
        cursorCache.removeAll()
        cacheHits = 0
        cacheMisses = 0
    }
    
    /// Get cache statistics
    public var cacheStatistics: (hits: Int, misses: Int, hitRate: Double) {
        let total = cacheHits + cacheMisses
        let rate = total > 0 ? Double(cacheHits) / Double(total) : 0.0
        return (cacheHits, cacheMisses, rate)
    }
    
    // MARK: - Private Query Implementation (C API)
    
    private func runCursorInfoQuery(location: Location) async throws -> CursorInfo? {
        guard let service = service else {
            throw SourceKitError.notAvailable("SourceKit service not initialized")
        }
        
        // Convert line/column to byte offset
        let offset = try await calculateOffset(file: location.file, line: location.line, column: location.column)
        
        // Build compiler arguments - source file MUST be first
        var args = [location.file]
        args.append(contentsOf: compilerArguments)
        
        if let sdkPath = getSDKPath() {
            args.append(contentsOf: ["-sdk", sdkPath])
        }
        
        // Add target triple (auto-detected from system)
        let target = Self.detectTargetTriple()
        args.append(contentsOf: ["-target", target])
        
        // Query via C API
        let result = try await service.cursorInfo(
            at: Int64(offset),
            in: location.file,
            sourceText: nil, // Let SourceKit read the file
            compilerArgs: args
        )
        
        // Convert to our CursorInfo type
        return convertToCursorInfo(result)
    }
    
    private func convertToCursorInfo(_ result: CursorInfoResult) -> CursorInfo? {
        // Only return if we got meaningful info
        guard result.hasData else { return nil }
        
        let kind: CursorInfo.SymbolKind? = result.kind.flatMap { CursorInfo.SymbolKind(rawValue: $0) }
        
        // Determine if internal
        let isInternal: Bool
        if let module = result.moduleName {
            isInternal = isProjectModule(module)
        } else {
            isInternal = !result.isSystem
        }
        
        return CursorInfo(
            typeName: result.typeName,
            usr: result.usr,
            kind: kind,
            isInternal: isInternal,
            moduleName: result.moduleName,
            declaration: result.annotatedDecl,
            documentation: result.docFullAsXML
        )
    }
    
    private func calculateOffset(file: String, line: Int, column: Int) async throws -> Int {
        let content = try String(contentsOfFile: file, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var offset = 0
        for i in 0..<(line - 1) {
            if i < lines.count {
                offset += lines[i].utf8.count + 1 // +1 for newline
            }
        }
        offset += column - 1
        
        return offset
    }
    
    private func isProjectModule(_ moduleName: String) -> Bool {
        // Check if module is part of this project
        // This is a heuristic - could be improved with build system info
        
        // Check Package.swift for target names
        let packagePath = projectRoot.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packagePath.path) {
            if let content = try? String(contentsOf: packagePath, encoding: .utf8) {
                // Simple check - look for target name in Package.swift
                return content.contains("\"\(moduleName)\"")
            }
        }
        
        // Check if there's a source directory with this name
        let sourcesPath = projectRoot.appendingPathComponent("Sources/\(moduleName)")
        if FileManager.default.fileExists(atPath: sourcesPath.path) {
            return true
        }
        
        return false
    }
    
    private func getSDKPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    
    /// Detect the target triple from the current system
    /// Returns format like "arm64-apple-macosx14.0" or "x86_64-apple-macosx14.0"
    private static func detectTargetTriple() -> String {
        // Try to get from swift -print-target-info first (most accurate)
        if let targetFromSwift = getTargetFromSwift() {
            return targetFromSwift
        }
        
        // Fall back to compile-time detection
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "arm64" // Default
        #endif
        
        #if os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(arch)-apple-macosx\(version.majorVersion).\(version.minorVersion)"
        #elseif os(iOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(arch)-apple-ios\(version.majorVersion).\(version.minorVersion)"
        #elseif os(Linux)
        return "\(arch)-unknown-linux-gnu"
        #else
        return "\(arch)-apple-macosx14.0"
        #endif
    }
    
    private static func getTargetFromSwift() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swift", "-print-target-info"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else { return nil }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8),
                  let jsonData = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let target = json["target"] as? [String: Any],
                  let triple = target["unversionedTriple"] as? String else {
                return nil
            }
            
            // Get versioned triple if available
            if let versionedTriple = target["triple"] as? String {
                return versionedTriple
            }
            
            return triple
        } catch {
            return nil
        }
    }
    
    private static func buildCompilerArguments(
        for projectRoot: URL,
        capabilities: SemanticCapabilities
    ) -> [String] {
        var args: [String] = []
        
        // If this is a Swift package, we can derive arguments
        if capabilities.isSwiftPackage {
            // Add the build directory for module maps
            let buildDir = projectRoot.appendingPathComponent(".build")
            if FileManager.default.fileExists(atPath: buildDir.path) {
                args.append("-I")
                args.append(buildDir.path)
            }
        }
        
        return args
    }
}

// MARK: - Convenience Extensions

extension SourceKitClient.CursorInfo {
    /// Whether this is a type declaration (class, struct, enum, protocol)
    public var isTypeDeclaration: Bool {
        switch kind {
        case .class, .struct, .enum, .protocol:
            return true
        default:
            return false
        }
    }
    
    /// Whether this is a function or method
    public var isCallable: Bool {
        switch kind {
        case .function, .method, .staticMethod, .classMethod, .initializer:
            return true
        default:
            return false
        }
    }
    
    /// Whether this is a property or variable
    public var isVariable: Bool {
        switch kind {
        case .property, .staticProperty, .classProperty, .globalVariable, .localVariable, .parameter:
            return true
        default:
            return false
        }
    }
}
