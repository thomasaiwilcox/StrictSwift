import Foundation
import SwiftSyntax
import SwiftParser

/// Enhanced rule that detects classes violating Single Responsibility Principle using type analysis

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
public final class EnhancedGodClassRule: Rule {
    public var id: String { "enhanced_god_class" }
    public var name: String { "Enhanced God Class" }
    public var description: String { "Detects classes with too many responsibilities using comprehensive type analysis" }
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
        let typeResolver = TypeResolver()
        let dependencyAnalyzer = DependencyAnalyzer()
        let performanceProfiler = PerformanceProfiler()

        // Start performance profiling
        let operationId = performanceProfiler.startOperation(id)

        defer {
            _ = performanceProfiler.endOperation(operationId, fileCount: 1, linesAnalyzed: sourceFile.source().components(separatedBy: .newlines).count)
        }

        // Perform comprehensive analysis using infrastructure components
        violations.append(contentsOf: await performTypeBasedAnalysis(sourceFile: sourceFile, context: context, ruleConfig: ruleConfig, typeResolver: typeResolver))
        violations.append(contentsOf: await performDependencyBasedAnalysis(sourceFile: sourceFile, context: context, ruleConfig: ruleConfig, dependencyAnalyzer: dependencyAnalyzer))
        violations.append(contentsOf: await performStructuralAnalysis(sourceFile: sourceFile, context: context, ruleConfig: ruleConfig))
        violations.append(contentsOf: await performBehavioralAnalysis(sourceFile: sourceFile, context: context, ruleConfig: ruleConfig))

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

