import Foundation
import SwiftSyntax
import SwiftParser

/// Enhanced rule that detects violations of architectural layering principles using dependency analysis

/// Helper to find type declarations in source code
private class TypeDeclarationFinder: SyntaxAnyVisitor {
    let targetTypeName: String
    var foundLocation: AbsolutePosition?

    init(targetTypeName: String) {
        self.targetTypeName = targetTypeName
        super.init(viewMode: .fixedUp)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == targetTypeName {
            foundLocation = node.position
            return .skipChildren
        }
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == targetTypeName {
            foundLocation = node.position
            return .skipChildren
        }
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == targetTypeName {
            foundLocation = node.position
            return .skipChildren
        }
        return .visitChildren
    }
}
public final class EnhancedLayeredDependenciesRule: Rule {
    public var id: String { "enhanced_layered_dependencies" }
    public var name: String { "Enhanced Layered Dependencies" }
    public var description: String { "Detects architectural layering violations using dependency graph analysis" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    // Note: Infrastructure components are created per analysis for thread safety

    public init() {
        // No shared state stored in instance variables
    }

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []

        // Get configuration for this rule
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)

        // Check if rule should analyze this file
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else {
            return []
        }

        // Skip if rule is disabled
        guard ruleConfig.enabled else { return [] }

        // Create fresh infrastructure components for thread safety
        let dependencyAnalyzer = DependencyAnalyzer()
        let typeResolver = TypeResolver()
        let layerValidator = LayerValidator(policy: LayerValidator.cleanArchitecturePolicy())

