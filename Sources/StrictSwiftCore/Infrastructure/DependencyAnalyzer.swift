import Foundation
import SwiftSyntax

/// Analyzes source files to build dependency graphs
public final class DependencyAnalyzer: @unchecked Sendable {
    private let dependencyGraph: DependencyGraph

    public init() {
        self.dependencyGraph = DependencyGraph()
    }

    /// Analyze multiple source files and build a dependency graph
    public func analyze(files: [SourceFile]) -> DependencyGraph {
        dependencyGraph.clear()

        // First pass: add all nodes
        for file in files {
            addNodesFromFile(file)
        }

        // Second pass: analyze dependencies between nodes
        for file in files {
            analyzeDependenciesInFile(file)
        }

        return dependencyGraph
    }

    /// Get the current dependency graph
    public var graph: DependencyGraph {
        return dependencyGraph
    }

    // MARK: - Private Methods

    private func addNodesFromFile(_ sourceFile: SourceFile) {
        let source = sourceFile.source()
        let lines = source.components(separatedBy: .newlines)
        let fileName = sourceFile.url.lastPathComponent

        // Add file node
        let fileNode = DependencyNode(
            name: fileName,
            type: .file,
            filePath: sourceFile.url.path
        )
        dependencyGraph.addNode(fileNode)

        // Extract and add type nodes
        for (_, line) in lines.enumerated() {
            extractNodesFromLine(line, filePath: sourceFile.url.path)
        }
    }

    private func extractNodesFromLine(_ line: String, filePath: String) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip comments and empty lines
        if trimmedLine.isEmpty || trimmedLine.hasPrefix("//") {
            return
        }

        // Extract imports
        if trimmedLine.hasPrefix("import ") {
            let moduleName = trimmedLine.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
            let moduleNode = DependencyNode(
                name: moduleName,
                type: .module,
                filePath: filePath
            )
            dependencyGraph.addNode(moduleNode)
        }

        // Extract class declarations
        if trimmedLine.contains("class ") {
            extractTypeDeclaration(
                line: trimmedLine,
                prefix: "class",
                type: .class,
                filePath: filePath
            )
        }

        // Extract struct declarations
        if trimmedLine.contains("struct ") {
            extractTypeDeclaration(
                line: trimmedLine,
                prefix: "struct",
                type: .struct,
                filePath: filePath
            )
        }

        // Extract protocol declarations
        if trimmedLine.contains("protocol ") {
            extractTypeDeclaration(
                line: trimmedLine,
                prefix: "protocol",
                type: .protocol,
                filePath: filePath
            )
        }

        // Extract enum declarations
        if trimmedLine.contains("enum ") {
            extractTypeDeclaration(
                line: trimmedLine,
                prefix: "enum",
                type: .enum,
                filePath: filePath
            )
        }

        // Extract function declarations
        if trimmedLine.hasPrefix("func ") {
            extractFunctionDeclaration(line: trimmedLine, filePath: filePath)
        }

