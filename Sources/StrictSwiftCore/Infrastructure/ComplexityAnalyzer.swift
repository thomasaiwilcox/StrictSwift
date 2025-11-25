import Foundation
import SwiftSyntax
import SwiftParser

/// Analyzes code complexity metrics including cyclomatic complexity, nesting depth, and size metrics
public final class ComplexityAnalyzer: Sendable {
    /// Complexity metrics for a code element
    public struct ComplexityMetrics: Codable, Sendable {
        public let cyclomaticComplexity: Int
        public let nestingDepth: Int
        public let lineCount: Int
        public let functionCount: Int
        public let propertyCount: Int
        public let typeCount: Int
        public let cognitiveComplexity: Int
        public let halsteadMetrics: HalsteadMetrics

        public init(
            cyclomaticComplexity: Int = 1,
            nestingDepth: Int = 0,
            lineCount: Int = 0,
            functionCount: Int = 0,
            propertyCount: Int = 0,
            typeCount: Int = 0,
            cognitiveComplexity: Int = 0,
            halsteadMetrics: HalsteadMetrics = HalsteadMetrics()
        ) {
            self.cyclomaticComplexity = cyclomaticComplexity
            self.nestingDepth = nestingDepth
            self.lineCount = lineCount
            self.functionCount = functionCount
            self.propertyCount = propertyCount
            self.typeCount = typeCount
            self.cognitiveComplexity = cognitiveComplexity
            self.halsteadMetrics = halsteadMetrics
        }
    }

    /// Halstead metrics for code complexity
    public struct HalsteadMetrics: Codable, Sendable {
        public let vocabulary: Int
        public let length: Int
        public let calculatedLength: Double
        public let volume: Double
        public let difficulty: Double
        public let effort: Double
        public let timeToProgram: Double
        public let bugsDelivered: Double

        public init(
            vocabulary: Int = 0,
            length: Int = 0,
            calculatedLength: Double = 0.0,
            volume: Double = 0.0,
            difficulty: Double = 0.0,
            effort: Double = 0.0,
            timeToProgram: Double = 0.0,
            bugsDelivered: Double = 0.0
        ) {
            self.vocabulary = vocabulary
            self.length = length
            self.calculatedLength = calculatedLength
            self.volume = volume
            self.difficulty = difficulty
            self.effort = effort
            self.timeToProgram = timeToProgram
            self.bugsDelivered = bugsDelivered
        }
    }

    /// Complexity analysis result
    public struct ComplexityResult: Sendable {
        public let fileMetrics: FileMetrics
        public let functionMetrics: [String: ComplexityMetrics]
        public let typeMetrics: [String: ComplexityMetrics]
        public let overallComplexity: ComplexityMetrics

        public init(
            fileMetrics: FileMetrics,
            functionMetrics: [String: ComplexityMetrics],
            typeMetrics: [String: ComplexityMetrics],
            overallComplexity: ComplexityMetrics
        ) {
            self.fileMetrics = fileMetrics
            self.functionMetrics = functionMetrics
            self.typeMetrics = typeMetrics
            self.overallComplexity = overallComplexity
        }
    }

    /// File-level complexity metrics
    public struct FileMetrics: Codable, Sendable {
        public let lineCount: Int
        public let functionCount: Int
        public let typeCount: Int
        public let averageFunctionComplexity: Double
        public let maxFunctionComplexity: Int
        public let averageNestingDepth: Double
        public let maxNestingDepth: Int

        public init(
            lineCount: Int,
            functionCount: Int,
            typeCount: Int,
            averageFunctionComplexity: Double,
            maxFunctionComplexity: Int,
            averageNestingDepth: Double,
            maxNestingDepth: Int
        ) {
            self.lineCount = lineCount
            self.functionCount = functionCount
            self.typeCount = typeCount
            self.averageFunctionComplexity = averageFunctionComplexity
            self.maxFunctionComplexity = maxFunctionComplexity
            self.averageNestingDepth = averageNestingDepth
            self.maxNestingDepth = maxNestingDepth
        }
    }

    /// Analysis options for customizing complexity calculation
    public struct AnalysisOptions: Sendable {
        public let includeComments: Bool
        public let countEmptyLines: Bool
        public let cognitiveComplexityEnabled: Bool
        public let halsteadMetricsEnabled: Bool
        public let maxNestingDepth: Int
        public let maxCyclomaticComplexity: Int
        public let maxFunctionLength: Int

