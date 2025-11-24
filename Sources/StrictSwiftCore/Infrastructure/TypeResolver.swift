import Foundation
import SwiftSyntax

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

/// Resolves types from source files and maintains a type registry
public final class TypeResolver: @unchecked Sendable {
    private var typeRegistry: [String: ResolvedType] = [:]
    private let lock = NSLock()

    public init() {}

    /// Resolve types from source files
    public func resolveTypes(from files: [SourceFile]) {
        lock.lock()
        defer { lock.unlock() }

        typeRegistry.removeAll()

        for file in files {
            resolveTypesFromFile(file)
        }
    }

    /// Get all resolved types
    public var allTypes: [ResolvedType] {
        lock.lock()
        defer { lock.unlock() }
        return Array(typeRegistry.values)
    }

    /// Get a specific type by name
    public func type(named name: String) -> ResolvedType? {
        lock.lock()
        defer { lock.unlock() }
        return typeRegistry[name]
    }

    /// Get types that conform to a specific protocol
    public func typesConforming(to protocolName: String) -> [ResolvedType] {
        lock.lock()
        defer { lock.unlock() }

        return typeRegistry.values.filter { type in
            type.conformances.contains(protocolName)
        }
    }

    /// Get types that inherit from a specific class
    public func typesInheriting(from className: String) -> [ResolvedType] {
        lock.lock()
        defer { lock.unlock() }

        return typeRegistry.values.filter { type in
            type.inheritanceChain.contains(className)
        }
    }

    /// Check if two types are compatible (can be used together)
    public func areTypesCompatible(_ type1: String, _ type2: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let resolvedType1 = typeRegistry[type1],
              let resolvedType2 = typeRegistry[type2] else {
            return false
        }

        // Types are compatible if:
        // 1. They are the same type
        if type1 == type2 { return true }

        // 2. One inherits from the other
        if resolvedType1.inheritanceChain.contains(type2) ||
           resolvedType2.inheritanceChain.contains(type1) {
            return true
        }

        // 3. They conform to the same protocol
        let commonConformances = Set(resolvedType1.conformances).intersection(Set(resolvedType2.conformances))
        if !commonConformances.isEmpty { return true }

        return false
    }

    /// Analyze complexity of a type (number of properties, methods, etc.)
    public func complexity(of typeName: String) -> TypeComplexity? {
        lock.lock()
        defer { lock.unlock() }

        guard let type = typeRegistry[typeName] else { return nil }

        return TypeComplexity(
            propertyCount: type.properties.count,
            methodCount: type.methods.count,
            inheritanceDepth: type.inheritanceChain.count,
            protocolCount: type.conformances.count,
            publicMembersCount: type.properties.filter { $0.accessLevel == .public || $0.accessLevel == .open }.count +
                              type.methods.filter { $0.accessLevel == .public || $0.accessLevel == .open }.count
        )
    }

    // MARK: - Private Methods

    private func resolveTypesFromFile(_ sourceFile: SourceFile) {
        let source = sourceFile.source()
        let lines = source.components(separatedBy: .newlines)
        let module = extractModuleName(from: sourceFile)
        let filePath = sourceFile.url.path

        var currentType: ResolvedType?
        var braceCount = 0
        var inTypeDeclaration = false

        for (_, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip comments and empty lines
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("//") || trimmedLine.hasPrefix("/*") {
                continue
            }

            // Check for type declarations
            if let typeDeclaration = parseTypeDeclaration(line, module: module, filePath: filePath) {
                if inTypeDeclaration {
                    // Save previous type
                    if let type = currentType {
                        typeRegistry[type.name] = type
                    }
                }

                currentType = typeDeclaration
                braceCount = line.components(separatedBy: "{").count - line.components(separatedBy: "}").count
                inTypeDeclaration = true
            } else if inTypeDeclaration {
                // Update brace count
                braceCount += line.components(separatedBy: "{").count - line.components(separatedBy: "}").count

                // Parse properties and methods
                if var type = currentType {
                    if let property = parseProperty(line) {
                        type.properties.append(property)
                        currentType = type
                    } else if let method = parseMethod(line) {
                        type.methods.append(method)
                        currentType = type
                    } else if let inheritance = parseInheritance(line) {
                        type.inheritanceChain.append(contentsOf: inheritance)
                        currentType = type
                    } else if let conformance = parseProtocolConformance(line) {
                        type.conformances.append(contentsOf: conformance)
                        currentType = type
                    }
                }

                // Check if we've exited the type declaration
                if braceCount <= 0 {
                    if let type = currentType {
                        typeRegistry[type.name] = type
                    }
                    currentType = nil
                    inTypeDeclaration = false
                    braceCount = 0
                }
            }
        }

        // Save any remaining type
        if let type = currentType {
            typeRegistry[type.name] = type
        }
    }

