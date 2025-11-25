import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that analyzes and enforces maximum function length
/// SAFETY: @unchecked Sendable is safe because complexityAnalyzer is itself Sendable
/// and is only initialized once in init() - no mutable state after construction.
public final class FunctionLengthRule: Rule, @unchecked Sendable {
    public var id: String { "function_length" }
    public var name: String { "Function Length" }
    public var description: String { "Detects and flags overly long functions that reduce maintainability" }
    public var category: RuleCategory { .complexity }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    // Infrastructure components for thread safety
    private let complexityAnalyzer: ComplexityAnalyzer

    public init() {
        let options = ComplexityAnalyzer.AnalysisOptions(
            includeComments: false,
            countEmptyLines: false,
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
        let maxFunctionLength = ruleConfig.parameter("maxFunctionLength", defaultValue: 50)
        let excludeTestFunctions = ruleConfig.parameter("excludeTestFunctions", defaultValue: true)
        let excludeGenerated = ruleConfig.parameter("excludeGenerated", defaultValue: true)
        let excludeComments = ruleConfig.parameter("excludeComments", defaultValue: true)
        let excludeEmptyLines = ruleConfig.parameter("excludeEmptyLines", defaultValue: true)
        let checkAccessors = ruleConfig.parameter("checkAccessors", defaultValue: false)
        let checkInitializers = ruleConfig.parameter("checkInitializers", defaultValue: true)

        // Perform detailed function length analysis
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)
        let lengthAnalyzer = DetailedLengthAnalyzer(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            maxFunctionLength: maxFunctionLength,
            excludeTestFunctions: excludeTestFunctions,
            excludeGenerated: excludeGenerated,
            excludeComments: excludeComments,
            excludeEmptyLines: excludeEmptyLines,
            checkAccessors: checkAccessors,
            checkInitializers: checkInitializers
        )
        lengthAnalyzer.walk(tree)

        violations.append(contentsOf: lengthAnalyzer.violations)

        let lengthOptions = ComplexityAnalyzer.AnalysisOptions(
            includeComments: !excludeComments,
            countEmptyLines: !excludeEmptyLines,
            maxFunctionLength: maxFunctionLength
        )
        let analyzer = ComplexityAnalyzer(options: lengthOptions)
        let result = analyzer.analyze(sourceFile)

        for (functionName, metrics) in result.functionMetrics where metrics.lineCount > maxFunctionLength {
            let location = sourceFile.locationOfFunction(named: functionName) ?? sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
            let violation = ViolationBuilder(
                ruleId: id,
                category: .complexity,
                location: location
            )
            .message("Function '\(functionName)' is \(metrics.lineCount) lines long (threshold: \(maxFunctionLength))")
            .suggestFix("Break the function into smaller units or extract helper methods")
            .severity(ruleConfig.severity)
            .build()

            violations.append(violation)
        }

        // Add file-level analysis
        violations.append(contentsOf: analyzeFileLength(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            maxFunctionLength: maxFunctionLength
        ))

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }

    // MARK: - Helper Methods

    private func analyzeFileLength(
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration,
        maxFunctionLength: Int
    ) -> [Violation] {
        var violations: [Violation] = []

        let source = sourceFile.source()
        let lineCount = countLines(source)

        let maxFileLength = ruleConfig.parameter("maxFileLength", defaultValue: 500)
        if lineCount > maxFileLength {
            let location = sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
            let violation = ViolationBuilder(
                ruleId: "function_length",
                category: .complexity,
                location: location
            )
            .message("File is \(lineCount) lines long (threshold: \(maxFileLength))")
            .suggestFix("Consider splitting into multiple files")
            .severity(.info)
            .build()

            violations.append(violation)
        }

        return violations
    }

    private func countLines(_ source: String) -> Int {
        return source.components(separatedBy: .newlines).count
    }
}

