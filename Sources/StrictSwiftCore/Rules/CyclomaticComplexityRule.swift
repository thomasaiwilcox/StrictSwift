import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that analyzes cyclomatic complexity of functions and methods
/// SAFETY: @unchecked Sendable is safe because complexityAnalyzer is itself Sendable
/// and is only initialized once in init() - no mutable state after construction.
public final class CyclomaticComplexityRule: Rule, @unchecked Sendable {
    public var id: String { "cyclomatic_complexity" }
    public var name: String { "Cyclomatic Complexity" }
    public var description: String { "Analyzes cyclomatic complexity and flags overly complex functions" }
    public var category: RuleCategory { .complexity }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    // Infrastructure components for thread safety
    private let complexityAnalyzer: ComplexityAnalyzer

    public init() {
        let options = ComplexityAnalyzer.AnalysisOptions(
            maxNestingDepth: 5,
            maxCyclomaticComplexity: 10,
            maxFunctionLength: 50
        )
        self.complexityAnalyzer = ComplexityAnalyzer(options: options)
    }

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []

        // Get configuration
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }

        // Get configuration parameters
        let defaultMaxComplexity = ruleConfig.parameter("maxCyclomaticComplexity", defaultValue: 5)
        let maxComplexity = ruleConfig.parameter("maxComplexity", defaultValue: defaultMaxComplexity)
        let excludeTestFunctions = ruleConfig.parameter("excludeTestFunctions", defaultValue: true)
        let excludeGenerated = ruleConfig.parameter("excludeGenerated", defaultValue: true)
        let checkAccessors = ruleConfig.parameter("checkAccessors", defaultValue: false)
        let checkInitializers = ruleConfig.parameter("checkInitializers", defaultValue: true)
        let maxFileComplexity = ruleConfig.parameter("maxFileComplexity", defaultValue: maxComplexity * 2)

        // Create analyzer with updated options
        let options = ComplexityAnalyzer.AnalysisOptions(
            cognitiveComplexityEnabled: ruleConfig.parameter("cognitiveComplexityEnabled", defaultValue: true),
            halsteadMetricsEnabled: ruleConfig.parameter("halsteadMetricsEnabled", defaultValue: false),
            maxNestingDepth: ruleConfig.parameter("maxNestingDepth", defaultValue: 5),
            maxCyclomaticComplexity: maxComplexity,
            maxFunctionLength: ruleConfig.parameter("maxFunctionLength", defaultValue: 50)
        )

        let analyzer = ComplexityAnalyzer(options: options)
        let result = analyzer.analyze(sourceFile)

        // Analyze each function
        for (functionName, metrics) in result.functionMetrics {
            if shouldSkipFunction(functionName,
                                sourceFile: sourceFile,
                                excludeTestFunctions: excludeTestFunctions,
                                excludeGenerated: excludeGenerated,
                                checkAccessors: checkAccessors,
                                checkInitializers: checkInitializers) {
                continue
            }

            let violationsForFunction = analyzeFunction(
                name: functionName,
                metrics: metrics,
                sourceFile: sourceFile,
                ruleConfig: ruleConfig,
                maxComplexity: maxComplexity
            )

            violations.append(contentsOf: violationsForFunction)
        }

        // Analyze overall file complexity
        violations.append(contentsOf: analyzeFileComplexity(
            result: result,
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            maxComplexity: maxComplexity,
            maxFileComplexity: maxFileComplexity
        ))

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }

    // MARK: - Helper Methods

    private func shouldSkipFunction(
        _ functionName: String,
        sourceFile: SourceFile,
        excludeTestFunctions: Bool,
        excludeGenerated: Bool,
        checkAccessors: Bool,
        checkInitializers: Bool
    ) -> Bool {
        // Skip test functions
        if excludeTestFunctions && (functionName.hasPrefix("test") || functionName.contains("Test")) {
            return true
        }

        // Skip generated code
        if excludeGenerated && sourceFile.url.path.contains(".generated.") {
            return true
        }

        // Skip accessors if not checking them
        if !checkAccessors && (functionName.hasPrefix("get") || functionName.hasPrefix("set") || functionName.hasPrefix("willSet") || functionName.hasPrefix("didSet")) {
            return true
        }

        // Skip initializers if not checking them
        if !checkInitializers && (functionName.hasPrefix("init") || functionName.hasPrefix("deinit")) {
            return true
        }

        return false
    }

    private func analyzeFunction(
        name: String,
        metrics: ComplexityAnalyzer.ComplexityMetrics,
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration,
        maxComplexity: Int
    ) -> [Violation] {
        var violations: [Violation] = []

        // Check cyclomatic complexity
        if metrics.cyclomaticComplexity > maxComplexity {
            let location = findFunctionLocation(name: name, in: sourceFile)
            let violation = ViolationBuilder(
                ruleId: id,
                category: .complexity,
                location: location
            )
            .message("Function '\(name)' has cyclomatic complexity of \(metrics.cyclomaticComplexity) (threshold: \(maxComplexity))")
            .suggestFix(simplifyComplexitySuggestion(metrics: metrics, functionName: name))
            .severity(ruleConfig.severity)
            .build()

            violations.append(violation)
        }

        // Check for nested complexity
        let maxNestingDepth = ruleConfig.parameter("maxNestingDepth", defaultValue: 5)
        if metrics.nestingDepth > maxNestingDepth {
            let location = findFunctionLocation(name: name, in: sourceFile)
            let violation = ViolationBuilder(
                ruleId: id,
                category: .complexity,
                location: location
            )
            .message("Function '\(name)' has nesting depth of \(metrics.nestingDepth) (threshold: \(maxNestingDepth))")
            .suggestFix("Reduce nesting by extracting functions or using early returns")
            .severity(.info)
            .build()

            violations.append(violation)
        }

        // Check function length
        let maxFunctionLength = ruleConfig.parameter("maxFunctionLength", defaultValue: 50)
        if metrics.lineCount > maxFunctionLength {
            let location = findFunctionLocation(name: name, in: sourceFile)
            let violation = ViolationBuilder(
                ruleId: id,
                category: .complexity,
                location: location
            )
            .message("Function '\(name)' is \(metrics.lineCount) lines long (threshold: \(maxFunctionLength))")
            .suggestFix("Break down into smaller functions or extract common logic")
            .severity(.info)
            .build()

            violations.append(violation)
        }

        // Check cognitive complexity if enabled
        if ruleConfig.parameter("cognitiveComplexityEnabled", defaultValue: true) {
            let maxCognitiveComplexity = ruleConfig.parameter("maxCognitiveComplexity", defaultValue: 15)
            if metrics.cognitiveComplexity > maxCognitiveComplexity {
                let location = findFunctionLocation(name: name, in: sourceFile)
                let violation = ViolationBuilder(
                    ruleId: id,
                    category: .complexity,
                    location: location
                )
                .message("Function '\(name)' has cognitive complexity of \(metrics.cognitiveComplexity) (threshold: \(maxCognitiveComplexity))")
                .suggestFix("Simplify control flow and reduce nesting to improve readability")
                .severity(.info)
                .build()

                violations.append(violation)
            }
        }

        return violations
    }

    private func analyzeFileComplexity(
        result: ComplexityAnalyzer.ComplexityResult,
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration,
        maxComplexity: Int,
        maxFileComplexity: Int
    ) -> [Violation] {
        var violations: [Violation] = []

        // Check for overly complex file
        let maxAverageComplexity = ruleConfig.parameter("maxAverageComplexity", defaultValue: 7.0)
        if result.fileMetrics.averageFunctionComplexity > maxAverageComplexity {
            let location = sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
            let violation = ViolationBuilder(
                ruleId: id,
                category: .complexity,
                location: location
            )
            .message("File has average function complexity of \(String(format: "%.1f", result.fileMetrics.averageFunctionComplexity)) (threshold: \(maxAverageComplexity))")
            .suggestFix("Consider refactoring complex functions or splitting the file")
            .severity(ruleConfig.severity)
            .build()

            violations.append(violation)
        }

        // Check for too many functions
        let maxFunctions = ruleConfig.parameter("maxFunctionsPerFile", defaultValue: 20)
        if result.fileMetrics.functionCount > maxFunctions {
            let location = sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
            let violation = ViolationBuilder(
                ruleId: id,
                category: .complexity,
                location: location
            )
            .message("File contains \(result.fileMetrics.functionCount) functions (threshold: \(maxFunctions))")
            .suggestFix("Consider splitting into multiple files or organizing into classes/structs")
            .severity(.info)
            .build()

            violations.append(violation)
        }

        if result.overallComplexity.cyclomaticComplexity > maxFileComplexity {
            let location = sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
            let violation = ViolationBuilder(
                ruleId: id,
                category: .complexity,
                location: location
            )
            .message("File cyclomatic complexity is \(result.overallComplexity.cyclomaticComplexity) (threshold: \(maxFileComplexity))")
            .suggestFix("Break up complex functions or move logic into dedicated components")
            .severity(ruleConfig.severity)
            .build()

            violations.append(violation)
        }

        return violations
    }

    private func findFunctionLocation(name: String, in sourceFile: SourceFile) -> Location {
        if let location = sourceFile.locationOfFunction(named: name) {
            return location
        }

        return sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
    }

    private func simplifyComplexitySuggestion(metrics: ComplexityAnalyzer.ComplexityMetrics, functionName: String) -> String {
        var suggestions: [String] = []

        if metrics.cyclomaticComplexity > 15 {
            suggestions.append("Extract complex conditions into separate functions")
        }

        if metrics.nestingDepth > 3 {
            suggestions.append("Use early returns to reduce nesting")
        }

        if metrics.lineCount > 100 {
            suggestions.append("Break down into multiple smaller functions")
        }

        if suggestions.isEmpty {
            return "Consider simplifying the logic or extracting helper functions"
        }

        return suggestions.joined(separator: "; ")
    }
}