        // Extract extensions
        if trimmedLine.hasPrefix("extension ") {
            extractExtensionDeclaration(line: trimmedLine, filePath: filePath)
        }
    }

    private func extractTypeDeclaration(line: String, prefix: String, type: NodeType, filePath: String) {
        let pattern = "\(prefix)\\s+([A-Za-z][A-Za-z0-9_]*)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            let nameRange = match.range(at: 1)
            if nameRange.location != NSNotFound {
                let start = line.index(line.startIndex, offsetBy: nameRange.location)
                let end = line.index(start, offsetBy: nameRange.length)
                let typeName = String(line[start..<end])

                let node = DependencyNode(
                    name: typeName,
                    type: type,
                    filePath: filePath
                )
                dependencyGraph.addNode(node)
            }
        }
    }

    private func extractFunctionDeclaration(line: String, filePath: String) {
        let pattern = "func\\s+([A-Za-z][A-Za-z0-9_]*)\\s*\\("
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            let nameRange = match.range(at: 1)
            if nameRange.location != NSNotFound {
                let start = line.index(line.startIndex, offsetBy: nameRange.location)
                let end = line.index(start, offsetBy: nameRange.length)
                let functionName = String(line[start..<end])

                let node = DependencyNode(
                    name: functionName,
                    type: .function,
                    filePath: filePath
                )
                dependencyGraph.addNode(node)
            }
        }
    }

    private func extractExtensionDeclaration(line: String, filePath: String) {
        let pattern = "extension\\s+([A-Za-z][A-Za-z0-9_]*)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            let nameRange = match.range(at: 1)
            if nameRange.location != NSNotFound {
                let start = line.index(line.startIndex, offsetBy: nameRange.location)
                let end = line.index(start, offsetBy: nameRange.length)
                let extensionName = String(line[start..<end])

                let node = DependencyNode(
                    name: "\(extensionName)(extension)",
                    type: .extension,
                    filePath: filePath
                )
                dependencyGraph.addNode(node)
            }
        }
    }

    private func analyzeDependenciesInFile(_ sourceFile: SourceFile) {
        let source = sourceFile.source()
        let lines = source.components(separatedBy: .newlines)
        let fileName = sourceFile.url.lastPathComponent

        for (_, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip comments and empty lines
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("//") {
                continue
            }

            // Analyze import dependencies
            if trimmedLine.hasPrefix("import ") {
                let moduleName = trimmedLine.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
                let dependency = Dependency(
                    from: fileName,
                    to: moduleName,
                    type: .importModule,
                    strength: .strong
                )
                dependencyGraph.addDependency(dependency)
            }

            // Analyze inheritance and conformance
            analyzeInheritanceDependencies(line: trimmedLine, sourceFile: fileName)

            // Analyze composition and usage dependencies
            analyzeUsageDependencies(line: trimmedLine, sourceFile: fileName)

            // Analyze function call dependencies
            analyzeFunctionCallDependencies(line: trimmedLine, sourceFile: fileName)
        }
    }

    private func analyzeInheritanceDependencies(line: String, sourceFile: String) {
        // Class inheritance
        let inheritancePattern = "class\\s+([A-Za-z][A-Za-z0-9_]*)\\s*:\\s*([A-Za-z][A-Za-z0-9_,\\s]*)\\{"
        if let regex = try? NSRegularExpression(pattern: inheritancePattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            let classNameRange = match.range(at: 1)
            let parentsRange = match.range(at: 2)
            if classNameRange.location != NSNotFound && parentsRange.location != NSNotFound {

                let classStart = line.index(line.startIndex, offsetBy: classNameRange.location)
                let classEnd = line.index(classStart, offsetBy: classNameRange.length)
                let className = String(line[classStart..<classEnd])

                let parentsStart = line.index(line.startIndex, offsetBy: parentsRange.location)
                let parentsEnd = line.index(parentsStart, offsetBy: parentsRange.length)
                let parents = String(line[parentsStart..<parentsEnd])

                let parentTypes = parents.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                for parent in parentTypes {
                    if !parent.isEmpty {
                        let dependency = Dependency(
                            from: className,
                            to: parent,
                            type: .classInheritance,
                            strength: .strong
                        )
                        dependencyGraph.addDependency(dependency)
                    }
                }
            }
        }

        // Protocol conformance
        let conformancePattern = "extension\\s+([A-Za-z][A-Za-z0-9_]*)\\s*:\\s*([A-Za-z][A-Za-z0-9_,\\s]*)\\{"
        if let regex = try? NSRegularExpression(pattern: conformancePattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            let typeNameRange = match.range(at: 1)
            let protocolsRange = match.range(at: 2)
            if typeNameRange.location != NSNotFound && protocolsRange.location != NSNotFound {

                let typeStart = line.index(line.startIndex, offsetBy: typeNameRange.location)
                let typeEnd = line.index(typeStart, offsetBy: typeNameRange.length)
                let typeName = String(line[typeStart..<typeEnd])

                let protocolsStart = line.index(line.startIndex, offsetBy: protocolsRange.location)
                let protocolsEnd = line.index(protocolsStart, offsetBy: protocolsRange.length)
                let protocols = String(line[protocolsStart..<protocolsEnd])

                let protocolList = protocols.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                for protocolName in protocolList {
                    if !protocolName.isEmpty {
                        let dependency = Dependency(
                            from: typeName,
                            to: protocolName,
                            type: .protocolConformance,
                            strength: .medium
                        )
                        dependencyGraph.addDependency(dependency)
                    }
                }
            }
        }
    }

    private func analyzeUsageDependencies(line: String, sourceFile: String) {
        // Look for property types and variable declarations
        let variablePattern = "(var|let)\\s+([A-Za-z][A-Za-z0-9_]*)\\s*:\\s*([A-Za-z][A-Za-z0-9_<>\\[\\],\\s]*)"
        if let regex = try? NSRegularExpression(pattern: variablePattern) {
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))
            for match in matches {
                if match.range.location != NSNotFound {
                    let typeRange = match.range(at: 3)
                    if typeRange.location != NSNotFound {
                        let typeStart = line.index(line.startIndex, offsetBy: typeRange.location)
                    let typeEnd = line.index(typeStart, offsetBy: typeRange.length)
                        let typeString = String(line[typeStart..<typeEnd])

                        // Extract type name (remove generics, arrays, etc.)
                        let typeName = extractTypeName(from: typeString)
                    if !typeName.isEmpty {
                            let dependency = Dependency(
                                from: sourceFile,
                                to: typeName,
                                type: .typeReference,
                                strength: .medium
                            )
                            dependencyGraph.addDependency(dependency)
                        }
                    }
                }
            }
        }
    }

    private func analyzeFunctionCallDependencies(line: String, sourceFile: String) {
        // Look for function calls and method invocations
        let functionCallPattern = "([A-Za-z][A-Za-z0-9_\\.]+)\\s*\\("
        if let regex = try? NSRegularExpression(pattern: functionCallPattern) {
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))
            for match in matches {
                if match.range.location != NSNotFound {
                    let functionRange = match.range(at: 1)
                    if functionRange.location != NSNotFound {
                        let functionStart = line.index(line.startIndex, offsetBy: functionRange.location)
                        let functionEnd = line.index(functionStart, offsetBy: functionRange.length)
                        let functionCall = String(line[functionStart..<functionEnd])

                        // Extract the target type/function name
                        let components = functionCall.components(separatedBy: ".")
                        if components.count > 1 {
                            let target = components.dropLast().joined(separator: ".")
                            if !target.isEmpty && target != "self" {
                                let dependency = Dependency(
                                    from: sourceFile,
                                    to: target,
                                    type: .functionCall,
                                    strength: .weak
                                )
                                dependencyGraph.addDependency(dependency)
                            }
                        }
                    }
                }
            }
        }
    }

    private func extractTypeName(from typeString: String) -> String {
        // Remove array brackets, optionals, generics, etc.
        var cleanType = typeString
        cleanType = cleanType.replacingOccurrences(of: "[", with: "")
        cleanType = cleanType.replacingOccurrences(of: "]", with: "")
        cleanType = cleanType.replacingOccurrences(of: "?", with: "")
        cleanType = cleanType.replacingOccurrences(of: "!", with: "")

        // Split on whitespace and take the first component
        let components = cleanType.components(separatedBy: .whitespacesAndNewlines)
        return components.first?.components(separatedBy: "<").first ?? ""
    }
}