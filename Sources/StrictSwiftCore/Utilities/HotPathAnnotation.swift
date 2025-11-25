import Foundation
import SwiftSyntax
import SwiftParser

/// Utility for detecting and working with the @hotPath attribute annotation
/// Used to mark performance-critical code paths for stricter analysis
public struct HotPathAnnotation: Sendable {
    
    /// Check if a function has the @hotPath attribute
    public static func isHotPath(_ node: FunctionDeclSyntax) -> Bool {
        return hasHotPathAttribute(node.attributes)
    }
    
    /// Check if a variable has the @hotPath attribute
    public static func isHotPath(_ node: VariableDeclSyntax) -> Bool {
        return hasHotPathAttribute(node.attributes)
    }
    
    /// Check if any ancestor has @hotPath (for nested code)
    public static func isInHotPathContext(_ node: some SyntaxProtocol) -> Bool {
        var current: Syntax? = Syntax(node)
        
        while let syntax = current {
            if let funcDecl = syntax.as(FunctionDeclSyntax.self) {
                if isHotPath(funcDecl) {
                    return true
                }
            }
            if let varDecl = syntax.as(VariableDeclSyntax.self) {
                if isHotPath(varDecl) {
                    return true
                }
            }
            current = syntax.parent
        }
        
        return false
    }
    
    /// Check an attribute list for @hotPath
    public static func hasHotPathAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if case let .attribute(attr) = attribute {
                let attrName = attr.attributeName.description.trimmingCharacters(in: .whitespaces)
                // Support both @hotPath and @HotPath conventions
                if attrName == "hotPath" || attrName == "HotPath" || 
                   attrName == "hot_path" || attrName == "performanceCritical" ||
                   attrName == "PerformanceCritical" {
                    return true
                }
            }
        }
        return false
    }
    
    /// Get the reason/description from @hotPath("reason") if provided
    public static func getHotPathReason(_ attributes: AttributeListSyntax) -> String? {
        for attribute in attributes {
            if case let .attribute(attr) = attribute {
                let attrName = attr.attributeName.description.trimmingCharacters(in: .whitespaces)
                if attrName == "hotPath" || attrName == "HotPath" ||
                   attrName == "hot_path" || attrName == "performanceCritical" ||
                   attrName == "PerformanceCritical" {
                    // Check for argument
                    if let args = attr.arguments, case let .argumentList(argList) = args {
                        if let firstArg = argList.first {
                            return firstArg.expression.description.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        }
                    }
                }
            }
        }
        return nil
    }
}

/// Visitor that collects all @hotPath annotated functions in a source file
public class HotPathCollector: SyntaxVisitor {
    public struct HotPathFunction: Sendable {
        public let name: String
        public let location: AbsolutePosition
        public let reason: String?
        public let isAsync: Bool
        public let parameters: [String]
    }
    
    public private(set) var hotPathFunctions: [HotPathFunction] = []
    
    public init() {
        super.init(viewMode: .sourceAccurate)
    }
    
    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if HotPathAnnotation.isHotPath(node) {
            let reason = HotPathAnnotation.getHotPathReason(node.attributes)
            let isAsync = node.signature.effectSpecifiers?.asyncSpecifier != nil
            let parameters = node.signature.parameterClause.parameters.map { 
                $0.firstName.text + ": " + $0.type.description.trimmingCharacters(in: .whitespaces)
            }
            
            hotPathFunctions.append(HotPathFunction(
                name: node.name.text,
                location: node.position,
                reason: reason,
                isAsync: isAsync,
                parameters: parameters
            ))
        }
        return .visitChildren
    }
}

/// Configuration for how @hotPath affects analysis
public struct HotPathConfiguration: Codable, Sendable {
    /// Whether @hotPath functions should have stricter thresholds
    public var stricterThresholds: Bool = true
    
    /// Multiplier for thresholds in hot paths (e.g., 0.5 means half the normal threshold)
    public var thresholdMultiplier: Double = 0.5
    
    /// Whether to treat violations in hot paths as errors instead of warnings
    public var elevateToError: Bool = true
    