        public init(
            includeComments: Bool = false,
            countEmptyLines: Bool = false,
            cognitiveComplexityEnabled: Bool = true,
            halsteadMetricsEnabled: Bool = true,
            maxNestingDepth: Int = 5,
            maxCyclomaticComplexity: Int = 10,
            maxFunctionLength: Int = 50
        ) {
            self.includeComments = includeComments
            self.countEmptyLines = countEmptyLines
            self.cognitiveComplexityEnabled = cognitiveComplexityEnabled
            self.halsteadMetricsEnabled = halsteadMetricsEnabled
            self.maxNestingDepth = maxNestingDepth
            self.maxCyclomaticComplexity = maxCyclomaticComplexity
            self.maxFunctionLength = maxFunctionLength
        }
    }

    private let options: AnalysisOptions

    public init(options: AnalysisOptions = AnalysisOptions()) {
        self.options = options
    }

    /// Analyze complexity of source files
    public func analyze(_ sourceFiles: [SourceFile]) -> [ComplexityResult] {
        return sourceFiles.map { analyze($0) }
    }

    /// Analyze complexity of a single source file
    public func analyze(_ sourceFile: SourceFile) -> ComplexityResult {
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)

        let analyzer = ComplexitySyntaxAnalyzer(options: options, sourceFile: sourceFile)
        analyzer.walk(tree)
        return analyzer.result
    }

    /// Get complexity for a specific function
    public func getFunctionComplexity(_ functionName: String, in sourceFile: SourceFile) -> ComplexityMetrics? {
        let result = analyze(sourceFile)
        return result.functionMetrics[functionName]
    }

    /// Get complexity for a specific type
    public func getTypeComplexity(_ typeName: String, in sourceFile: SourceFile) -> ComplexityMetrics? {
        let result = analyze(sourceFile)
        return result.typeMetrics[typeName]
    }

    /// Check if complexity exceeds thresholds
    public func exceedsThresholds(_ metrics: ComplexityMetrics) -> [String] {
        var violations: [String] = []

        if metrics.cyclomaticComplexity > options.maxCyclomaticComplexity {
            violations.append("Cyclomatic complexity \(metrics.cyclomaticComplexity) exceeds threshold of \(options.maxCyclomaticComplexity)")
        }

        if metrics.nestingDepth > options.maxNestingDepth {
            violations.append("Nesting depth \(metrics.nestingDepth) exceeds threshold of \(options.maxNestingDepth)")
        }

        if metrics.lineCount > options.maxFunctionLength {
            violations.append("Function length \(metrics.lineCount) lines exceeds threshold of \(options.maxFunctionLength)")
        }

        return violations
    }
}

/// Syntax visitor for analyzing code complexity
private class ComplexitySyntaxAnalyzer: SyntaxAnyVisitor {
    private let options: ComplexityAnalyzer.AnalysisOptions
    private let sourceFile: SourceFile

    private var functionMetrics: [String: ComplexityAnalyzer.ComplexityMetrics] = [:]
    private var typeMetrics: [String: ComplexityAnalyzer.ComplexityMetrics] = [:]
    private var currentFunction: String?
    private var currentType: String?
    private var currentNestingDepth: Int = 0
    private var currentCyclomaticComplexity: Int = 1
    private var currentCognitiveComplexity: Int = 0
    private var currentLineCount: Int = 0
    private var currentFunctionCount: Int = 0
    private var currentPropertyCount: Int = 0
    private var currentTypeCount: Int = 0
    private var functionLineNumbers: [String: (start: Int, end: Int)] = [:]