    /// Analyze types using TypeResolver infrastructure
    private func performTypeBasedAnalysis(sourceFile: SourceFile, context: AnalysisContext, ruleConfig: RuleSpecificConfiguration, typeResolver: TypeResolver) async -> [Violation] {
        var violations: [Violation] = []

        // Resolve types in the source file
        typeResolver.resolveTypes(from: [sourceFile])

        // Get configuration thresholds
        let maxMethods = ruleConfig.parameter("maxMethods", defaultValue: 15)
        let maxProperties = ruleConfig.parameter("maxProperties", defaultValue: 15)
        let maxComplexityScore = ruleConfig.parameter("maxComplexityScore", defaultValue: 50)
        let checkInheritance = ruleConfig.parameter("checkInheritance", defaultValue: true)
        let maxInheritanceDepth = ruleConfig.parameter("maxInheritanceDepth", defaultValue: 3)

        // Analyze each resolved type
        for type in typeResolver.allTypes {
            guard type.kind == .class else { continue }

            let complexity = typeResolver.complexity(of: type.name)
            guard let complexity = complexity else { continue }

            // Check for various God class indicators
            if complexity.methodCount > maxMethods {
                let typeLocation = findTypeLocation(for: type.name, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Class '\(type.name)' has too many methods (\(complexity.methodCount)) - violates Single Responsibility Principle")
                .suggestFix("Extract related methods into separate classes or use composition")
                .severity(severityForCount(count: complexity.methodCount, threshold: maxMethods, ruleSeverity: ruleConfig.severity))
                .build()

                violations.append(violation)
            }

            if complexity.propertyCount > maxProperties {
                let typeLocation = findTypeLocation(for: type.name, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Class '\(type.name)' has too many properties (\(complexity.propertyCount)) - violates Single Responsibility Principle")
                .suggestFix("Group related properties into value types or separate classes")
                .severity(severityForCount(count: complexity.propertyCount, threshold: maxProperties, ruleSeverity: ruleConfig.severity))
                .build()

                violations.append(violation)
            }

            if complexity.complexityScore > maxComplexityScore || complexity.isGodClass {
                let typeLocation = findTypeLocation(for: type.name, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Class '\(type.name)' has excessive complexity (score: \(complexity.complexityScore)) - likely a God class")
                .suggestFix("Break down into smaller, more focused classes with clear responsibilities")
                .severity(severityForCount(count: complexity.complexityScore, threshold: maxComplexityScore, ruleSeverity: ruleConfig.severity))
                .build()

                violations.append(violation)
            }

            if checkInheritance && complexity.inheritanceDepth > maxInheritanceDepth {
                let typeLocation = findTypeLocation(for: type.name, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Class '\(type.name)' has deep inheritance hierarchy (\(complexity.inheritanceDepth) levels)")
                .suggestFix("Consider using composition instead of deep inheritance, or flatten the hierarchy")
                .severity(severityForCount(count: complexity.inheritanceDepth, threshold: maxInheritanceDepth, ruleSeverity: ruleConfig.severity))
                .build()

                violations.append(violation)
            }
        }

        return violations
    }

    /// Analyze dependencies using DependencyAnalyzer infrastructure
    private func performDependencyBasedAnalysis(sourceFile: SourceFile, context: AnalysisContext, ruleConfig: RuleSpecificConfiguration, dependencyAnalyzer: DependencyAnalyzer) async -> [Violation] {
        var violations: [Violation] = []

        // Build dependency graph
        let dependencyGraph = dependencyAnalyzer.analyze(files: [sourceFile])

        // Get configuration thresholds
        let maxDependencies = ruleConfig.parameter("maxDependencies", defaultValue: 10)
        let checkCyclicDependencies = ruleConfig.parameter("checkCyclicDependencies", defaultValue: true)

        // Analyze dependency graph for God class patterns
        for node in dependencyGraph.allNodes {
            guard node.type == .class else { continue }

            let dependencyCount = node.dependencies.count
            let dependentCount = node.dependents.count

            // Check for too many outgoing dependencies
            if dependencyCount > maxDependencies {
                let typeLocation = findTypeLocation(for: node.name, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Class '\(node.name)' depends on too many other components (\(dependencyCount))")
                .suggestFix("Extract an interface or use dependency injection to reduce coupling")
                .severity(severityForCount(count: dependencyCount, threshold: maxDependencies, ruleSeverity: ruleConfig.severity))
                .build()

                violations.append(violation)
            }

            // Check for being depended on by too many components (Law of Demeter violation)
            if dependentCount > maxDependencies {
                let typeLocation = findTypeLocation(for: node.name, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Class '\(node.name)' is depended on by too many components (\(dependentCount)) - potential God class")
                .suggestFix("Consider using an interface to reduce direct dependencies on this class")
                .severity(severityForCount(count: dependentCount, threshold: maxDependencies, ruleSeverity: ruleConfig.severity))
                .build()

                violations.append(violation)
            }
        }

        // Check for circular dependencies if enabled
        if checkCyclicDependencies {
            let cycles = dependencyGraph.findCycles()
            if !cycles.isEmpty {
                let location = sourceFile.location(for: AbsolutePosition(utf8Offset: 0))

                for (_, cycle) in cycles.enumerated() {
                    let violation = ViolationBuilder(
                        ruleId: id,
                        category: .architecture,
                        location: location
                    )
                    .message("Circular dependency detected: \(cycle.joined(separator: " → "))")
                    .suggestFix("Break the cycle by introducing abstractions or redesigning the relationship")
                    .severity(severity(from: .error, ruleSeverity: ruleConfig.severity))
                    .build()

                    violations.append(violation)
                }
            }
        }

        return violations
    }

    /// Perform structural analysis of the source code
    private func performStructuralAnalysis(sourceFile: SourceFile, context: AnalysisContext, ruleConfig: RuleSpecificConfiguration) async -> [Violation] {
        var violations: [Violation] = []

        // Get configuration settings
        let maxLines = ruleConfig.parameter("maxLines", defaultValue: 200)
        let maxNestingDepth = ruleConfig.parameter("maxNestingDepth", defaultValue: 4)
        let checkLongMethods = ruleConfig.parameter("checkLongMethods", defaultValue: true)
        let maxMethodLines = ruleConfig.parameter("maxMethodLines", defaultValue: 50)

        let source = sourceFile.source()
        let lines = source.components(separatedBy: .newlines)

        // Check overall file length
        if lines.count > maxLines {
            let location = sourceFile.location(for: AbsolutePosition(utf8Offset: 0))

            let violation = ViolationBuilder(
                ruleId: id,
                category: .architecture,
                location: location
            )
            .message("File contains \(lines.count) lines, exceeding threshold of \(maxLines)")
            .suggestFix("Consider splitting into multiple files")
            .severity(severityForCount(count: lines.count, threshold: maxLines, ruleSeverity: ruleConfig.severity))
            .build()

            violations.append(violation)
        }

        // Analyze structural patterns
        var currentClass: String?
        var currentNestingDepth = 0
        var methodStartLine = 0

        for (lineIndex, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Track class declarations
            if trimmedLine.hasPrefix("class ") && trimmedLine.contains("{") {
                if let className = extractClassName(from: trimmedLine) {
                    currentClass = className
                }
            }

            // Track nesting depth
            let openBraces = line.filter { $0 == "{" }.count
            let closeBraces = line.filter { $0 == "}" }.count
            currentNestingDepth += openBraces - closeBraces

            // Check for excessive nesting
            if currentNestingDepth > maxNestingDepth && currentClass != nil {
                // Calculate position based on line index (include newlines)
                let utf8Count = lines.prefix(lineIndex).joined(separator: "\n").utf8.count + lineIndex
                let linePosition = AbsolutePosition(utf8Offset: utf8Count)
                let location = sourceFile.location(for: linePosition)

                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Excessive nesting depth (\(currentNestingDepth)) in class '\(currentClass ?? "Unknown")'")
                .suggestFix("Extract nested code into separate methods or classes")
                .severity(severity(from: .warning, ruleSeverity: ruleConfig.severity))
                .build()

                violations.append(violation)
            }

            // Track method boundaries
            if checkLongMethods && (trimmedLine.hasPrefix("func ") || trimmedLine.contains(" func ")) {
                methodStartLine = lineIndex
            }

            // Check method length when method ends
            if checkLongMethods && trimmedLine.hasPrefix("}") && currentClass != nil && methodStartLine > 0 {
                let methodLength = lineIndex - methodStartLine + 1
                if methodLength > maxMethodLines {
                    // Use method start line for location
                    let utf8Count = lines.prefix(methodStartLine).joined(separator: "\n").utf8.count + methodStartLine
                    let methodPosition = AbsolutePosition(utf8Offset: utf8Count)
                    let location = sourceFile.location(for: methodPosition)

                    let violation = ViolationBuilder(
                        ruleId: id,
                        category: .architecture,
                        location: location
                    )
                    .message("Method in class '\(currentClass ?? "Unknown")' is too long (\(methodLength) lines)")
                    .suggestFix("Break down into smaller, more focused methods")
                    .severity(severityForCount(count: methodLength, threshold: maxMethodLines, ruleSeverity: ruleConfig.severity))
                    .build()

                    violations.append(violation)
                }
                methodStartLine = 0
            }
        }

        return violations
    }

    /// Perform behavioral analysis to detect anti-patterns
    private func performBehavioralAnalysis(sourceFile: SourceFile, context: AnalysisContext, ruleConfig: RuleSpecificConfiguration) async -> [Violation] {
        var violations: [Violation] = []

        // Get configuration settings
        let checkMultipleResponsibilities = ruleConfig.parameter("checkMultipleResponsibilities", defaultValue: true)
        let checkLawOfDemeter = ruleConfig.parameter("checkLawOfDemeter", defaultValue: true)
        let checkPrimitives = ruleConfig.parameter("checkPrimitives", defaultValue: false)

        let source = sourceFile.source()

        if checkMultipleResponsibilities {
            // Look for classes with mixed concerns
            let mixedConcerns = analyzeMixedConcerns(source: source)
            for concern in mixedConcerns {
                let typeLocation = findTypeLocation(for: concern.className, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Class '\(concern.className)' has mixed responsibilities: \(concern.responsibilities.joined(separator: ", "))")
                .suggestFix("Separate these concerns into different classes following Single Responsibility Principle")
                .severity(severity(from: .warning, ruleSeverity: ruleConfig.severity))
                .build()

                violations.append(violation)
            }
        }

        if checkLawOfDemeter {
            // Look for Law of Demeter violations
            let demeterViolations = analyzeLawOfDemeterViolations(source: source)
            for violation in demeterViolations {
                violations.append(violation)
            }
        }

        if checkPrimitives {
            // Look for Primitive Obsession
            let primitiveViolations = analyzePrimitiveObsession(source: source, sourceFile: sourceFile, ruleConfig: ruleConfig)
            for violation in primitiveViolations {
                violations.append(violation)
            }
        }

        return violations
    }

    // MARK: - Helper Methods

    private func severityForCount(count: Int, threshold: Int, ruleSeverity: DiagnosticSeverity) -> DiagnosticSeverity {
        let ratio = Double(count) / Double(threshold)
        switch ratio {
        case 2.0...:
            return .error
        case 1.5..<2.0:
            return ruleSeverity == .error ? .error : .warning
        default:
            return ruleSeverity
        }
    }

    private func severity(from baseSeverity: DiagnosticSeverity, ruleSeverity: DiagnosticSeverity) -> DiagnosticSeverity {
        switch (baseSeverity, ruleSeverity) {
        case (.error, _), (_, .error):
            return .error
        case (.warning, _), (_, .warning):
            return .warning
        default:
            return .info
        }
    }

    private func extractClassName(from line: String) -> String? {
        let pattern = #"class\s+([A-Za-z][A-Za-z0-9_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) else {
            return nil
        }

        let nsRange = match.range(at: 1)
        guard nsRange.location != NSNotFound else {
            return nil
        }

        let start = line.index(line.startIndex, offsetBy: nsRange.location)
        let end = line.index(start, offsetBy: nsRange.length)
        return String(line[start..<end])
    }

    private func analyzeMixedConcerns(source: String) -> [(className: String, responsibilities: [String])] {
        var mixedConcerns: [(className: String, responsibilities: [String])] = []

        // Simplified analysis - in a real implementation, this would be more sophisticated
        let lines = source.components(separatedBy: .newlines)
        var currentClass: String?
        var responsibilities: Set<String> = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.hasPrefix("class ") {
                if let className = extractClassName(from: trimmedLine) {
                    if let currentClass = currentClass, !responsibilities.isEmpty {
                        mixedConcerns.append((className: currentClass, responsibilities: Array(responsibilities)))
                    }
                    currentClass = className
                    responsibilities.removeAll()
                }
            }

            // Look for patterns indicating different responsibilities
            if trimmedLine.contains("func ") {
                if trimmedLine.lowercased().contains("save") || trimmedLine.lowercased().contains("load") {
                    responsibilities.insert("Persistence")
                }
                if trimmedLine.lowercased().contains("validate") || trimmedLine.lowercased().contains("calculate") {
                    responsibilities.insert("Business Logic")
                }
                if trimmedLine.lowercased().contains("network") || trimmedLine.lowercased().contains("api") {
                    responsibilities.insert("Network Communication")
                }
                if trimmedLine.lowercased().contains("ui") || trimmedLine.lowercased().contains("view") {
                    responsibilities.insert("UI Logic")
                }
            }
        }

        // Add the last class if it exists
        if let currentClass = currentClass, !responsibilities.isEmpty {
            mixedConcerns.append((className: currentClass, responsibilities: Array(responsibilities)))
        }

        return mixedConcerns.filter { $0.responsibilities.count > 2 }
    }

    private func analyzeLawOfDemeterViolations(source: String) -> [Violation] {
        // Simplified implementation - would need more sophisticated parsing in production
        return []
    }

    private func analyzePrimitiveObsession(source: String, sourceFile: SourceFile, ruleConfig: RuleSpecificConfiguration) -> [Violation] {
        var violations: [Violation] = []

        let primitiveTypes = ["String", "Int", "Double", "Bool", "Array", "Dictionary"]
        let lines = source.components(separatedBy: .newlines)

        for (lineIndex, line) in lines.enumerated() {
            for primitive in primitiveTypes {
                if line.contains("let \(primitive):") || line.contains("var \(primitive):") {
                    // This is a very simplified check
                    let utf8Count = lines.prefix(lineIndex).joined(separator: "\n").utf8.count + lineIndex
                    let linePosition = AbsolutePosition(utf8Offset: utf8Count)
                    let location = sourceFile.location(for: linePosition)

                    let violation = ViolationBuilder(
                        ruleId: id,
                        category: .architecture,
                        location: location
                    )
                    .message("Consider using value types instead of primitive \(primitive) for better type safety")
                    .suggestFix("Create a custom value type that encapsulates the primitive behavior")
                    .severity(.info)
                    .build()

                    violations.append(violation)
                }
            }
        }

        return violations
    }
}

/// Extension to create rule configurations for different project types
extension EnhancedGodClassRule {
    /// Create configuration for different project scales
    public static func configuration(for projectScale: ProjectScale) -> RuleSpecificConfiguration {
        switch projectScale {
        case .small:
            return RuleSpecificConfiguration(
                ruleId: "enhanced_god_class",
                enabled: true,
                severity: .info,
                parameters: [
                    "maxMethods": .integerValue(10),
                    "maxProperties": .integerValue(8),
                    "maxComplexityScore": .integerValue(30),
                    "maxLines": .integerValue(100),
                    "checkInheritance": .booleanValue(true),
                    "maxDependencies": .integerValue(5)
                ]
            )

        case .medium:
            return RuleSpecificConfiguration(
                ruleId: "enhanced_god_class",
                enabled: true,
                severity: .warning,
                parameters: [
                    "maxMethods": .integerValue(15),
                    "maxProperties": .integerValue(15),
                    "maxComplexityScore": .integerValue(50),
                    "maxLines": .integerValue(200),
                    "checkInheritance": .booleanValue(true),
                    "maxDependencies": .integerValue(10)
                ]
            )

        case .large:
            return RuleSpecificConfiguration(
                ruleId: "enhanced_god_class",
                enabled: true,
                severity: .error,
                parameters: [
                    "maxMethods": .integerValue(25),
                    "maxProperties": .integerValue(25),
                    "maxComplexityScore": .integerValue(80),
                    "maxLines": .integerValue(500),
                    "checkInheritance": .booleanValue(true),
                    "maxDependencies": .integerValue(15)
                ]
            )
        }
    }
}

/// Project scale definitions
public enum ProjectScale: String, CaseIterable {
    case small = "small"
    case medium = "medium"
    case large = "large"

    public var description: String {
        switch self {
        case .small:
            return "Small projects with limited scope"
        case .medium:
            return "Medium projects with moderate complexity"
        case .large:
            return "Large projects with extensive functionality"
        }
    }
}