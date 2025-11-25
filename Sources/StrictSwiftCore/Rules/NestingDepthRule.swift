import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that analyzes and enforces maximum nesting depth in code
/// SAFETY: @unchecked Sendable is safe because complexityAnalyzer is itself Sendable
/// and is only initialized once in init() - no mutable state after construction.
public final class NestingDepthRule: Rule, @unchecked Sendable {
    public var id: String { "nesting_depth" }
    public var name: String { "Nesting Depth" }
    public var description: String { "Detects and flags excessive control flow nesting that reduces code readability" }
    public var category: RuleCategory { .complexity }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    // Infrastructure components for thread safety
    private let complexityAnalyzer: ComplexityAnalyzer

    public init() {
        let options = ComplexityAnalyzer.AnalysisOptions(
            maxNestingDepth: 5,
            maxCyclomaticComplexity: 20,
            maxFunctionLength: 100
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
        let maxNestingDepth = ruleConfig.parameter("maxNestingDepth", defaultValue: 5)
        let excludeTestFunctions = ruleConfig.parameter("excludeTestFunctions", defaultValue: true)
        let countClosureNesting = ruleConfig.parameter("countClosureNesting", defaultValue: true)
        let countSwitchCases = ruleConfig.parameter("countSwitchCases", defaultValue: false)

        // Create analyzer with updated options
        let options = ComplexityAnalyzer.AnalysisOptions(
            countEmptyLines: false,
            cognitiveComplexityEnabled: true,
            maxNestingDepth: maxNestingDepth
        )

        let analyzer = ComplexityAnalyzer(options: options)
        let result = analyzer.analyze(sourceFile)

        // Perform detailed nesting analysis
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)
        let nestingAnalyzer = DetailedNestingAnalyzer(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            maxNestingDepth: maxNestingDepth,
            excludeTestFunctions: excludeTestFunctions,
            countClosureNesting: countClosureNesting,
            countSwitchCases: countSwitchCases
        )
        nestingAnalyzer.walk(tree)

        violations.append(contentsOf: nestingAnalyzer.violations)

        for (functionName, metrics) in result.functionMetrics where metrics.nestingDepth > maxNestingDepth {
            let location = sourceFile.locationOfFunction(named: functionName) ?? sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
            let violation = ViolationBuilder(
                ruleId: id,
                category: .complexity,
                location: location
            )
            .message("Function '\(functionName)' has nesting depth of \(metrics.nestingDepth) (threshold: \(maxNestingDepth))")
            .suggestFix("Reduce nested control flow or extract helper methods to simplify")
            .severity(ruleConfig.severity)
            .build()

            violations.append(violation)
        }

        // Add file-level violations from complexity analysis
        violations.append(contentsOf: analyzeFileNesting(
            result: result,
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            maxNestingDepth: maxNestingDepth
        ))

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }

    // MARK: - Helper Methods

    private func analyzeFileNesting(
        result: ComplexityAnalyzer.ComplexityResult,
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration,
        maxNestingDepth: Int
    ) -> [Violation] {
        var violations: [Violation] = []

        // Check for excessive average nesting
        let maxAverageNesting = ruleConfig.parameter("maxAverageNesting", defaultValue: 3.0)
        if result.fileMetrics.averageNestingDepth > maxAverageNesting {
            let location = sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
            let violation = ViolationBuilder(
                ruleId: id,
                category: .complexity,
                location: location
            )
            .message("File has average nesting depth of \(String(format: "%.1f", result.fileMetrics.averageNestingDepth)) (threshold: \(maxAverageNesting))")
            .suggestFix("Consider restructuring functions to reduce overall nesting")
            .severity(ruleConfig.severity)
            .build()

            violations.append(violation)
        }

        // Check for maximum nesting violations
        if result.fileMetrics.maxNestingDepth > maxNestingDepth {
            let location = sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
            let violation = ViolationBuilder(
                ruleId: id,
                category: .complexity,
                location: location
            )
            .message("File contains nesting depth of \(result.fileMetrics.maxNestingDepth) (threshold: \(maxNestingDepth))")
            .suggestFix("Extract deeply nested code into separate functions or use early returns")
            .severity(ruleConfig.severity)
            .build()

            violations.append(violation)
        }

        return violations
    }
}