    init(options: ComplexityAnalyzer.AnalysisOptions, sourceFile: SourceFile) {
        self.options = options
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    var result: ComplexityAnalyzer.ComplexityResult {
        let fileMetrics = calculateFileMetrics()
        let overallComplexity = calculateOverallComplexity(fileMetrics: fileMetrics)

        return ComplexityAnalyzer.ComplexityResult(
            fileMetrics: fileMetrics,
            functionMetrics: functionMetrics,
            typeMetrics: typeMetrics,
            overallComplexity: overallComplexity
        )
    }

    // MARK: - Type Declarations

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.name.text
        currentType = typeName
        currentTypeCount += 1

        let startLine = getLineNumber(node.position)
        let analyzer = TypeComplexityAnalyzer(
            options: options,
            startLine: startLine
        )
        analyzer.walk(node)

        typeMetrics[typeName] = analyzer.metrics

        // Continue analyzing children
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        currentType = nil
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.name.text
        currentType = typeName
        currentTypeCount += 1

        let startLine = getLineNumber(node.position)
        let analyzer = TypeComplexityAnalyzer(
            options: options,
            startLine: startLine
        )
        analyzer.walk(node)

        typeMetrics[typeName] = analyzer.metrics

        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        currentType = nil
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.name.text
        currentType = typeName
        currentTypeCount += 1

        let startLine = getLineNumber(node.position)
        let analyzer = TypeComplexityAnalyzer(
            options: options,
            startLine: startLine
        )
        analyzer.walk(node)

        typeMetrics[typeName] = analyzer.metrics

        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        currentType = nil
    }

    // MARK: - Function Declarations

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let functionName = node.name.text
        currentFunction = functionName
        currentFunctionCount += 1

        let startLine = getLineNumber(node.position)
        let analyzer = FunctionComplexityAnalyzer(
            options: options,
            startLine: startLine,
            sourceFile: sourceFile
        )
        analyzer.walk(node)

        functionMetrics[functionName] = analyzer.metrics
        functionLineNumbers[functionName] = (start: startLine, end: analyzer.endLine)

        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        currentFunction = nil
    }

    // MARK: - Variable Declarations

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        currentPropertyCount += 1
        return .skipChildren
    }

    // MARK: - Helper Methods

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

    private func calculateFileMetrics() -> ComplexityAnalyzer.FileMetrics {
        let source = sourceFile.source()
        let lineCount = countLines(source)

        let complexities = functionMetrics.values.map { $0.cyclomaticComplexity }
        let averageFunctionComplexity = complexities.isEmpty ? 0.0 : Double(complexities.reduce(0, +)) / Double(complexities.count)
        let maxFunctionComplexity = complexities.max() ?? 0

        let nestingDepths = functionMetrics.values.map { $0.nestingDepth }
        let averageNestingDepth = nestingDepths.isEmpty ? 0.0 : Double(nestingDepths.reduce(0, +)) / Double(nestingDepths.count)
        let maxNestingDepth = nestingDepths.max() ?? 0

        return ComplexityAnalyzer.FileMetrics(
            lineCount: lineCount,
            functionCount: currentFunctionCount,
            typeCount: currentTypeCount,
            averageFunctionComplexity: averageFunctionComplexity,
            maxFunctionComplexity: maxFunctionComplexity,
            averageNestingDepth: averageNestingDepth,
            maxNestingDepth: maxNestingDepth
        )
    }

    private func calculateOverallComplexity(fileMetrics: ComplexityAnalyzer.FileMetrics) -> ComplexityAnalyzer.ComplexityMetrics {
        let complexities = functionMetrics.values
        let maxCyclomatic = complexities.map { $0.cyclomaticComplexity }.max() ?? 1
        let maxNesting = complexities.map { $0.nestingDepth }.max() ?? 0

        return ComplexityAnalyzer.ComplexityMetrics(
            cyclomaticComplexity: maxCyclomatic,
            nestingDepth: maxNesting,
            lineCount: fileMetrics.lineCount,
            functionCount: fileMetrics.functionCount,
            propertyCount: currentPropertyCount,
            typeCount: fileMetrics.typeCount,
            cognitiveComplexity: complexities.reduce(0) { $0 + $1.cognitiveComplexity }
        )
    }

    private func countLines(_ source: String) -> Int {
        if options.countEmptyLines {
            return source.components(separatedBy: .newlines).count
        } else {
            return source.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        }
    }
}

/// Specialized analyzer for function complexity
private class FunctionComplexityAnalyzer: SyntaxAnyVisitor {
    private let options: ComplexityAnalyzer.AnalysisOptions
    private let startLine: Int
    private let sourceFile: SourceFile

    private var cyclomaticComplexity: Int = 1
    private var nestingDepth: Int = 0
    private var cognitiveComplexity: Int = 0
    private var lineCount: Int = 1
    var endLine: Int = 1

    private var nestingIncrementers: Int = 0
    private var cognitiveNestingDepth: Int = 0

