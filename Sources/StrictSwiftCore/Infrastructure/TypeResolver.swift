import Foundation
import SwiftSyntax

/// Resolves types from source files and maintains a type registry
/// SAFETY: @unchecked Sendable is safe because all mutable state (typeRegistry)
/// is protected by NSLock for thread-safe access.
public final class TypeResolver: @unchecked Sendable {
    private var typeRegistry: [String: ResolvedType] = [:]
    private let lock = NSLock()

    public init() {}

    // MARK: - Public API

    /// Resolve types from source files
    public func resolveTypes(from files: [SourceFile]) {
        lock.lock()
        defer { lock.unlock() }

        typeRegistry.removeAll()

        for file in files {
            resolveTypesFromFile(file)
        }
        
        // Categorize inherited types as superclasses vs protocol conformances
        resolveInheritanceAndConformances()
        
        // Build full inheritance chains (transitive)
        resolveTransitiveInheritance()
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

    /// Check if two types are compatible (type1 can be used where type2 is expected)
    public func areTypesCompatible(_ type1: String, _ type2: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let resolvedType1 = typeRegistry[type1],
              let resolvedType2 = typeRegistry[type2] else {
            return false
        }

        // Types are compatible if they are the same
        if type1 == type2 { return true }

        // type1 inherits from type2
        if resolvedType1.inheritanceChain.contains(type2) {
            return true
        }
        
        // type2 is a protocol and type1 conforms to it
        if resolvedType2.kind == .protocol {
            if resolvedType1.conformances.contains(type2) {
                return true
            }
            
            // Check inherited conformance
            for parentTypeName in resolvedType1.inheritanceChain {
                if let parentType = typeRegistry[parentTypeName] {
                    if parentType.conformances.contains(type2) {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Analyze complexity of a type
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

    // MARK: - Inheritance Resolution

    /// Resolve inherited types into proper superclasses and protocol conformances
    private func resolveInheritanceAndConformances() {
        for (typeName, type) in typeRegistry {
            guard type.kind == .class else { continue }
            
            var inheritanceChain: [String] = []
            var conformances: [String] = []
            
            for inheritedType in type.conformances {
                if let resolvedInherited = typeRegistry[inheritedType] {
                    if resolvedInherited.kind == .class {
                        inheritanceChain.append(inheritedType)
                    } else {
                        conformances.append(inheritedType)
                    }
                } else {
                    // Use heuristics for unknown types
                    let commonProtocols = ["Codable", "Encodable", "Decodable", "Hashable", "Equatable", 
                                          "Identifiable", "Sendable", "Comparable", "CustomStringConvertible",
                                          "CustomDebugStringConvertible", "CaseIterable", "Error", "Collection",
                                          "Sequence", "RandomAccessCollection", "BidirectionalCollection"]
                    
                    if commonProtocols.contains(inheritedType) ||
                       inheritedType.hasSuffix("Protocol") ||
                       inheritedType.hasSuffix("Delegate") ||
                       inheritedType.hasSuffix("able") ||
                       inheritedType.hasSuffix("ible") {
                        conformances.append(inheritedType)
                    } else if inheritanceChain.isEmpty {
                        inheritanceChain.append(inheritedType)
                    } else {
                        conformances.append(inheritedType)
                    }
                }
            }
            
            var updatedType = type
            updatedType.inheritanceChain = inheritanceChain
            updatedType.conformances = conformances
            typeRegistry[typeName] = updatedType
        }
    }
    
    /// Resolve transitive inheritance chains
    private func resolveTransitiveInheritance() {
        var changed = true
        var iterations = 0
        let maxIterations = 100
        
        while changed && iterations < maxIterations {
            changed = false
            iterations += 1
            
            for (typeName, type) in typeRegistry {
                let currentChain = type.inheritanceChain
                var addedTypes = Set<String>()
                
                for parentTypeName in currentChain {
                    if let parentType = typeRegistry[parentTypeName] {
                        for grandparent in parentType.inheritanceChain {
                            if !currentChain.contains(grandparent) && !addedTypes.contains(grandparent) {
                                addedTypes.insert(grandparent)
                            }
                        }
                    }
                }
                
                if !addedTypes.isEmpty {
                    var updatedType = type
                    updatedType.inheritanceChain.append(contentsOf: addedTypes)
                    typeRegistry[typeName] = updatedType
                    changed = true
                }
            }
        }
    }

    // MARK: - File Parsing

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

            if trimmedLine.isEmpty || trimmedLine.hasPrefix("//") || trimmedLine.hasPrefix("/*") {
                continue
            }

            if let typeDeclaration = parseTypeDeclaration(line, module: module, filePath: filePath) {
                if inTypeDeclaration, let type = currentType {
                    typeRegistry[type.name] = type
                }

                currentType = typeDeclaration
                braceCount = line.components(separatedBy: "{").count - line.components(separatedBy: "}").count
                inTypeDeclaration = true
            } else if inTypeDeclaration {
                braceCount += line.components(separatedBy: "{").count - line.components(separatedBy: "}").count

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

        if let type = currentType {
            typeRegistry[type.name] = type
        }
    }

    private func extractModuleName(from sourceFile: SourceFile) -> String {
        let source = sourceFile.source()

        if let moduleMatch = source.range(of: "module ", options: .caseInsensitive) {
            let afterModule = source[moduleMatch.upperBound...]
            if let nameEnd = afterModule.range(of: " ") {
                return String(afterModule[..<nameEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return sourceFile.url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Type Declaration Parsing

    private func parseTypeDeclaration(_ line: String, module: String, filePath: String) -> ResolvedType? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedLine.contains("class ") && !trimmedLine.contains("//") {
            return parseTypeWithPattern(trimmedLine, pattern: "(public|open|internal|fileprivate|private)?\\s*class\\s+([A-Za-z][A-Za-z0-9_]*)", kind: .class, module: module, filePath: filePath)
        }

        if trimmedLine.contains("struct ") && !trimmedLine.contains("//") {
            return parseTypeWithPattern(trimmedLine, pattern: "(public|internal|fileprivate|private)?\\s*struct\\s+([A-Za-z][A-Za-z0-9_]*)", kind: .struct, module: module, filePath: filePath)
        }

        if trimmedLine.contains("protocol ") && !trimmedLine.contains("//") {
            return parseTypeWithPattern(trimmedLine, pattern: "(public|open|internal|fileprivate|private)?\\s*protocol\\s+([A-Za-z][A-Za-z0-9_]*)", kind: .protocol, module: module, filePath: filePath)
        }

        if trimmedLine.contains("enum ") && !trimmedLine.contains("//") {
            return parseTypeWithPattern(trimmedLine, pattern: "(public|internal|fileprivate|private)?\\s*enum\\s+([A-Za-z][A-Za-z0-9_]*)", kind: .enum, module: module, filePath: filePath)
        }

        if trimmedLine.contains("actor ") && !trimmedLine.contains("//") {
            return parseTypeWithPattern(trimmedLine, pattern: "(public|internal|fileprivate|private)?\\s*actor\\s+([A-Za-z][A-Za-z0-9_]*)", kind: .actor, module: module, filePath: filePath)
        }

        return nil
    }

    private func parseTypeWithPattern(_ line: String, pattern: String, kind: TypeKind, module: String, filePath: String) -> ResolvedType? {
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
            accessLevel = AccessLevel(rawValue: String(line[accessStart..<accessEnd])) ?? .internal
        } else {
            accessLevel = .internal
        }

        guard nameRange.location != NSNotFound else { return nil }
        let nameStart = line.index(line.startIndex, offsetBy: nameRange.location)
        let nameEnd = line.index(nameStart, offsetBy: nameRange.length)
        let name = String(line[nameStart..<nameEnd])

        // Parse inheritance
        var inheritedTypes: [String] = []
        if let colonIndex = line.range(of: ":") {
            let afterColon = line[colonIndex.upperBound...]
            let inheritancePart: String
            if let braceIndex = afterColon.firstIndex(of: "{") {
                inheritancePart = String(afterColon[..<braceIndex])
            } else if let whereIndex = afterColon.range(of: " where ") {
                inheritancePart = String(afterColon[..<whereIndex.lowerBound])
            } else {
                inheritancePart = String(afterColon)
            }
            
            inheritedTypes = inheritancePart
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.contains("<") && !$0.contains(">") }
        }

        var resolvedType = ResolvedType(
            name: name,
            kind: kind,
            module: module,
            isPublic: accessLevel == .public || accessLevel == .open,
            filePath: filePath
        )
        resolvedType.conformances = inheritedTypes
        
        return resolvedType
    }

    // MARK: - Property Parsing

    private func parseProperty(_ line: String) -> Property? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedLine.contains("let ") && !trimmedLine.contains("var ") {
            return nil
        }
        
        if trimmedLine.contains("func ") {
            return nil
        }
        
        // Skip computed properties
        if trimmedLine.contains("var ") && trimmedLine.range(of: ":\\s*[A-Za-z][A-Za-z0-9_?!<>\\[\\]:, ]*\\s*\\{", options: .regularExpression) != nil {
            return nil
        }

        let pattern = "(public|private|fileprivate|internal)?\\s*(static)?\\s*(var|let)\\s+([A-Za-z][A-Za-z0-9_]*)\\s*:\\s*([^=\\{\\n]+)"
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
            accessLevel = AccessLevel(rawValue: String(trimmedLine[accessStart..<accessEnd])) ?? .internal
        } else {
            accessLevel = .internal
        }

        let isStatic = staticRange.location != NSNotFound
        
        let varLetStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: varLetRange.location)
        let varLetEnd = trimmedLine.index(varLetStart, offsetBy: varLetRange.length)
        let isMutable = String(trimmedLine[varLetStart..<varLetEnd]) == "var"

        let nameStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: nameRange.location)
        let nameEnd = trimmedLine.index(nameStart, offsetBy: nameRange.length)
        let name = String(trimmedLine[nameStart..<nameEnd])

        let typeStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: typeRange.location)
        let typeEnd = trimmedLine.index(typeStart, offsetBy: typeRange.length)
        let type = String(trimmedLine[typeStart..<typeEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        return Property(
            name: name,
            type: type,
            isMutable: isMutable,
            isOptional: type.contains("?"),
            isStatic: isStatic,
            accessLevel: accessLevel
        )
    }

    // MARK: - Method Parsing

    private func parseMethod(_ line: String) -> Method? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for computed property first
        if let computedMethod = parseComputedPropertyAsMethod(trimmedLine) {
            return computedMethod
        }

        if !trimmedLine.contains("func ") {
            return nil
        }

        let pattern = "(public|private|fileprivate|internal|open)?\\s*(static)?\\s*func\\s+([A-Za-z][A-Za-z0-9_]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmedLine, range: NSRange(location: 0, length: trimmedLine.utf16.count)) else {
            return nil
        }

        let accessLevelRange = match.range(at: 1)
        let staticRange = match.range(at: 2)
        let nameRange = match.range(at: 3)

        guard nameRange.location != NSNotFound else { return nil }

        let nameStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: nameRange.location)
        let nameEnd = trimmedLine.index(nameStart, offsetBy: nameRange.length)
        let name = String(trimmedLine[nameStart..<nameEnd])

        let accessLevel: AccessLevel
        if accessLevelRange.location != NSNotFound {
            let accessStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: accessLevelRange.location)
            let accessEnd = trimmedLine.index(accessStart, offsetBy: accessLevelRange.length)
            accessLevel = AccessLevel(rawValue: String(trimmedLine[accessStart..<accessEnd])) ?? .internal
        } else {
            accessLevel = .internal
        }
        
        let isStatic = staticRange.location != NSNotFound
        let isAsync = trimmedLine.contains(") async") || (trimmedLine.contains("async ") && trimmedLine.contains("func "))
        let throwsError = trimmedLine.contains("throws") || trimmedLine.contains("rethrows")

        var returnType = "Void"
        if let arrowRange = trimmedLine.range(of: "->") {
            let afterArrow = trimmedLine[arrowRange.upperBound...]
            if let braceIndex = afterArrow.firstIndex(of: "{") {
                returnType = String(afterArrow[..<braceIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                returnType = String(afterArrow).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return Method(
            name: name,
            returnType: returnType,
            isStatic: isStatic,
            isAsync: isAsync,
            throwsError: throwsError,
            accessLevel: accessLevel
        )
    }

    private func parseComputedPropertyAsMethod(_ line: String) -> Method? {
        guard line.contains("var ") && line.contains("{") && !line.contains("func ") else {
            return nil
        }
        
        let pattern = "(public|private|fileprivate|internal|open)?\\s*(static)?\\s*var\\s+([A-Za-z][A-Za-z0-9_]*)\\s*:\\s*([A-Za-z][A-Za-z0-9_?!<>\\[\\]]+)\\s*\\{"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) else {
            return nil
        }
        
        let accessLevelRange = match.range(at: 1)
        let staticRange = match.range(at: 2)
        let nameRange = match.range(at: 3)
        let typeRange = match.range(at: 4)
        
        guard nameRange.location != NSNotFound else { return nil }
        
        let nameStart = line.index(line.startIndex, offsetBy: nameRange.location)
        let nameEnd = line.index(nameStart, offsetBy: nameRange.length)
        let name = String(line[nameStart..<nameEnd])
        
        let accessLevel: AccessLevel
        if accessLevelRange.location != NSNotFound {
            let accessStart = line.index(line.startIndex, offsetBy: accessLevelRange.location)
            let accessEnd = line.index(accessStart, offsetBy: accessLevelRange.length)
            accessLevel = AccessLevel(rawValue: String(line[accessStart..<accessEnd])) ?? .internal
        } else {
            accessLevel = .internal
        }
        
        let isStatic = staticRange.location != NSNotFound
        
        let returnType: String
        if typeRange.location != NSNotFound {
            let typeStart = line.index(line.startIndex, offsetBy: typeRange.location)
            let typeEnd = line.index(typeStart, offsetBy: typeRange.length)
            returnType = String(line[typeStart..<typeEnd])
        } else {
            returnType = "Void"
        }
        
        return Method(
            name: name,
            returnType: returnType,
            isStatic: isStatic,
            isAsync: false,
            throwsError: false,
            accessLevel: accessLevel
        )
    }

    // MARK: - Inheritance Parsing

    private func parseInheritance(_ line: String) -> [String]? {
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
        return parseInheritance(line)
    }
}