    private func extractModuleName(from sourceFile: SourceFile) -> String {
        // Try to extract module name from imports or file structure
        let source = sourceFile.source()

        // Look for module declaration (if this is a main file)
        if let moduleMatch = source.range(of: "module ", options: .caseInsensitive) {
            let afterModule = source[moduleMatch.upperBound...]
            if let nameEnd = afterModule.range(of: " ") {
                let moduleName = String(afterModule[..<nameEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return moduleName
            }
        }

        // Fallback: use directory name or file name
        return sourceFile.url.deletingPathExtension().lastPathComponent
    }

    private func parseTypeDeclaration(_ line: String, module: String, filePath: String) -> ResolvedType? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse class declaration
        if trimmedLine.hasPrefix("class ") {
            return parseClassDeclaration(trimmedLine, module: module, filePath: filePath)
        }

        // Parse struct declaration
        if trimmedLine.hasPrefix("struct ") {
            return parseStructDeclaration(trimmedLine, module: module, filePath: filePath)
        }

        // Parse protocol declaration
        if trimmedLine.hasPrefix("protocol ") {
            return parseProtocolDeclaration(trimmedLine, module: module, filePath: filePath)
        }

        // Parse enum declaration
        if trimmedLine.hasPrefix("enum ") {
            return parseEnumDeclaration(trimmedLine, module: module, filePath: filePath)
        }

        return nil
    }

    private func parseClassDeclaration(_ line: String, module: String, filePath: String) -> ResolvedType? {
        let pattern = "(public|open|internal|fileprivate|private)?\\s*class\\s+([A-Za-z][A-Za-z0-9_]*)"
        return parseTypeDeclarationWithPattern(line, pattern: pattern, kind: .class, module: module, filePath: filePath)
    }

    private func parseStructDeclaration(_ line: String, module: String, filePath: String) -> ResolvedType? {
        let pattern = "(public|internal|fileprivate|private)?\\s*struct\\s+([A-Za-z][A-Za-z0-9_]*)"
        return parseTypeDeclarationWithPattern(line, pattern: pattern, kind: .struct, module: module, filePath: filePath)
    }

    private func parseProtocolDeclaration(_ line: String, module: String, filePath: String) -> ResolvedType? {
        let pattern = "(public|open|internal|fileprivate|private)?\\s*protocol\\s+([A-Za-z][A-Za-z0-9_]*)"
        return parseTypeDeclarationWithPattern(line, pattern: pattern, kind: .protocol, module: module, filePath: filePath)
    }

    private func parseEnumDeclaration(_ line: String, module: String, filePath: String) -> ResolvedType? {
        let pattern = "(public|internal|fileprivate|private)?\\s*enum\\s+([A-Za-z][A-Za-z0-9_]*)"
        return parseTypeDeclarationWithPattern(line, pattern: pattern, kind: .enum, module: module, filePath: filePath)
    }

    private func parseTypeDeclarationWithPattern(_ line: String, pattern: String, kind: TypeKind, module: String, filePath: String) -> ResolvedType? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) else {
            return nil
        }

        let accessLevelRange = match.range(at: 1)
        let nameRange = match.range(at: 2)

        let accessLevel: AccessLevel
        if accessLevelRange.location != NSNotFound {
            let accessStart = line.index(line.startIndex, offsetBy: accessLevelRange.location)
            let accessEnd = line.index(accessStart, offsetBy: accessLevelRange.length)
            let accessString = String(line[accessStart..<accessEnd])
            accessLevel = AccessLevel(rawValue: accessString) ?? .internal
        } else {
            accessLevel = .internal
        }

        guard nameRange.location != NSNotFound else { return nil }
        let nameStart = line.index(line.startIndex, offsetBy: nameRange.location)
        let nameEnd = line.index(nameStart, offsetBy: nameRange.length)
        let name = String(line[nameStart..<nameEnd])

        let isPublic = accessLevel == .public || accessLevel == .open