/// Detailed syntax analyzer for function length violations
private class DetailedLengthAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let ruleConfig: RuleSpecificConfiguration
    private let maxFunctionLength: Int
    private let excludeTestFunctions: Bool
    private let excludeGenerated: Bool
    private let excludeComments: Bool
    private let excludeEmptyLines: Bool
    private let checkAccessors: Bool
    private let checkInitializers: Bool

    var violations: [Violation] = []
    private var functionLengths: [String: FunctionLengthInfo] = [:]

    init(sourceFile: SourceFile,
         ruleConfig: RuleSpecificConfiguration,
         maxFunctionLength: Int,
         excludeTestFunctions: Bool,
         excludeGenerated: Bool,
         excludeComments: Bool,
         excludeEmptyLines: Bool,
         checkAccessors: Bool,
         checkInitializers: Bool) {
        self.sourceFile = sourceFile
        self.ruleConfig = ruleConfig
        self.maxFunctionLength = maxFunctionLength
        self.excludeTestFunctions = excludeTestFunctions
        self.excludeGenerated = excludeGenerated
        self.excludeComments = excludeComments
        self.excludeEmptyLines = excludeEmptyLines
        self.checkAccessors = checkAccessors
        self.checkInitializers = checkInitializers
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Function Declarations

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let functionName = node.name.text

        if shouldSkipFunction(functionName) {
            return .skipChildren
        }

        let startLine = getLineNumber(node.position)
        let lengthInfo = analyzeFunctionLength(node, functionName: functionName, startLine: startLine)
        functionLengths[functionName] = lengthInfo

        if lengthInfo.effectiveLength > maxFunctionLength {
            createFunctionLengthViolation(
                name: functionName,
                lengthInfo: lengthInfo,
                location: node.position
            )
        }

        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if !checkInitializers {
            return .skipChildren
        }

        let functionName = "init"
        let startLine = getLineNumber(node.position)
        let lengthInfo = analyzeFunctionLength(node, functionName: functionName, startLine: startLine)
        functionLengths[functionName] = lengthInfo

        if lengthInfo.effectiveLength > maxFunctionLength {
            createFunctionLengthViolation(
                name: functionName,
                lengthInfo: lengthInfo,
                location: node.position
            )
        }

        return .visitChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if !checkInitializers {
            return .skipChildren
        }

        let functionName = "deinit"
        let startLine = getLineNumber(node.position)
        let lengthInfo = analyzeFunctionLength(node, functionName: functionName, startLine: startLine)
        functionLengths[functionName] = lengthInfo

        if lengthInfo.effectiveLength > maxFunctionLength {
            createFunctionLengthViolation(
                name: functionName,
                lengthInfo: lengthInfo,
                location: node.position
            )
        }

        return .visitChildren
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        if !checkAccessors {
            return .skipChildren
        }

        let accessorType = node.accessorSpecifier.text
        let functionName = "\(accessorType) accessor"
        let startLine = getLineNumber(node.position)
        let lengthInfo = analyzeFunctionLength(node, functionName: functionName, startLine: startLine)
        functionLengths[functionName] = lengthInfo

        let maxAccessorLength = ruleConfig.parameter("maxAccessorLength", defaultValue: maxFunctionLength / 2)
        if lengthInfo.effectiveLength > maxAccessorLength {
            createAccessorLengthViolation(
                name: functionName,
                lengthInfo: lengthInfo,
                location: node.position,
                maxAccessorLength: maxAccessorLength
            )
        }

        return .visitChildren
    }

    // MARK: - Property Analysis

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for complex property initializers
        if let bindings = node.bindings.first {
            if let initializer = bindings.initializer {
                let propertyComplexity = analyzeInitializerComplexity(initializer.value)
                if propertyComplexity > ruleConfig.parameter("maxPropertyComplexity", defaultValue: 5) {
                    let location = sourceFile.location(of: node)
                    let violation = ViolationBuilder(
                        ruleId: "function_length",
                        category: .complexity,
                        location: location
                    )
                    .message("Property initializer has complexity \(propertyComplexity)")
                    .suggestFix("Extract property initialization to a separate method")
                    .severity(.info)
                    .build()

                    violations.append(violation)
                }
            }
        }

        return .skipChildren
    }

    // MARK: - Helper Methods

    private func shouldSkipFunction(_ functionName: String) -> Bool {
        if excludeTestFunctions && (functionName.hasPrefix("test") || functionName.contains("Test")) {
            return true
        }
        return false
    }

    private func analyzeFunctionLength<T: DeclSyntaxProtocol>(
        _ node: T,
        functionName: String,
        startLine: Int
    ) -> FunctionLengthInfo {
        let source = sourceFile.source()
        let lines = source.components(separatedBy: .newlines)

        let functionStart = startLine - 1 // Convert to 0-based index
        var functionEnd = lines.count - 1

        // Find the end of the function - check different types that might have bodies
        if let functionDecl = node.as(FunctionDeclSyntax.self), let body = functionDecl.body {
            functionEnd = getLineNumber(body.endPosition) - 1
        } else if let initializerDecl = node.as(InitializerDeclSyntax.self), let body = initializerDecl.body {
            functionEnd = getLineNumber(body.endPosition) - 1
        } else if let deinitializerDecl = node.as(DeinitializerDeclSyntax.self), let body = deinitializerDecl.body {
            functionEnd = getLineNumber(body.endPosition) - 1
        } else if let accessorDecl = node.as(AccessorDeclSyntax.self), let body = accessorDecl.body {
            functionEnd = getLineNumber(body.endPosition) - 1
        }

        let totalLines = functionEnd - functionStart + 1
        let effectiveLines = calculateEffectiveLines(from: functionStart, to: functionEnd, in: lines)

        return FunctionLengthInfo(
            name: functionName,
            startLine: startLine,
            endLine: functionEnd + 1,
            totalLines: totalLines,
            effectiveLines: effectiveLines,
            complexity: estimateComplexity(node)
        )
    }

    private func calculateEffectiveLines(from start: Int, to end: Int, in lines: [String]) -> Int {
        var effectiveCount = 0

        for i in start...min(end, lines.count - 1) {
            let line = lines[i]

            if excludeEmptyLines && line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }

            if excludeComments && isCommentLine(line) {
                continue
            }

            effectiveCount += 1
        }

        return effectiveCount
    }

    private func isCommentLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*")
    }

    private func getLineNumber(_ position: AbsolutePosition) -> Int {
        let source = sourceFile.source()
        let lines = source.components(separatedBy: .newlines)
        var utf8Offset: Int = 0
        for (index, line) in lines.enumerated() {
            if utf8Offset + line.utf8.count >= position.utf8Offset {
                return index + 1
            }
            utf8Offset += line.utf8.count + 1 // +1 for newline
        }
        return lines.count
    }

    private func estimateComplexity<T: DeclSyntaxProtocol>(_ node: T) -> Int {
        let complexity = 1 // Base complexity

        // This is a simplified complexity estimation
        // In a real implementation, you would traverse the AST and count
        // decision points, loops, etc.

        return complexity
    }

    private func analyzeInitializerComplexity(_ expression: ExprSyntax) -> Int {
        // Simple heuristic for property initializer complexity
        var complexity = 1

        class ComplexityCounter: SyntaxAnyVisitor {
            var complexity: Int = 0

            init() {
                super.init(viewMode: .sourceAccurate)
            }

            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                complexity += 1
                return .visitChildren
            }

            override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
                complexity += 2
                return .visitChildren
            }

            override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
                complexity += 1
                return .visitChildren
            }
        }

        let counter = ComplexityCounter()
        counter.walk(expression)
        complexity += counter.complexity

        return complexity
    }

    private func createFunctionLengthViolation(
        name: String,
        lengthInfo: FunctionLengthInfo,
        location: AbsolutePosition
    ) {
        let locationInfo = sourceFile.location(for: location)
        let violation = ViolationBuilder(
            ruleId: "function_length",
            category: .complexity,
            location: locationInfo
        )
        .message("Function '\(name)' is \(lengthInfo.effectiveLength) lines long (threshold: \(maxFunctionLength))")
        .suggestFix(suggestReduction(lengthInfo: lengthInfo))
        .severity(ruleConfig.severity)
        .build()

        violations.append(violation)
    }

    private func createAccessorLengthViolation(
        name: String,
        lengthInfo: FunctionLengthInfo,
        location: AbsolutePosition,
        maxAccessorLength: Int
    ) {
        let locationInfo = sourceFile.location(for: location)
        let violation = ViolationBuilder(
            ruleId: "function_length",
            category: .complexity,
            location: locationInfo
        )
        .message("'\(name)' is \(lengthInfo.effectiveLength) lines long (threshold: \(maxAccessorLength))")
        .suggestFix("Extract complex accessor logic to a separate method")
        .severity(.info)
        .build()

        violations.append(violation)
    }

    private func suggestReduction(lengthInfo: FunctionLengthInfo) -> String {
        var suggestions: [String] = []

        if lengthInfo.effectiveLength > 100 {
            suggestions.append("Break into multiple smaller functions")
        } else if lengthInfo.effectiveLength > 50 {
            suggestions.append("Extract common logic into helper functions")
        }

        if Double(lengthInfo.effectiveLength) > Double(maxFunctionLength) * 1.5 {
            suggestions.append("Consider splitting into separate types or modules")
        }

        suggestions.append("Use early returns to reduce nesting")
        suggestions.append("Extract complex conditional logic into separate methods")

        return suggestions.joined(separator: "; ")
    }
}

/// Information about function length analysis
private struct FunctionLengthInfo {
    let name: String
    let startLine: Int
    let endLine: Int
    let totalLines: Int
    let effectiveLength: Int
    let complexity: Int

    init(name: String, startLine: Int, endLine: Int, totalLines: Int, effectiveLines: Int, complexity: Int) {
        self.name = name
        self.startLine = startLine
        self.endLine = endLine
        self.totalLines = totalLines
        self.effectiveLength = effectiveLines
        self.complexity = complexity
    }
}