    /// Whether to flag async operations in hot paths
    public var flagAsyncInHotPath: Bool = true
    
    /// Whether to flag any heap allocations in hot paths
    public var flagHeapAllocations: Bool = true
    
    /// Maximum allowed complexity in hot paths
    public var maxComplexityInHotPath: Int = 5
    
    /// Maximum allowed nesting depth in hot paths
    public var maxNestingInHotPath: Int = 3
    
    /// Maximum allowed function length in hot paths (lines)
    public var maxLengthInHotPath: Int = 30
    
    public init() {}
    
    /// Get adjusted threshold for hot path context
    public func adjustedThreshold(_ normalThreshold: Int) -> Int {
        if stricterThresholds {
            return Int(Double(normalThreshold) * thresholdMultiplier)
        }
        return normalThreshold
    }
    
    /// Get severity for hot path violations
    public func severity(for normalSeverity: DiagnosticSeverity) -> DiagnosticSeverity {
        if elevateToError && normalSeverity == .warning {
            return .error
        }
        return normalSeverity
    }
}

/// Rule that validates @hotPath annotated code meets performance requirements
/// SAFETY: @unchecked Sendable is safe because this rule has no mutable stored state.
public final class HotPathValidationRule: Rule, @unchecked Sendable {
    public var id: String { "hot_path_validation" }
    public var name: String { "Hot Path Validation" }
    public var description: String { "Validates that @hotPath annotated code meets strict performance requirements" }
    public var category: RuleCategory { .performance }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }
    
    public init() {}
    
    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        
        // Get configuration
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }
        
        // Get hot path configuration
        let flagAsync = ruleConfig.parameter("flagAsyncInHotPath", defaultValue: true)
        let flagHeapAlloc = ruleConfig.parameter("flagHeapAllocations", defaultValue: true)
        let maxComplexity = ruleConfig.parameter("maxComplexityInHotPath", defaultValue: 5)
        let maxNesting = ruleConfig.parameter("maxNestingInHotPath", defaultValue: 3)
        let maxLength = ruleConfig.parameter("maxLengthInHotPath", defaultValue: 30)
        
        // Parse and analyze
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)
        
        let analyzer = HotPathAnalyzer(
            sourceFile: sourceFile,
            flagAsync: flagAsync,
            flagHeapAlloc: flagHeapAlloc,
            maxComplexity: maxComplexity,
            maxNesting: maxNesting,
            maxLength: maxLength
        )
        analyzer.walk(tree)
        
        violations.append(contentsOf: analyzer.violations)
        
        return violations
    }
    
    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Analyzer for hot path validation
private class HotPathAnalyzer: SyntaxVisitor {
    private let sourceFile: SourceFile
    private let flagAsync: Bool
    private let flagHeapAlloc: Bool
    private let maxComplexity: Int
    private let maxNesting: Int
    private let maxLength: Int
    
    var violations: [Violation] = []
    
    private var inHotPath: Bool = false
    private var hotPathFunctionStart: AbsolutePosition?
    private var currentNestingDepth: Int = 0
    private var currentComplexity: Int = 1 // Start at 1 for the function itself
    private var currentFunctionLines: Int = 0
    
    init(
        sourceFile: SourceFile,
        flagAsync: Bool,
        flagHeapAlloc: Bool,
        maxComplexity: Int,
        maxNesting: Int,
        maxLength: Int
    ) {
        self.sourceFile = sourceFile
        self.flagAsync = flagAsync
        self.flagHeapAlloc = flagHeapAlloc
        self.maxComplexity = maxComplexity
        self.maxNesting = maxNesting
        self.maxLength = maxLength
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if HotPathAnnotation.isHotPath(node) {
            inHotPath = true
            hotPathFunctionStart = node.position
            currentComplexity = 1
            currentNestingDepth = 0
            
            // Calculate function length
            let funcSource = node.description
            currentFunctionLines = funcSource.components(separatedBy: .newlines).count
            
            // Check for async in hot path
            if flagAsync && node.signature.effectSpecifiers?.asyncSpecifier != nil {
                addViolation(
                    at: node.position,
                    message: "@hotPath function '\(node.name.text)' is marked async, which may cause performance overhead",
                    suggestion: "Consider using synchronous implementation for hot paths or document why async is necessary"
                )
            }
            
            // Check function length
            if currentFunctionLines > maxLength {
                addViolation(
                    at: node.position,
                    message: "@hotPath function '\(node.name.text)' is \(currentFunctionLines) lines (max: \(maxLength))",
                    suggestion: "Split into smaller functions or inline critical sections"
                )
            }
        }
        
        return .visitChildren
    }
    
