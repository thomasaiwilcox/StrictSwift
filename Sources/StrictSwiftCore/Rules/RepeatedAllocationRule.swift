import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that detects repeated allocations and performance anti-patterns
/// SAFETY: @unchecked Sendable is safe because allocationTracker is created in init()
/// and the analyze() method creates fresh analyzers per call for thread safety.
public final class RepeatedAllocationRule: Rule, @unchecked Sendable {
    public var id: String { "repeated_allocation" }
    public var name: String { "Repeated Allocation" }
    public var description: String { "Detects repeated allocations and performance anti-patterns that can impact performance" }
    public var category: RuleCategory { .performance }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    // Infrastructure components for thread safety
    private let allocationTracker: AllocationTracker

    public init() {
        self.allocationTracker = AllocationTracker()
    }

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []

        // Get configuration
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }

        // Get configuration parameters
        let maxLoopAllocations = ruleConfig.parameter("maxLoopAllocations", defaultValue: 3)
        let checkStringConcatenation = ruleConfig.parameter("checkStringConcatenation", defaultValue: true)
        let checkArrayGrowth = ruleConfig.parameter("checkArrayGrowth", defaultValue: true)
        let checkClosureAllocation = ruleConfig.parameter("checkClosureAllocation", defaultValue: true)
        let performanceThreshold = ruleConfig.parameter("performanceThreshold", defaultValue: "medium")

        // Perform allocation analysis
        let analysisResult = allocationTracker.analyze(sourceFile)

        // Convert analysis recommendations to violations
        violations.append(contentsOf: convertRecommendationsToViolations(
            analysisResult.recommendations,
            ruleConfig: ruleConfig,
            sourceFile: sourceFile
        ))

        // Add additional pattern-based analysis
        violations.append(contentsOf: analyzeAllocationPatterns(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            maxLoopAllocations: maxLoopAllocations,
            checkStringConcatenation: checkStringConcatenation,
            checkArrayGrowth: checkArrayGrowth,
            checkClosureAllocation: checkClosureAllocation
        ))

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }

    // MARK: - Helper Methods

    private func convertRecommendationsToViolations(
        _ recommendations: [AllocationTracker.PerformanceRecommendation],
        ruleConfig: RuleSpecificConfiguration,
        sourceFile: SourceFile
    ) -> [Violation] {
        return recommendations.map { recommendation in
            ViolationBuilder(
                ruleId: id,
                category: .performance,
                location: Location(
                    file: sourceFile.url,
                    line: recommendation.location.line,
                    column: recommendation.location.column
                )
            )
            .message(recommendation.message)
            .suggestFix(recommendation.suggestion)
            .severity(overrideSeverity(recommendation.impact, with: ruleConfig.severity))
            .build()
        }
    }

    private func analyzeAllocationPatterns(
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration,
        maxLoopAllocations: Int,
        checkStringConcatenation: Bool,
        checkArrayGrowth: Bool,
        checkClosureAllocation: Bool
    ) -> [Violation] {
        var violations: [Violation] = []

        let source = sourceFile.source()
        let tree = Parser.parse(source: source)

        let patternAnalyzer = AllocationPatternAnalyzer(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            maxLoopAllocations: maxLoopAllocations,
            checkStringConcatenation: checkStringConcatenation,
            checkArrayGrowth: checkArrayGrowth,
            checkClosureAllocation: checkClosureAllocation
        )
        patternAnalyzer.walk(tree)

        violations.append(contentsOf: patternAnalyzer.violations)

        return violations
    }

    private func overrideSeverity(_ impact: AllocationTracker.PerformanceImpact, with configured: DiagnosticSeverity) -> DiagnosticSeverity {
        switch (impact, configured) {
        case (.critical, _), (_, .error):
            return .error
        case (.high, _), (_, .warning):
            return .warning
        default:
            return .info
        }
    }
}