/// Detailed syntax analyzer for nesting depth violations
private class DetailedNestingAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let ruleConfig: RuleSpecificConfiguration
    private let maxNestingDepth: Int
    private let excludeTestFunctions: Bool
    private let countClosureNesting: Bool
    private let countSwitchCases: Bool

    var violations: [Violation] = []
    private var currentFunction: String?
    private var currentNestingDepth: Int = 0
    private var nestingStack: [(type: NestingType, depth: Int, location: AbsolutePosition)] = []
    private var maxDepthReached: Int = 0

    init(sourceFile: SourceFile,
         ruleConfig: RuleSpecificConfiguration,
         maxNestingDepth: Int,
         excludeTestFunctions: Bool,
         countClosureNesting: Bool,
         countSwitchCases: Bool) {
        self.sourceFile = sourceFile
        self.ruleConfig = ruleConfig
        self.maxNestingDepth = maxNestingDepth
        self.excludeTestFunctions = excludeTestFunctions
        self.countClosureNesting = countClosureNesting
        self.countSwitchCases = countSwitchCases
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Function Tracking

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let functionName = node.name.text

        if shouldSkipFunction(functionName) {
            return .skipChildren
        }

        currentFunction = functionName
        currentNestingDepth = 0
        nestingStack.removeAll()
        maxDepthReached = 0

        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        checkFunctionCompletion()
        currentFunction = nil
    }

    // MARK: - Control Flow Structures

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        enterNesting(.ifStatement, location: node.position)
        return .visitChildren
    }

    override func visitPost(_ node: IfExprSyntax) {
        exitNesting(.ifStatement)
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        // Guard statements don't typically increase nesting depth for the else block
        // but we track them for analysis
        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        enterNesting(.whileLoop, location: node.position)
        return .visitChildren
    }

    override func visitPost(_ node: WhileStmtSyntax) {
        exitNesting(.whileLoop)
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        enterNesting(.repeatLoop, location: node.position)
        return .visitChildren
    }

    override func visitPost(_ node: RepeatStmtSyntax) {
        exitNesting(.repeatLoop)
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        enterNesting(.forLoop, location: node.position)
        return .visitChildren
    }

    override func visitPost(_ node: ForStmtSyntax) {
        exitNesting(.forLoop)
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        if countSwitchCases {
            enterNesting(.switchCase, location: node.position)
        }
        return .visitChildren
    }

    override func visitPost(_ node: SwitchCaseSyntax) {
        if countSwitchCases {
            exitNesting(.switchCase)
        }
    }

    // MARK: - Closure Nesting

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if countClosureNesting {
            enterNesting(.closure, location: node.position)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        if countClosureNesting {
            exitNesting(.closure)
        }
    }

    override func visit(_ node: ClosureCaptureClauseSyntax) -> SyntaxVisitorContinueKind {
        // Analyze capture list for complexity
        if node.items.count > 3 {
            let location = sourceFile.location(of: node)
            let violation = ViolationBuilder(
                ruleId: "nesting_depth",
                category: .complexity,
                location: location
            )
            .message("Closure captures \(node.items.count) variables, consider reducing complexity")
            .suggestFix("Extract complex closure into a named function")
            .severity(.info)
            .build()

            violations.append(violation)
        }

        return .visitChildren
    }

    // MARK: - Ternary Operator

    override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        // Ternary operators can add cognitive complexity
        if currentNestingDepth >= maxNestingDepth - 1 {
            let location = sourceFile.location(of: node)
            let violation = ViolationBuilder(
                ruleId: "nesting_depth",
                category: .complexity,
                location: location
            )
            .message("Ternary operator at nesting level \(currentNestingDepth + 1) may reduce readability")
            .suggestFix("Consider using if-else statement for clarity")
            .severity(.info)
            .build()

            violations.append(violation)
        }

        return .visitChildren
    }

    // MARK: - Helper Methods

    private func shouldSkipFunction(_ functionName: String) -> Bool {
        if excludeTestFunctions && (functionName.hasPrefix("test") || functionName.contains("Test")) {
            return true
        }
        return false
    }

    private func enterNesting(_ type: NestingType, location: AbsolutePosition) {
        currentNestingDepth += 1
        maxDepthReached = max(maxDepthReached, currentNestingDepth)
        nestingStack.append((type: type, depth: currentNestingDepth, location: location))

        if currentNestingDepth > maxNestingDepth {
            createNestingViolation(type: type, depth: currentNestingDepth, location: location)
        }
    }

    private func exitNesting(_ type: NestingType) {
        if let last = nestingStack.last, last.type == type {
            nestingStack.removeLast()
        }
        currentNestingDepth = nestingStack.last?.depth ?? 0
    }

    private func createNestingViolation(type: NestingType, depth: Int, location: AbsolutePosition) {
        let locationInfo = sourceFile.location(for: location)
        let violation = ViolationBuilder(
            ruleId: "nesting_depth",
            category: .complexity,
            location: locationInfo
        )
        .message("Excessive nesting: \(type.description) at level \(depth) (threshold: \(maxNestingDepth))")
        .suggestFix(suggestReduction(type: type, depth: depth, functionName: currentFunction))
        .severity(ruleConfig.severity)
        .build()

        violations.append(violation)
    }

    private func checkFunctionCompletion() {
        if let functionName = currentFunction {
            if maxDepthReached > maxNestingDepth {
                // Create summary violation for the function
                let location = sourceFile.locationOfFunction(named: functionName) ??
                    sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
                let violation = ViolationBuilder(
                    ruleId: "nesting_depth",
                    category: .complexity,
                    location: location
                )
                .message("Function '\(functionName)' has maximum nesting depth of \(maxDepthReached) (threshold: \(maxNestingDepth))")
                .suggestFix("Consider refactoring to reduce overall nesting complexity")
                .severity(ruleConfig.severity)
                .build()

                violations.append(violation)
            }
        }
    }

    private func suggestReduction(type: NestingType, depth: Int, functionName: String?) -> String {
        var suggestions: [String] = []

        switch type {
        case .ifStatement:
            suggestions.append("Use early returns to reduce if-else nesting")
            suggestions.append("Extract complex conditions into separate functions")
        case .forLoop, .whileLoop, .repeatLoop:
            suggestions.append("Extract loop body into separate function")
            suggestions.append("Consider using higher-order functions like map/filter")
        case .switchCase:
            suggestions.append("Extract case logic into separate methods")
            suggestions.append("Consider using polymorphism instead of large switch statements")
        case .closure:
            suggestions.append("Extract closure into named function")
            suggestions.append("Simplify capture list")
        }

        if let functionName = functionName, depth > maxNestingDepth + 2 {
            suggestions.append("Consider breaking '\(functionName)' into smaller functions")
        }

        return suggestions.joined(separator: "; ")
    }
}

/// Types of nesting that can occur in Swift code
private enum NestingType {
    case ifStatement
    case whileLoop
    case repeatLoop
    case forLoop
    case switchCase
    case closure

    var description: String {
        switch self {
        case .ifStatement:
            return "if statement"
        case .whileLoop:
            return "while loop"
        case .repeatLoop:
            return "repeat loop"
        case .forLoop:
            return "for loop"
        case .switchCase:
            return "switch case"
        case .closure:
            return "closure"
        }
    }
}