    override func visitPost(_ node: FunctionDeclSyntax) {
        if HotPathAnnotation.isHotPath(node) {
            // Check complexity at end of function
            if currentComplexity > maxComplexity {
                addViolation(
                    at: node.position,
                    message: "@hotPath function '\(node.name.text)' has complexity \(currentComplexity) (max: \(maxComplexity))",
                    suggestion: "Reduce conditional logic or extract helper functions"
                )
            }
            
            inHotPath = false
            hotPathFunctionStart = nil
        }
    }
    
    // Track complexity contributors
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        if inHotPath {
            currentComplexity += 1
            currentNestingDepth += 1
            checkNestingDepth(at: node.position)
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: IfExprSyntax) {
        if inHotPath {
            currentNestingDepth -= 1
        }
    }
    
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        if inHotPath {
            currentComplexity += 1
            currentNestingDepth += 1
            checkNestingDepth(at: node.position)
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: ForStmtSyntax) {
        if inHotPath {
            currentNestingDepth -= 1
        }
    }
    
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        if inHotPath {
            currentComplexity += 1
            currentNestingDepth += 1
            checkNestingDepth(at: node.position)
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: WhileStmtSyntax) {
        if inHotPath {
            currentNestingDepth -= 1
        }
    }
    
    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        if inHotPath {
            // Each case adds to complexity
            currentComplexity += node.cases.count
            currentNestingDepth += 1
            checkNestingDepth(at: node.position)
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: SwitchExprSyntax) {
        if inHotPath {
            currentNestingDepth -= 1
        }
    }
    
    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        if inHotPath {
            currentComplexity += 1
        }
        return .visitChildren
    }
    
    // Check for heap allocations
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if inHotPath && flagHeapAlloc {
            let calledExpr = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
            
            // Check for known heap-allocating patterns
            let heapAllocatingTypes = [
                "NSObject", "UIView", "UIViewController", "NSView",
                "NSMutableArray", "NSMutableDictionary", "NSMutableString",
                "DispatchQueue", "OperationQueue", "URLSession",
                "Data(", "Array(", "Dictionary(", "Set(",
                "String(repeating:", "ContiguousArray("
            ]
            
            for allocType in heapAllocatingTypes {
                if calledExpr.contains(allocType) {
                    addViolation(
                        at: node.position,
                        message: "Heap allocation '\(calledExpr.prefix(30))...' in @hotPath function",
                        suggestion: "Pre-allocate outside hot path or use stack-allocated alternatives"
                    )
                    break
                }
            }
        }
        
        return .visitChildren
    }
    
    // Check for closures (which may allocate)
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if inHotPath && flagHeapAlloc {
            addViolation(
                at: node.position,
                message: "Closure in @hotPath may cause heap allocation",
                suggestion: "Use direct function calls or inline the closure logic"
            )
        }
        return .visitChildren
    }
    
    private func checkNestingDepth(at position: AbsolutePosition) {
        if currentNestingDepth > maxNesting {
            addViolation(
                at: position,
                message: "Nesting depth \(currentNestingDepth) exceeds maximum \(maxNesting) for @hotPath",
                suggestion: "Flatten control flow using early returns or guard statements"
            )
        }
    }
    
    private func addViolation(at position: AbsolutePosition, message: String, suggestion: String) {
        let location = sourceFile.location(for: position)
        let violation = ViolationBuilder(
            ruleId: "hot_path_validation",
            category: .performance,
            location: location
        )
        .message(message)
        .suggestFix(suggestion)
        .severity(.error)
        .build()
        
        violations.append(violation)
    }
}