    init(options: ComplexityAnalyzer.AnalysisOptions, startLine: Int, sourceFile: SourceFile) {
        self.options = options
        self.startLine = startLine
        self.sourceFile = sourceFile
        self.endLine = startLine
        super.init(viewMode: .sourceAccurate)
    }

    var metrics: ComplexityAnalyzer.ComplexityMetrics {
        return ComplexityAnalyzer.ComplexityMetrics(
            cyclomaticComplexity: cyclomaticComplexity,
            nestingDepth: nestingDepth,
            lineCount: lineCount,
            cognitiveComplexity: cognitiveComplexity,
            halsteadMetrics: ComplexityAnalyzer.HalsteadMetrics()
        )
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        updateLineMetrics(with: node.endPosition)
        return .visitChildren
    }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        cyclomaticComplexity += 1

        // Cognitive complexity tracking
        if options.cognitiveComplexityEnabled {
            cognitiveComplexity += 1 + cognitiveNestingDepth
            cognitiveNestingDepth += 1
        }

        nestingDepth = max(nestingDepth, nestingIncrementers + 1)
        nestingIncrementers += 1

        let result: SyntaxVisitorContinueKind = .visitChildren

        nestingIncrementers -= 1
        if options.cognitiveComplexityEnabled {
            cognitiveNestingDepth -= 1
        }

        return result
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        cyclomaticComplexity += 1

        if options.cognitiveComplexityEnabled {
            cognitiveComplexity += 1 + cognitiveNestingDepth
        }

        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        cyclomaticComplexity += 1

        if options.cognitiveComplexityEnabled {
            cognitiveComplexity += 1 + cognitiveNestingDepth
            cognitiveNestingDepth += 1
        }

        nestingDepth = max(nestingDepth, nestingIncrementers + 1)
        nestingIncrementers += 1

        let result: SyntaxVisitorContinueKind = .visitChildren

        nestingIncrementers -= 1
        if options.cognitiveComplexityEnabled {
            cognitiveNestingDepth -= 1
        }

        return result
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        cyclomaticComplexity += 1
        return .visitChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        cyclomaticComplexity += 1

        if options.cognitiveComplexityEnabled {
            cognitiveComplexity += 1 + cognitiveNestingDepth
            cognitiveNestingDepth += 1
        }

        nestingDepth = max(nestingDepth, nestingIncrementers + 1)
        nestingIncrementers += 1

        let result: SyntaxVisitorContinueKind = .visitChildren

        nestingIncrementers -= 1
        if options.cognitiveComplexityEnabled {
            cognitiveNestingDepth -= 1
        }

        return result
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        cyclomaticComplexity += 1

        if options.cognitiveComplexityEnabled {
            cognitiveComplexity += 1 + cognitiveNestingDepth
        }

        return .visitChildren
    }

    override func visit(_ node: SwitchCaseLabelSyntax) -> SyntaxVisitorContinueKind {
        cyclomaticComplexity += 1
        return .visitChildren
    }

    private func updateLineMetrics(with position: AbsolutePosition) {
        let newEnd = getLineNumber(position)
        endLine = max(endLine, newEnd)
        lineCount = max(lineCount, endLine - startLine + 1)
    }

    private func getLineNumber(_ position: AbsolutePosition) -> Int {
        let source = sourceFile.source()
        let lines = source.components(separatedBy: .newlines)
        var utf8Offset: Int = 0
        for (index, line) in lines.enumerated() {
            if utf8Offset + line.utf8.count >= position.utf8Offset {
                return index + 1
            }
            utf8Offset += line.utf8.count + 1
        }
        return lines.count
    }
}

/// Specialized analyzer for type complexity
private class TypeComplexityAnalyzer: SyntaxAnyVisitor {
    private let options: ComplexityAnalyzer.AnalysisOptions
    private let startLine: Int

    private var functionCount: Int = 0
    private var propertyCount: Int = 0

    init(options: ComplexityAnalyzer.AnalysisOptions, startLine: Int) {
        self.options = options
        self.startLine = startLine
        super.init(viewMode: .sourceAccurate)
    }

    var metrics: ComplexityAnalyzer.ComplexityMetrics {
        return ComplexityAnalyzer.ComplexityMetrics(
            functionCount: functionCount,
            propertyCount: propertyCount
        )
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        functionCount += 1
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        propertyCount += 1
        return .skipChildren
    }
}
