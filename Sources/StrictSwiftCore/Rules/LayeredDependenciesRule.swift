import Foundation
import SwiftSyntax

/// Detects violations of architectural layering principles
public final class LayeredDependenciesRule: Rule {
    public var id: String { "layered_dependencies" }
    public var name: String { "Layered Dependencies" }
    public var description: String { "Detects violations of architectural layering principles" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = LayeredDependenciesVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds architectural layering violations
private final class LayeredDependenciesVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    // Common architectural layers and their naming patterns
    private let presentationLayerPatterns: Set<String> = [
        "View", "ViewController", "Presenter", "ViewModel", "Controller",
        "UI", "Activity", "Fragment", "Window", "Scene", "Coordinator"
    ]

    private let dataLayerPatterns: Set<String> = [
        "DataSource", "DataAccess", "Database", "Storage", "Cache",
        "Network", "API", "Remote", "Local", "Persistence"
    ]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        let nodeDescription = node.description

        // Check for layering violations by analyzing imports and class relationships
        analyzeImports(nodeDescription, node: node)
        analyzeClassDependencies(nodeDescription, node: node)

        return .visitChildren
    }

    private func analyzeImports(_ nodeDescription: String, node: Syntax) {
        // Check for UI components importing data layer directly (should go through business layer)
        if nodeDescription.contains("import") {
            let lines = nodeDescription.components(separatedBy: .newlines)

            for line in lines {
                if line.contains("import") && (line.contains("UIKit") || line.contains("AppKit")) {
                    // Check if this file also imports data layer components
                    if nodeDescription.contains("import") &&
                       (nodeDescription.contains("Database") ||
                        nodeDescription.contains("CoreData") ||
                        nodeDescription.contains("Realm") ||
                        nodeDescription.contains("SQLite")) {

                        let location = sourceFile.location(of: node)

                        let violation = ViolationBuilder(
                            ruleId: "layered_dependencies",
                            category: .architecture,
                            location: location
                        )
                        .message("Presentation layer importing data layer directly")
                        .suggestFix("Use business layer as abstraction between presentation and data layers")
                        .severity(.warning)
                        .build()

                        violations.append(violation)
                    }
                }
            }
        }
    }

    private func analyzeClassDependencies(_ nodeDescription: String, node: Syntax) {
        // Check for class naming and detect potential layering violations
        let words = extractWords(from: nodeDescription)

        for (index, word) in words.enumerated() {
            // Check if we have a presentation layer class depending on data layer
            if presentationLayerPatterns.contains(word) {
                // Look for data layer dependencies in the next few words
                let nextWords = Array(words.dropFirst(index + 1).prefix(10))

                for nextWord in nextWords {
                    if dataLayerPatterns.contains(nextWord) {
                        let location = sourceFile.location(of: node)

                        let violation = ViolationBuilder(
                            ruleId: "layered_dependencies",
                            category: .architecture,
                            location: location
                        )
                        .message("Presentation layer '\(word)' directly depending on data layer '\(nextWord)'")
                        .suggestFix("Introduce business layer abstraction between presentation and data layers")
                        .severity(.warning)
                        .build()

                        violations.append(violation)
                        break
                    }
                }
            }

            // Check for data layer depending on presentation layer (inverted dependency)
            if dataLayerPatterns.contains(word) {
                let nextWords = Array(words.dropFirst(index + 1).prefix(10))

                for nextWord in nextWords {
                    if presentationLayerPatterns.contains(nextWord) {
                        let location = sourceFile.location(of: node)

                        let violation = ViolationBuilder(
                            ruleId: "layered_dependencies",
                            category: .architecture,
                            location: location
                        )
                        .message("Data layer '\(word)' depending on presentation layer '\(nextWord)'")
                        .suggestFix("Use dependency inversion with protocols/abstractions")
                        .severity(.warning)
                        .build()

                        violations.append(violation)
                        break
                    }
                }
            }
        }
    }

    private func extractWords(from text: String) -> [String] {
        let pattern = "[A-Za-z][A-Za-z0-9]*"
        let regex = try? NSRegularExpression(pattern: pattern)
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) ?? []

        return matches.compactMap { match in
            let start = text.index(text.startIndex, offsetBy: match.range.location)
            let end = text.index(start, offsetBy: match.range.length)
            return String(text[start..<end])
        }
    }
}