/// Syntax analyzer for allocation pattern violations
private class AllocationPatternAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let ruleConfig: RuleSpecificConfiguration
    private let maxLoopAllocations: Int
    private let checkStringConcatenation: Bool
    private let checkArrayGrowth: Bool
    private let checkClosureAllocation: Bool

    var violations: [Violation] = []
    private var inLoop: Bool = false
    private var loopAllocations: Int = 0
    private var currentFunction: String?

    init(
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration,
        maxLoopAllocations: Int,
        checkStringConcatenation: Bool,
        checkArrayGrowth: Bool,
        checkClosureAllocation: Bool
    ) {
        self.sourceFile = sourceFile
        self.ruleConfig = ruleConfig
        self.maxLoopAllocations = maxLoopAllocations
        self.checkStringConcatenation = checkStringConcatenation
        self.checkArrayGrowth = checkArrayGrowth
        self.checkClosureAllocation = checkClosureAllocation
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Function Context

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunction = node.name.text
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        currentFunction = nil
    }

    // MARK: - Loop Tracking

    // In SwiftSyntax 600.0.0, ForInStmtSyntax was renamed to ForStmtSyntax
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        enterLoop()
        return .visitChildren
    }

    override func visitPost(_ node: ForStmtSyntax) {
        exitLoop()
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        enterLoop()
        return .visitChildren
    }

    override func visitPost(_ node: WhileStmtSyntax) {
        exitLoop()
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        enterLoop()
        return .visitChildren
    }

    override func visitPost(_ node: RepeatStmtSyntax) {
        exitLoop()
    }

    // MARK: - Allocation Pattern Analysis

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let bindings = node.bindings.first else { return .skipChildren }

        if let initializer = bindings.initializer {
            // Check if this is an allocation pattern (e.g., let x = DateFormatter())
            if let funcCall = initializer.value.as(FunctionCallExprSyntax.self) {
                let calledFunction = funcCall.calledExpression.trimmedDescription
                
                if isAllocationPattern(calledFunction) {
                    trackAllocation(location: node.position)
                    analyzeAllocation(initializer.value, location: node.position)
                    
                    // Report expensive allocations inside loops
                    if inLoop && isExpensiveLoopAllocation(calledFunction) {
                        let locationInfo = sourceFile.location(of: node)
                        let violation = ViolationBuilder(
                            ruleId: "repeated_allocation",
                            category: .performance,
                            location: locationInfo
                        )
                        .message("Expensive allocation '\(calledFunction)' inside loop")
                        .suggestFix("Move allocation outside loop and reuse the instance")
                        .severity(.warning)
                        .build()

                        violations.append(violation)
                    }
                }
            } else {
                analyzeAllocation(initializer.value, location: node.position)
            }
        }

        return .skipChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let calledFunction = node.calledExpression.trimmedDescription

        // Check for allocation patterns
        if isAllocationPattern(calledFunction) {
            trackAllocation(location: node.position)
            analyzeAllocation(node.calledExpression, location: node.position)
            
            // Report expensive allocations inside loops even if below threshold
            if inLoop && isExpensiveLoopAllocation(calledFunction) {
                let locationInfo = sourceFile.location(of: node)
                let violation = ViolationBuilder(
                    ruleId: "repeated_allocation",
                    category: .performance,
                    location: locationInfo
                )
                .message("Expensive allocation '\(calledFunction)' inside loop")
                .suggestFix("Move allocation outside loop and reuse the instance")
                .severity(.warning)
                .build()

                violations.append(violation)
            }
        }

        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if checkClosureAllocation {
            trackAllocation(location: node.position)

            if inLoop {
                let locationInfo = sourceFile.location(of: node)
                let violation = ViolationBuilder(
                    ruleId: "repeated_allocation",
                    category: .performance,
                    location: locationInfo
                )
                .message("Closure allocation inside loop may cause performance issues")
                .suggestFix("Move closure outside loop or use capture lists effectively")
                .severity(.warning)
                .build()

                violations.append(violation)
            }
        }

        return .visitChildren
    }

    override func visit(_ node: ArrayExprSyntax) -> SyntaxVisitorContinueKind {
        trackAllocation(location: node.position)
        analyzeArrayLiteral(node, location: node.position)
        return .skipChildren
    }

    override func visit(_ node: DictionaryExprSyntax) -> SyntaxVisitorContinueKind {
        trackAllocation(location: node.position)
        return .skipChildren
    }

    // MARK: - String Concatenation Analysis

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if checkStringConcatenation {
            analyzeStringConcatenation(node)
        }
        return .visitChildren
    }

    // MARK: - Helper Methods

    private func enterLoop() {
        inLoop = true
        loopAllocations = 0
    }

    private func exitLoop() {
        inLoop = false
        loopAllocations = 0
    }

    private func trackAllocation(location: AbsolutePosition) {
        if inLoop {
            loopAllocations += 1

            if loopAllocations > maxLoopAllocations {
                let locationInfo = sourceFile.location(for: location)
                let violation = ViolationBuilder(
                    ruleId: "repeated_allocation",
                    category: .performance,
                    location: locationInfo
                )
                .message("Too many allocations in loop (\(loopAllocations), threshold: \(maxLoopAllocations))")
                .suggestFix("Move allocations outside loop or use pooling/reuse patterns")
                .severity(.warning)
                .build()

                violations.append(violation)
            }
        }
    }

    private func analyzeAllocation(_ expression: ExprSyntax, location: AbsolutePosition) {
        let expressionString = expression.trimmedDescription

        // Check for expensive allocations
        if isExpensiveAllocation(expressionString) {
            let locationInfo = sourceFile.location(for: location)
            let violation = ViolationBuilder(
                ruleId: "repeated_allocation",
                category: .performance,
                location: locationInfo
            )
            .message("Expensive allocation detected: '\(expressionString)'")
            .suggestFix("Consider caching, pooling, or lazy initialization")
            .severity(.info)
            .build()

            violations.append(violation)
        }
    }

    private func analyzeArrayLiteral(_ arrayExpr: ArrayExprSyntax, location: AbsolutePosition) {
        // Check for large array literals
        let elementCount = arrayExpr.elements.count
        let maxArrayLiteralSize = ruleConfig.parameter("maxArrayLiteralSize", defaultValue: 10)

        if elementCount > maxArrayLiteralSize {
            let locationInfo = sourceFile.location(for: location)
            let violation = ViolationBuilder(
                ruleId: "repeated_allocation",
                category: .performance,
                location: locationInfo
            )
            .message("Large array literal with \(elementCount) elements (threshold: \(maxArrayLiteralSize))")
            .suggestFix("Consider using data files, lazy loading, or smaller initial arrays")
            .severity(.info)
            .build()

            violations.append(violation)
        }
    }

    private func analyzeStringConcatenation(_ binaryExpr: InfixOperatorExprSyntax) {
        // Check the operator - look for + or += which are string concatenation operators
        let operatorText = binaryExpr.operator.trimmedDescription
        
        // Only check + and += operators for string concatenation
        guard operatorText == "+" || operatorText == "+=" else { return }
        
        // In SwiftSyntax 600.0.0, BinaryOperationExprSyntax structure has changed
        let children = binaryExpr.children(viewMode: .sourceAccurate)
        let childArray = Array(children)

        var leftString = ""
        var rightString = ""

        if childArray.count >= 3 {
            // First child should be the left side (LHS)
            if let leftExpr = childArray[0].as(ExprSyntax.self) {
                leftString = leftExpr.trimmedDescription
            }

            // Third child should be the right side (RHS)
            if let rightExpr = childArray[2].as(ExprSyntax.self) {
                rightString = rightExpr.trimmedDescription
            }
        }

        // Check for string concatenation in loops
        // Detect patterns like: result += item, str = str + other, "a" + "b"
        if isStringConcatenation(leftString, rightString, operator: operatorText) && inLoop {
            let locationInfo = sourceFile.location(for: binaryExpr.position)
            let violation = ViolationBuilder(
                ruleId: "repeated_allocation",
                category: .performance,
                location: locationInfo
            )
            .message("String concatenation in loop causes repeated allocations")
            .suggestFix("Use StringBuilder or pre-allocate string capacity")
            .severity(.warning)
            .build()

            violations.append(violation)
        }
    }

    private func isAllocationPattern(_ functionName: String) -> Bool {
        // Common allocation patterns - note: functionName is just the called expression without ()
        let allocationPatterns = [
            "String", "Data", "Array", "Dictionary",
            "Set", "NSMutableArray", "NSMutableDictionary",
            "NSMutableData", "NSMutableString",
            // Common expensive Foundation types
            "DateFormatter", "NumberFormatter", "ByteCountFormatter",
            "MeasurementFormatter", "PersonNameComponentsFormatter",
            "DateComponentsFormatter", "DateIntervalFormatter",
            "ISO8601DateFormatter", "RelativeDateTimeFormatter",
            "JSONEncoder", "JSONDecoder", "PropertyListEncoder", "PropertyListDecoder",
            "NSRegularExpression", "NSCache", "NSURLSession"
        ]

        // Check if functionName matches any allocation pattern
        // We compare the end of the string to handle qualified names like Foundation.DateFormatter
        return allocationPatterns.contains { pattern in 
            functionName == pattern || functionName.hasSuffix(".\(pattern)")
        }
    }

    private func isExpensiveAllocation(_ expression: String) -> Bool {
        // Check for expensive allocation patterns
        let expensivePatterns = [
            "Data(", "UIImage(", "UIViewController(",
            "NSManagedObject", "CoreData", "Foundation.Data"
        ]

        return expensivePatterns.contains { expression.contains($0) }
    }
    
    /// Check if an allocation is expensive when done inside a loop
    private func isExpensiveLoopAllocation(_ functionName: String) -> Bool {
        // These allocations are expensive when done repeatedly in loops
        let expensiveLoopPatterns = [
            // Formatters are expensive to create
            "DateFormatter", "NumberFormatter", "ByteCountFormatter",
            "MeasurementFormatter", "PersonNameComponentsFormatter",
            "DateComponentsFormatter", "DateIntervalFormatter",
            "ISO8601DateFormatter", "RelativeDateTimeFormatter",
            // Coders are expensive
            "JSONEncoder", "JSONDecoder", "PropertyListEncoder", "PropertyListDecoder",
            // Regex compilation is expensive  
            "NSRegularExpression",
            // Network/Core Data
            "NSURLSession", "NSManagedObject"
        ]
        
        return expensiveLoopPatterns.contains { pattern in 
            functionName == pattern || functionName.hasSuffix(".\(pattern)")
        }
    }

    private func isStringConcatenation(_ left: String, _ right: String, operator op: String) -> Bool {
        // For += operator, it's likely a string accumulation pattern (result += item)
        // This is a common inefficient pattern in loops
        if op == "+=" {
            return true  // Assume any += in a loop could be string concatenation
        }
        
        // For + operator, check if operands look like strings
        return (left.hasPrefix("\"") || right.hasPrefix("\"")) ||
               (left.contains("String(") || right.contains("String(")) ||
               (left.hasPrefix("\"") && right.hasPrefix("\""))
    }
}