        return ResolvedType(
            name: name,
            kind: kind,
            module: module,
            isPublic: isPublic,
            filePath: filePath
        )
    }

    private func parseProperty(_ line: String) -> Property? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip if not a property line
        if !(trimmedLine.hasPrefix("let ") || trimmedLine.hasPrefix("var ")) {
            return nil
        }

        let pattern = "(public|private|fileprivate|internal)?\\s*(static)?\\s*(var|let)\\s+([A-Za-z][A-Za-z0-9_]*)\\s*:\\s*([^=\\n]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmedLine, range: NSRange(location: 0, length: trimmedLine.utf16.count)) else {
            return nil
        }

        let accessLevelRange = match.range(at: 1)
        let staticRange = match.range(at: 2)
        let varLetRange = match.range(at: 3)
        let nameRange = match.range(at: 4)
        let typeRange = match.range(at: 5)

        guard varLetRange.location != NSNotFound && nameRange.location != NSNotFound && typeRange.location != NSNotFound else {
            return nil
        }

        let accessLevel: AccessLevel
        if accessLevelRange.location != NSNotFound {
            let accessStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: accessLevelRange.location)
            let accessEnd = trimmedLine.index(accessStart, offsetBy: accessLevelRange.length)
            let accessString = String(trimmedLine[accessStart..<accessEnd])
            accessLevel = AccessLevel(rawValue: accessString) ?? .internal
        } else {
            accessLevel = .internal
        }

        let isStatic = staticRange.location != NSNotFound
        let varLetNSRange = match.range(at: 3) // varLetRange is the parameter name, not the index
        let varLetStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: varLetNSRange.location)
        let varLetEnd = trimmedLine.index(varLetStart, offsetBy: varLetNSRange.length)
        let isMutable = String(trimmedLine[varLetStart..<varLetEnd]) == "var"

        let nameStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: nameRange.location)
        let nameEnd = trimmedLine.index(nameStart, offsetBy: nameRange.length)
        let name = String(trimmedLine[nameStart..<nameEnd])

        let typeStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: typeRange.location)
        let typeEnd = trimmedLine.index(typeStart, offsetBy: typeRange.length)
        let type = String(trimmedLine[typeStart..<typeEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        let isOptional = type.contains("?")

        return Property(
            name: name,
            type: type,
            isMutable: isMutable,
            isOptional: isOptional,
            isStatic: isStatic,
            accessLevel: accessLevel
        )
    }

    private func parseMethod(_ line: String) -> Method? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Basic method pattern (simplified)
        let pattern = "(public|private|fileprivate|internal|open)?\\s*(static)?\\s*func\\s+([A-Za-z][A-Za-z0-9_]*)\\s*\\([^)]*\\)(\\s*->\\s*([^\\n]+))?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmedLine, range: NSRange(location: 0, length: trimmedLine.utf16.count)) else {
            return nil
        }

        let nameRange = match.range(at: 3)
        let returnTypeRange = match.range(at: 5)

        guard nameRange.location != NSNotFound else { return nil }

        let nameStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: nameRange.location)
        let nameEnd = trimmedLine.index(nameStart, offsetBy: nameRange.length)
        let name = String(trimmedLine[nameStart..<nameEnd])

        let returnType: String
        if returnTypeRange.location != NSNotFound {
            let returnStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: returnTypeRange.location)
            let returnEnd = trimmedLine.index(returnStart, offsetBy: returnTypeRange.length)
            returnType = String(trimmedLine[returnStart..<returnEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            returnType = "Void"
        }

        return Method(name: name, returnType: returnType)
    }

    private func parseInheritance(_ line: String) -> [String]? {
        // Simple inheritance parsing
        let pattern = ":\\s*([A-Za-z][A-Za-z0-9_,\\s]*)\\s*\\{"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) else {
            return nil
        }

        let range = match.range(at: 1)
        guard range.location != NSNotFound else { return nil }

        let start = line.index(line.startIndex, offsetBy: range.location)
        let end = line.index(start, offsetBy: range.length)
        let inheritanceString = String(line[start..<end])

        return inheritanceString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func parseProtocolConformance(_ line: String) -> [String]? {
        // Similar to inheritance but for protocols
        return parseInheritance(line)
    }
}

/// Represents the complexity metrics of a type
public struct TypeComplexity: Sendable {
    public let propertyCount: Int
    public let methodCount: Int
    public let inheritanceDepth: Int
    public let protocolCount: Int
    public let publicMembersCount: Int

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