        // Perform multi-stage analysis
        violations.append(contentsOf: await performDependencyAnalysis(sourceFile: sourceFile, context: context, ruleConfig: ruleConfig, dependencyAnalyzer: dependencyAnalyzer, layerValidator: layerValidator))
        violations.append(contentsOf: await performTypeAnalysis(sourceFile: sourceFile, context: context, ruleConfig: ruleConfig, typeResolver: typeResolver))
        violations.append(contentsOf: await performLayerValidation(sourceFile: sourceFile, context: context, ruleConfig: ruleConfig, layerValidator: layerValidator))

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }

    // MARK: - Analysis Methods

    /// Find the location of a type declaration in source code
    private func findTypeLocation(for typeName: String, in sourceFile: SourceFile) -> AbsolutePosition {
        let finder = TypeDeclarationFinder(targetTypeName: typeName)
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)

        finder.walk(tree)
        if let location = finder.foundLocation {
            return location
        }

        // Fallback to start of file if not found
        return AbsolutePosition(utf8Offset: 0)
    }

    /// Analyze dependencies using the DependencyGraph infrastructure
    private func performDependencyAnalysis(sourceFile: SourceFile, context: AnalysisContext, ruleConfig: RuleSpecificConfiguration, dependencyAnalyzer: DependencyAnalyzer, layerValidator: LayerValidator) async -> [Violation] {
        var violations: [Violation] = []

        // Build dependency graph
        let dependencyGraph = dependencyAnalyzer.analyze(files: [sourceFile])

        // Check for architectural violations
        let layerViolations = layerValidator.validate(dependencyGraph)

        // Convert layer violations to rule violations with enhanced context and accurate locations
        for layerViolation in layerViolations {
            // Try to find the actual location of the violating type
            let violatingTypeName = extractTypeName(from: layerViolation.fromLayer)
            let typeLocation = findTypeLocation(for: violatingTypeName, in: sourceFile)
            let location = sourceFile.location(for: typeLocation)

            let violation = ViolationBuilder(
                ruleId: id,
                category: .architecture,
                location: location
            )
            .message("Layer violation: \(layerViolation.fromLayer) -> \(layerViolation.toLayer) using \(layerViolation.dependencyType.rawValue)")
            .suggestFix("Follow proper layering principles - consider dependency inversion")
            .severity(severity(from: layerViolation.severity, ruleSeverity: ruleConfig.severity))
            .build()

            violations.append(violation)
        }

        return violations
    }

    /// Analyze type relationships using the TypeResolver infrastructure
    private func performTypeAnalysis(sourceFile: SourceFile, context: AnalysisContext, ruleConfig: RuleSpecificConfiguration, typeResolver: TypeResolver) async -> [Violation] {
        var violations: [Violation] = []

        // Resolve types in the source file
        typeResolver.resolveTypes(from: [sourceFile])

        // Get type complexity from configuration
        let maxDependencyDepth = ruleConfig.parameter("maxDependencyDepth", defaultValue: 3)
        _ = ruleConfig.parameter("allowLayerCrossing", defaultValue: false)
        
        // Patterns that legitimately require many methods (visitor pattern, protocol implementations)
        let visitorPatterns = ["Visitor", "Walker", "Rewriter", "Observer", "Handler", "Delegate"]

        // Check for problematic type relationships
        let allTypes = typeResolver.allTypes

        for type in allTypes {
            // Skip visitor pattern classes - they legitimately need many methods
            let isVisitorPattern = visitorPatterns.contains { pattern in
                type.name.contains(pattern) ||
                type.inheritanceChain.contains { $0.contains(pattern) } ||
                type.conformances.contains { $0.contains(pattern) }
            }
            
            if isVisitorPattern {
                continue
            }
            
            // Check if type has too many dependencies
            let complexity = typeResolver.complexity(of: type.name)
            if let complexity = complexity, complexity.complexityScore > maxDependencyDepth * 10 {
                let typeLocation = findTypeLocation(for: type.name, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Type '\(type.name)' has excessive dependencies (complexity: \(complexity.complexityScore))")
                .suggestFix("Consider breaking down \(type.name) into smaller, more focused types")
                .severity(severity(from: .warning, ruleSeverity: ruleConfig.severity))
                .build()

                violations.append(violation)
            }

            // Check for God class anti-pattern
            if let complexity = complexity, complexity.isGodClass {
                let typeLocation = findTypeLocation(for: type.name, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Type '\(type.name)' appears to be a God class with \(complexity.methodCount) methods and \(complexity.propertyCount) properties")
                .suggestFix("Extract smaller classes or use composition to reduce responsibilities")
                .severity(severity(from: .error, ruleSeverity: ruleConfig.severity))
                .build()

                violations.append(violation)
            }
        }

        return violations
    }

    /// Perform enhanced layer validation using both dependency and type information
    private func performLayerValidation(sourceFile: SourceFile, context: AnalysisContext, ruleConfig: RuleSpecificConfiguration, layerValidator: LayerValidator) async -> [Violation] {
        var violations: [Violation] = []

        // Get validation settings from configuration
        let enforceStrictLayering = ruleConfig.parameter("enforceStrictLayering", defaultValue: true)
        let allowedCrossLayers = ruleConfig.parameter("allowedCrossLayers", defaultValue: [String]())

        // If strict layering is not enforced, skip detailed validation
        guard enforceStrictLayering else { return violations }

        // Enhanced layer detection using both type and dependency analysis
        let sourceContent = sourceFile.source()
        let violationsFromContent = detectLayerViolations(
            content: sourceContent,
            allowedCrossLayers: allowedCrossLayers,
            sourceFile: sourceFile,
            ruleConfig: ruleConfig
        )

        violations.append(contentsOf: violationsFromContent)

        return violations
    }

    /// Detect layer violations in source code with enhanced pattern matching
    private func detectLayerViolations(
        content: String,
        allowedCrossLayers: [String],
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration
    ) -> [Violation] {
        var violations: [Violation] = []

        // Enhanced layer patterns
        let presentationLayer = ["ViewController", "View", "ViewModel", "Presenter", "Controller", "Coordinator"]
        let dataLayer = ["DataSource", "Database", "Storage", "Cache", "Network", "API"]

        let lines = content.components(separatedBy: .newlines)

        for (lineIndex, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip comments and empty lines
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("//") {
                continue
            }

            // Detect direct dependencies between non-adjacent layers
            for presentation in presentationLayer {
                for data in dataLayer {
                    if trimmedLine.contains("\(presentation)") && trimmedLine.contains("\(data)") {
                        // Check if this cross-layer dependency is allowed
                        let dependencyPattern = "\(presentation)->\(data)"
                        if !allowedCrossLayers.contains(dependencyPattern) {
                            // Calculate position based on cumulative UTF-8 offset with proper newline handling
                            var utf8Offset = 0
                            for i in 0..<lineIndex {
                                utf8Offset += lines[i].utf8.count + 1  // +1 for newline character
                            }
                            let linePosition = AbsolutePosition(utf8Offset: utf8Offset)
                            let location = sourceFile.location(for: linePosition)

                            let violation = ViolationBuilder(
                                ruleId: id,
                                category: .architecture,
                                location: location
                            )
                            .message("Direct dependency from presentation layer (\(presentation)) to data layer (\(data)) violates layered architecture")
                            .suggestFix("Introduce a business layer service or repository to mediate this dependency")
                            .severity(severity(from: .error, ruleSeverity: ruleConfig.severity))
                            .build()

                            violations.append(violation)
                        }
                    }
                }
            }

            // Detect data layer depending on presentation layer
            for data in dataLayer {
                for presentation in presentationLayer {
                    if trimmedLine.contains("\(data)") && trimmedLine.contains("\(presentation)") {
                        // Calculate position based on cumulative UTF-8 offset with proper newline handling
                        var utf8Offset = 0
                        for i in 0..<lineIndex {
                            utf8Offset += lines[i].utf8.count + 1  // +1 for newline character
                        }
                        let linePosition = AbsolutePosition(utf8Offset: utf8Offset)
                        let location = sourceFile.location(for: linePosition)

                        let violation = ViolationBuilder(
                            ruleId: id,
                            category: .architecture,
                            location: location
                        )
                        .message("Data layer (\(data)) depending on presentation layer (\(presentation)) creates circular dependency")
                        .suggestFix("Use dependency inversion with protocols or observer pattern")
                        .severity(severity(from: .error, ruleSeverity: ruleConfig.severity))
                        .build()

                        violations.append(violation)
                    }
                }
            }
        }

        return violations
    }

    /// Helper to extract type name from layer identifier
    private func extractTypeName(from layerIdentifier: String) -> String {
        // Extract the type name from layer identifier
        // Layer identifiers may contain additional info like "Layer:Type" or "Type"
        if let colonIndex = layerIdentifier.firstIndex(of: ":") {
            return String(layerIdentifier[layerIdentifier.index(after: colonIndex)...])
        }

        // Extract the base type name (remove common suffixes)
        let typeName = layerIdentifier
        let suffixesToRemove = ["Layer", "Component", "Service", "Manager", "Controller", "View"]

        for suffix in suffixesToRemove {
            if typeName.hasSuffix(suffix) {
                return String(typeName.dropLast(suffix.count))
            }
        }

        return typeName
    }

    /// Helper to map severity with configuration override
    private func severity(from baseSeverity: DiagnosticSeverity, ruleSeverity: DiagnosticSeverity) -> DiagnosticSeverity {
        // Use the more severe of the two
        switch (baseSeverity, ruleSeverity) {
        case (.error, _), (_, .error):
            return .error
        case (.warning, _), (_, .warning):
            return .warning
        default:
            return .info
        }
    }
}

/// Extension to enhance the rule with configuration-specific behavior
extension EnhancedLayeredDependenciesRule {
    /// Create configuration for different architectural patterns
    public static func configuration(for pattern: ArchitecturalPattern) -> RuleSpecificConfiguration {
        switch pattern {
        case .cleanArchitecture:
            return RuleSpecificConfiguration(
                ruleId: "enhanced_layered_dependencies",
                enabled: true,
                severity: .error,
                parameters: [
                    "enforceStrictLayering": .booleanValue(true),
                    "maxDependencyDepth": .integerValue(3),
                    "allowLayerCrossing": .booleanValue(false),
                    "allowedCrossLayers": .stringArrayValue([])
                ]
            )

        case .mvc:
            return RuleSpecificConfiguration(
                ruleId: "enhanced_layered_dependencies",
                enabled: true,
                severity: .warning,
                parameters: [
                    "enforceStrictLayering": .booleanValue(false),
                    "maxDependencyDepth": .integerValue(5),
                    "allowLayerCrossing": .booleanValue(true),
                    "allowedCrossLayers": .stringArrayValue(["ViewController->Service", "View->ViewModel"])
                ]
            )

        case .mvvm:
            return RuleSpecificConfiguration(
                ruleId: "enhanced_layered_dependencies",
                enabled: true,
                severity: .warning,
                parameters: [
                    "enforceStrictLayering": .booleanValue(false),
                    "maxDependencyDepth": .integerValue(4),
                    "allowLayerCrossing": .booleanValue(true),
                    "allowedCrossLayers": .stringArrayValue(["ViewController->ViewModel", "View->ViewModel"])
                ]
            )
        }
    }
}

/// Supported architectural patterns
public enum ArchitecturalPattern: String, CaseIterable {
    case cleanArchitecture = "clean_architecture"
    case mvc = "mvc"
    case mvvm = "mvvm"

    public var description: String {
        switch self {
        case .cleanArchitecture:
            return "Clean Architecture with strict layer separation"
        case .mvc:
            return "Model-View-Controller pattern"
        case .mvvm:
            return "Model-View-ViewModel pattern"
        }
    }
}