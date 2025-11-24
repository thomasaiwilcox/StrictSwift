import Foundation
import SwiftSyntax

/// Detects circular dependencies between classes or modules
public final class CircularDependencyRule: Rule {
    public var id: String { "circular_dependency" }
    public var name: String { "Circular Dependency" }
    public var description: String { "Detects circular dependencies between classes or modules" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = CircularDependencyVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds potential circular dependencies
private final class CircularDependencyVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    // Patterns that might indicate circular dependencies
    private let dependencyPatterns: Set<String> = [
        "class", "struct", "protocol", "enum", "actor"
    ]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        let nodeDescription = node.description

        // Look for class declarations and their dependencies
        if nodeDescription.contains("class") || nodeDescription.contains("struct") {
            analyzeTypeDeclaration(nodeDescription, node: node)
        }

        return .visitChildren
    }

    private func analyzeTypeDeclaration(_ nodeDescription: String, node: Syntax) {
        // Extract type names and their potential dependencies
        let lines = nodeDescription.components(separatedBy: .newlines)
        var currentTypeName: String?
        var dependencies: [String] = []

        for line in lines {
            // Find type declarations
            if line.contains("class") || line.contains("struct") {
                if let range = line.range(of: "(class|struct)\\s+([A-Za-z][A-Za-z0-9]*)", options: .regularExpression) {
                    let match = String(line[range])
                    let components = match.components(separatedBy: .whitespaces)
                    if components.count >= 2 {
                        currentTypeName = components[1]
                    }
                }
            }

            // Find property declarations that might indicate dependencies
            if line.contains("let") || line.contains("var") {
                // Look for known types in the property declaration
                for dependencyPattern in dependencyPatterns {
                    if line.contains(dependencyPattern) && currentTypeName != nil {
                        dependencies.append(dependencyPattern)
                    }
                }
            }

            // Look for constructor parameters
            if line.contains("init") && currentTypeName != nil {
                for dependencyPattern in dependencyPatterns {
                    if line.contains(dependencyPattern) {
                        dependencies.append(dependencyPattern)
                    }
                }
            }
        }

        // Check for potential circular dependencies
        if let typeName = currentTypeName, !dependencies.isEmpty {
            checkForCircularDependencies(typeName: typeName, dependencies: dependencies, node: node)
        }
    }

    private func checkForCircularDependencies(typeName: String, dependencies: [String], node: Syntax) {
        // Simple heuristic: if a type depends on itself (self-reference) or has mutual dependency patterns
        for dependency in dependencies {
            // Check for self-dependency (circular reference to same type)
            if dependency.lowercased() == typeName.lowercased() {
                let location = sourceFile.location(for: node.position)

                let violation = ViolationBuilder(
                    ruleId: "circular_dependency",
                    category: .architecture,
                    location: location
                )
                .message("Potential self-reference in '\(typeName)'")
                .suggestFix("Break the circular dependency by introducing abstractions or redesigning the relationship")
                .severity(.error)
                .build()

                violations.append(violation)
            }

            // Check for patterns that commonly lead to circular dependencies
            if (dependency.contains("Manager") && typeName.contains("Service")) ||
               (dependency.contains("Service") && typeName.contains("Manager")) ||
               (dependency.contains("Controller") && typeName.contains("Coordinator")) ||
               (dependency.contains("Coordinator") && typeName.contains("Controller")) {

                let location = sourceFile.location(for: node.position)

                let violation = ViolationBuilder(
                    ruleId: "circular_dependency",
                    category: .architecture,
                    location: location
                )
                .message("Potential circular dependency between '\(typeName)' and '\(dependency)'")
                .suggestFix("Use dependency inversion with protocols or mediator pattern")
                .severity(.error)
                .build()

                violations.append(violation)
            }
        }
    }
}