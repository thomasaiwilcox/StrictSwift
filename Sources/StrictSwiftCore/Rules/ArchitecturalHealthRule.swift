import Foundation
import SwiftSyntax
import SwiftParser

/// Comprehensive architectural health analysis using all infrastructure components

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

/// Helper to find the first type declaration in source code for strategic positioning
private class FindFirstTypeVisitor: SyntaxAnyVisitor {
    var foundLocation: AbsolutePosition?

    init() {
        super.init(viewMode: .fixedUp)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        foundLocation = node.position
        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        foundLocation = node.position
        return .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        foundLocation = node.position
        return .skipChildren
    }
}
/// Comprehensive architectural health analysis rule
/// SAFETY: @unchecked Sendable is safe because this rule has no stored state.
/// Infrastructure components are created fresh per analysis call for thread safety.
public final class ArchitecturalHealthRule: Rule, @unchecked Sendable {
    public var id: String { "architectural_health" }
    public var name: String { "Architectural Health" }
    public var description: String { "Comprehensive analysis of architectural health using multiple infrastructure components" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .info }
    public var enabledByDefault: Bool { true }

    // Note: Infrastructure components are created per analysis for thread safety

    public init() {
        // No shared state stored in instance variables
    }

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []

        // Get configuration
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }

        // Create fresh infrastructure components for thread safety
        let typeResolver = TypeResolver()
        let dependencyAnalyzer = DependencyAnalyzer()
        let dependencyGraph = DependencyGraph()
        let layerValidator = LayerValidator(policy: LayerValidator.cleanArchitecturePolicy())
        let performanceProfiler = PerformanceProfiler()
        var healthMetrics = ArchitecturalHealthMetrics()

        // Start comprehensive analysis
        let analysisId = performanceProfiler.startOperation("architectural_health")

        defer {
            let lineCount = sourceFile.source().components(separatedBy: .newlines).count
            _ = performanceProfiler.endOperation(analysisId, fileCount: 1, linesAnalyzed: lineCount)
        }

        // Perform comprehensive analysis
        violations.append(contentsOf: await performHealthAssessment(
            sourceFile: sourceFile,
            context: context,
            ruleConfig: ruleConfig,
            typeResolver: typeResolver,
            dependencyAnalyzer: dependencyAnalyzer,
            dependencyGraph: dependencyGraph,
            layerValidator: layerValidator,
            healthMetrics: &healthMetrics
        ))
        violations.append(contentsOf: generateHealthReport(sourceFile: sourceFile, ruleConfig: ruleConfig, healthMetrics: healthMetrics))

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }

    // MARK: - Helper Methods

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

    // MARK: - Health Assessment

    private func performHealthAssessment(
        sourceFile: SourceFile,
        context: AnalysisContext,
        ruleConfig: RuleSpecificConfiguration,
        typeResolver: TypeResolver,
        dependencyAnalyzer: DependencyAnalyzer,
        dependencyGraph: DependencyGraph,
        layerValidator: LayerValidator,
        healthMetrics: inout ArchitecturalHealthMetrics
    ) async -> [Violation] {
        var violations: [Violation] = []

        // 1. Type Health Assessment
        violations.append(contentsOf: assessTypeHealth(sourceFile: sourceFile, ruleConfig: ruleConfig, typeResolver: typeResolver, healthMetrics: &healthMetrics))

        // 2. Dependency Health Assessment
        violations.append(contentsOf: await assessDependencyHealth(sourceFile: sourceFile, ruleConfig: ruleConfig, dependencyAnalyzer: dependencyAnalyzer, dependencyGraph: dependencyGraph, healthMetrics: &healthMetrics))

        // 3. Layer Compliance Assessment
        violations.append(contentsOf: await assessLayerCompliance(sourceFile: sourceFile, ruleConfig: ruleConfig, layerValidator: layerValidator, dependencyGraph: dependencyGraph, healthMetrics: &healthMetrics))

        // 4. Structural Health Assessment
        violations.append(contentsOf: assessStructuralHealth(sourceFile: sourceFile, ruleConfig: ruleConfig, healthMetrics: &healthMetrics))

        return violations
    }

    private func assessTypeHealth(sourceFile: SourceFile, ruleConfig: RuleSpecificConfiguration, typeResolver: TypeResolver, healthMetrics: inout ArchitecturalHealthMetrics) -> [Violation] {
        var violations: [Violation] = []

        // Resolve types
        typeResolver.resolveTypes(from: [sourceFile])

        let allTypes = typeResolver.allTypes
        healthMetrics.typeCount = allTypes.count

        var totalComplexity = 0
        var highComplexityTypes = 0
        var godClasses = 0
        var godClassNames: [String] = []

        for type in allTypes {
            if let complexity = typeResolver.complexity(of: type.name) {
                totalComplexity += complexity.complexityScore

                if complexity.isGodClass {
                    godClasses += 1
                    godClassNames.append(type.name)
                }

                if complexity.hasHighComplexity {
                    highComplexityTypes += 1
                }
            }
        }

        healthMetrics.averageTypeComplexity = allTypes.isEmpty ? 0 : totalComplexity / allTypes.count
        healthMetrics.highComplexityTypeRatio = allTypes.isEmpty ? 0 : Double(highComplexityTypes) / Double(allTypes.count)
        healthMetrics.godClassCount = godClasses

        // Generate violations for problematic types
        if godClasses > 0 {
            let threshold = ruleConfig.parameter("maxGodClasses", defaultValue: 0)
            if godClasses > threshold {
                for godClassName in godClassNames {
                    let typeLocation = findTypeLocation(for: godClassName, in: sourceFile)
                    let location = sourceFile.location(for: typeLocation)

                    violations.append(ViolationBuilder(
                        ruleId: id,
                        category: .architecture,
                        location: location
                    )
                    .message("Type '\(godClassName)' is a God class with too many responsibilities")
                    .suggestFix("Refactor into smaller, focused classes following Single Responsibility Principle")
                    .severity(.error)
                    .build())
                }
            }
        }

        return violations
    }

    private func assessDependencyHealth(sourceFile: SourceFile, ruleConfig: RuleSpecificConfiguration, dependencyAnalyzer: DependencyAnalyzer, dependencyGraph: DependencyGraph, healthMetrics: inout ArchitecturalHealthMetrics) async -> [Violation] {
        var violations: [Violation] = []

        // Build dependency graph
        let graph = dependencyAnalyzer.analyze(files: [sourceFile])
        dependencyGraph.clear()
        dependencyGraph.merge(graph)

        let allNodes = dependencyGraph.allNodes
        healthMetrics.dependencyCount = dependencyGraph.allDependencies.count

        // Find cycles
        let cycles = dependencyGraph.findCycles()
        healthMetrics.cycleCount = cycles.count

        // Analyze dependency depth
        var totalDepth = 0
        var maxDepth = 0
        for node in allNodes {
            let depth = dependencyGraph.dependencyDepth(for: node.name)
            totalDepth += depth
            maxDepth = max(maxDepth, depth)
        }

        healthMetrics.averageDependencyDepth = allNodes.isEmpty ? 0 : Double(totalDepth) / Double(allNodes.count)
        healthMetrics.maxDependencyDepth = maxDepth

        // Report cycles with accurate locations
        if !cycles.isEmpty {
            let allowedCycles = ruleConfig.parameter("allowCycles", defaultValue: false)
            if !allowedCycles {
                for (_, cycle) in cycles.enumerated() {
                    // Point to the first type in the cycle for actionable feedback
                    let firstTypeName = cycle.first ?? "Unknown"
                    let cycleLocation = findTypeLocation(for: firstTypeName, in: sourceFile)

                    violations.append(createViolation(
                        sourceFile: sourceFile,
                        message: "Circular dependency: \(cycle.joined(separator: " → "))",
                        suggestion: "Break cycle using dependency inversion or mediator pattern",
                        severity: .error,
                        at: cycleLocation
                    ))
                }
            }
        }

        // Report excessive dependency depth
        let maxAllowedDepth = ruleConfig.parameter("maxDependencyDepth", defaultValue: 5)
        if maxDepth > maxAllowedDepth {
            let deepestNode = allNodes.max { dependencyGraph.dependencyDepth(for: $0.name) < dependencyGraph.dependencyDepth(for: $1.name) }
            if let deepestNode = deepestNode {
                // Try to find the type location in the source file
                let typeLocation = findTypeLocation(for: deepestNode.name, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                violations.append(ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Excessive dependency depth for '\(deepestNode.name)': \(maxDepth) levels")
                .suggestFix("Consider flattening the dependency hierarchy or using facades")
                .severity(.warning)
                .build())
            }
        }

        return violations
    }

    private func assessLayerCompliance(sourceFile: SourceFile, ruleConfig: RuleSpecificConfiguration, layerValidator: LayerValidator, dependencyGraph: DependencyGraph, healthMetrics: inout ArchitecturalHealthMetrics) async -> [Violation] {
        var violations: [Violation] = []

        // Validate layering
        let layerViolations = layerValidator.validate(dependencyGraph)
        healthMetrics.layerViolations = layerViolations.count

        // Report layer violations with accurate locations
        let allowedViolations = ruleConfig.parameter("allowedLayerViolations", defaultValue: 0)
        if layerViolations.count > allowedViolations {
            for violation in layerViolations {
                let severity = mapSeverityToDiagnostic(violation.severity)
                // Try to find the actual location of the violating type
                let violatingTypeName = extractTypeNameFromLayer(violation.fromLayer)
                let typeLocation = findTypeLocation(for: violatingTypeName, in: sourceFile)
                let location = sourceFile.location(for: typeLocation)

                let violationDiagnostic = ViolationBuilder(
                    ruleId: id,
                    category: .architecture,
                    location: location
                )
                .message("Layer violation: \(violation.fromLayer) -> \(violation.toLayer) using \(violation.dependencyType.rawValue)")
                .suggestFix("Follow architectural layering principles - consider dependency inversion")
                .severity(severity)
                .build()

                violations.append(violationDiagnostic)
            }
        }

        return violations
    }

    private func assessStructuralHealth(sourceFile: SourceFile, ruleConfig: RuleSpecificConfiguration, healthMetrics: inout ArchitecturalHealthMetrics) -> [Violation] {
        var violations: [Violation] = []

        let source = sourceFile.source()
        let lineCount = source.components(separatedBy: .newlines).count
        healthMetrics.lineCount = lineCount

        // Check file length with strategic location
        let maxLines = ruleConfig.parameter("maxFileLines", defaultValue: 500)
        if lineCount > maxLines {
            // Position the warning at the middle of the file for visibility
            let source = sourceFile.source()
            let lines = source.components(separatedBy: .newlines)
            let midLine = max(0, lines.count / 2)

            var utf8Offset = 0
            for i in 0..<midLine {
                utf8Offset += lines[i].utf8.count + 1
            }
            let fileLengthLocation = AbsolutePosition(utf8Offset: utf8Offset)

            violations.append(createViolation(
                sourceFile: sourceFile,
                message: "File too large: \(lineCount) lines (max: \(maxLines))",
                suggestion: "Consider splitting into smaller files",
                severity: .info,
                at: fileLengthLocation
            ))
        }

        return violations
    }

    private func generateHealthReport(sourceFile: SourceFile, ruleConfig: RuleSpecificConfiguration, healthMetrics: ArchitecturalHealthMetrics) -> [Violation] {
        var violations: [Violation] = []

        // Calculate health score
        let healthScore = calculateHealthScore(ruleConfig: ruleConfig, healthMetrics: healthMetrics)

        let minHealthScore = ruleConfig.parameter("minHealthScore", defaultValue: 70)
        if healthScore < minHealthScore {
            // Find a strategic location for the health score warning
            var healthScoreLocation = AbsolutePosition(utf8Offset: 0)

            // Try to find the most problematic type to highlight the issue
            if healthMetrics.godClassCount > 0 {
                // If there are God classes, we'll find the first one
                let source = sourceFile.source()
                let tree = Parser.parse(source: source)
                let finder = FindFirstTypeVisitor()
                finder.walk(tree)
                if let firstTypeLocation = finder.foundLocation {
                    healthScoreLocation = firstTypeLocation
                }
            } else if healthMetrics.cycleCount > 0 {
                // If there are cycles, use a default location in the middle of the file
                let source = sourceFile.source()
                let lines = source.components(separatedBy: .newlines)
                let midLine = max(0, lines.count / 2)
                var utf8Offset = 0
                for i in 0..<midLine {
                    utf8Offset += lines[i].utf8.count + 1
                }
                healthScoreLocation = AbsolutePosition(utf8Offset: utf8Offset)
            }

            let location = sourceFile.location(for: healthScoreLocation)

            let violation = ViolationBuilder(
                ruleId: id,
                category: .architecture,
                location: location
            )
            .message("Architectural health score: \(healthScore)/100 (below threshold of \(minHealthScore))")
            .suggestFix("Improve architectural design by addressing reported issues")
            .severity(.warning)
            .build()

            violations.append(violation)
        }

        return violations
    }

    private func calculateHealthScore(ruleConfig: RuleSpecificConfiguration, healthMetrics: ArchitecturalHealthMetrics) -> Int {
        var score = 100

        // Deduct points for each issue
        score -= healthMetrics.cycleCount * 20
        score -= Int(healthMetrics.layerViolations * 10)
        score -= healthMetrics.godClassCount * 15
        score -= Int(healthMetrics.highComplexityTypeRatio * 10)

        // Add points for good practices
        if healthMetrics.averageDependencyDepth < 3 {
            score += 5
        }
        if healthMetrics.averageTypeComplexity < 30 {
            score += 5
        }

        return max(0, score)
    }

    private func createViolation(
        sourceFile: SourceFile,
        message: String,
        suggestion: String,
        severity: DiagnosticSeverity,
        at location: AbsolutePosition? = nil
    ) -> Violation {
        let violationLocation = location.map { sourceFile.location(for: $0) } ?? sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
        return ViolationBuilder(
            ruleId: id,
            category: .architecture,
            location: violationLocation
        )
        .message(message)
        .suggestFix(suggestion)
        .severity(severity)
        .build()
    }

    private func extractTypeNameFromLayer(_ layerIdentifier: String) -> String {
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

    private func mapSeverityToDiagnostic(_ severity: DiagnosticSeverity) -> DiagnosticSeverity {
        return severity
    }

    // Note: Health metrics methods removed since metrics are now per-analysis for thread safety
}

/// Comprehensive architectural health metrics
public struct ArchitecturalHealthMetrics: Codable, Sendable {
    public var typeCount: Int = 0
    public var dependencyCount: Int = 0
    public var layerViolations: Int = 0
    public var cycleCount: Int = 0
    public var godClassCount: Int = 0
    public var highComplexityTypeRatio: Double = 0.0
    public var averageTypeComplexity: Int = 0
    public var averageDependencyDepth: Double = 0.0
    public var maxDependencyDepth: Int = 0
    public var lineCount: Int = 0

    /// Calculate overall health score (0-100)
    public var healthScore: Int {
        var score = 100

        score -= cycleCount * 20
        score -= layerViolations * 10
        score -= godClassCount * 15
        score -= Int(highComplexityTypeRatio * 10)

        if averageDependencyDepth < 3 { score += 5 }
        if averageTypeComplexity < 30 { score += 5 }

        return max(0, score)
    }

    /// Get health grade
    public var healthGrade: String {
        let score = healthScore
        switch score {
        case 90...100: return "A"
        case 80..<90: return "B"
        case 70..<80: return "C"
        case 60..<70: return "D"
        case 0..<60: return "F"
        default: return "?"
        }
    }

    /// Get health assessment description
    public var healthAssessment: String {
        switch healthGrade {
        case "A":
            return "Excellent architecture with minimal issues"
        case "B":
            return "Good architecture with minor improvements needed"
        case "C":
            return "Acceptable architecture but needs attention"
        case "D":
            return "Poor architecture requiring significant refactoring"
        case "F":
            return "Critical architectural issues requiring immediate action"
        default:
            return "Unable to assess"
        }
    }
}

/// Extension to create configurations for different analysis modes
extension ArchitecturalHealthRule {
    /// Create configuration for different analysis intensities
    public static func configuration(for analysisMode: AnalysisMode) -> RuleSpecificConfiguration {
        switch analysisMode {
        case .quick:
            return RuleSpecificConfiguration(
                ruleId: "architectural_health",
                enabled: true,
                severity: .info,
                parameters: [
                    "maxFileLines": .integerValue(1000),
                    "maxDependencyDepth": .integerValue(10),
                    "allowedLayerViolations": .integerValue(5),
                    "minHealthScore": .integerValue(50),
                    "allowCycles": .booleanValue(false)
                ]
            )

        case .standard:
            return RuleSpecificConfiguration(
                ruleId: "architectural_health",
                enabled: true,
                severity: .warning,
                parameters: [
                    "maxFileLines": .integerValue(500),
                    "maxDependencyDepth": .integerValue(5),
                    "allowedLayerViolations": .integerValue(2),
                    "minHealthScore": .integerValue(70),
                    "allowCycles": .booleanValue(false)
                ]
            )

        case .comprehensive:
            return RuleSpecificConfiguration(
                ruleId: "architectural_health",
                enabled: true,
                severity: .error,
                parameters: [
                    "maxFileLines": .integerValue(200),
                    "maxDependencyDepth": .integerValue(3),
                    "allowedLayerViolations": .integerValue(0),
                    "minHealthScore": .integerValue(85),
                    "allowCycles": .booleanValue(false),
                    "maxGodClasses": .integerValue(0)
                ]
            )
        }
    }
}

/// Analysis intensity modes
public enum AnalysisMode: String, CaseIterable {
    case quick = "quick"
    case standard = "standard"
    case comprehensive = "comprehensive"

    public var description: String {
        switch self {
        case .quick:
            return "Fast analysis with basic checks"
        case .standard:
            return "Balanced analysis with moderate depth"
        case .comprehensive:
            return "Thorough analysis with detailed reporting"
        }
    }
}