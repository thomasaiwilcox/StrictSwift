import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that detects ARC (Automatic Reference Counting) churn patterns that can impact performance
/// SAFETY: @unchecked Sendable is safe because this rule has no mutable stored state.
/// All analysis is performed with fresh analyzers created per analyze() call.
public final class ARCChurnRule: Rule, @unchecked Sendable {
    public var id: String { "arc_churn" }
    public var name: String { "ARC Churn" }
    public var description: String { "Detects excessive retain/release patterns and ARC churn in loop bodies. Iterator expressions (e.g., for x in items.sorted()) are excluded as they execute once, not per iteration." }
    public var category: RuleCategory { .performance }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []

        // Get configuration
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }

        // Get configuration parameters
        let maxRetainsInLoop = ruleConfig.parameter("maxRetainsInLoop", defaultValue: 10)
        // Closure capture checks produce false positives with structured concurrency - disabled by default
        let checkClosureCaptures = ruleConfig.parameter("checkClosureCaptures", defaultValue: false)
        let checkPropertyAccess = ruleConfig.parameter("checkPropertyAccess", defaultValue: true)
        let checkArrayOperations = ruleConfig.parameter("checkArrayOperations", defaultValue: true)
        let checkOptionalChaining = ruleConfig.parameter("checkOptionalChaining", defaultValue: true)
        let checkHotPaths = ruleConfig.parameter("checkHotPaths", defaultValue: true)
        // Higher-order functions in loops are common and often acceptable - disabled by default
        let checkHigherOrderFunctions = ruleConfig.parameter("checkHigherOrderFunctions", defaultValue: false)

        // Parse source and analyze
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)

        let analyzer = ARCChurnAnalyzer(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            maxRetainsInLoop: maxRetainsInLoop,
            checkClosureCaptures: checkClosureCaptures,
            checkPropertyAccess: checkPropertyAccess,
            checkArrayOperations: checkArrayOperations,
            checkOptionalChaining: checkOptionalChaining,
            checkHotPaths: checkHotPaths,
            checkHigherOrderFunctions: checkHigherOrderFunctions
        )
        analyzer.walk(tree)

        violations.append(contentsOf: analyzer.violations)

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax analyzer for ARC churn patterns
private class ARCChurnAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let ruleConfig: RuleSpecificConfiguration
    private let maxRetainsInLoop: Int
    private let checkClosureCaptures: Bool
    private let checkPropertyAccess: Bool
    private let checkArrayOperations: Bool
    private let checkOptionalChaining: Bool
    private let checkHotPaths: Bool
    private let checkHigherOrderFunctions: Bool

    var violations: [Violation] = []

    // Tracking state
    private var loopDepth: Int = 0
    private var currentFunction: String?
    private var isInHotPath: Bool = false
    private var referenceAccessesInLoop: [String: Int] = [:]
    private var selfAccessCount: Int = 0
    private var closureDepth: Int = 0

    // Known reference types that cause ARC operations
    private let referenceTypes: Set<String> = [
        "class", "AnyObject", "NSObject", "UIView", "UIViewController",
        "NSView", "NSViewController", "CALayer", "SKNode", "SCNNode"
    ]

    // Methods that typically cause retain/release
    private let retainCausingMethods: Set<String> = [
        "append", "insert", "removeAll", "filter", "map", "compactMap",
        "flatMap", "reduce", "sorted", "reversed"
    ]

    init(
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration,
        maxRetainsInLoop: Int,
        checkClosureCaptures: Bool,
        checkPropertyAccess: Bool,
        checkArrayOperations: Bool,
        checkOptionalChaining: Bool,
        checkHotPaths: Bool,
        checkHigherOrderFunctions: Bool
    ) {
        self.sourceFile = sourceFile
        self.ruleConfig = ruleConfig
        self.maxRetainsInLoop = maxRetainsInLoop
        self.checkClosureCaptures = checkClosureCaptures
        self.checkPropertyAccess = checkPropertyAccess
        self.checkArrayOperations = checkArrayOperations
        self.checkOptionalChaining = checkOptionalChaining
        self.checkHotPaths = checkHotPaths
        self.checkHigherOrderFunctions = checkHigherOrderFunctions
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Function Tracking

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunction = node.name.text
        selfAccessCount = 0
        referenceAccessesInLoop.removeAll()

        // Check for @hotPath attribute
        if checkHotPaths {
            isInHotPath = hasHotPathAttribute(node.attributes)
        }

        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        currentFunction = nil
        isInHotPath = false
    }

    // MARK: - Loop Detection
    
    // For loops: visit the sequence expression BEFORE incrementing loopDepth
    // because the sequence is evaluated ONCE, not per iteration.
    // Example: `for x in items.sorted()` - sorted() is called once, not per iteration
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        // First visit the sequence expression - it runs once before the loop
        walk(node.sequence)
        
        // Now enter the loop body context
        loopDepth += 1
        referenceAccessesInLoop.removeAll()
        
        // Visit the pattern (usually just a simple identifier, safe to visit in loop context)
        walk(node.pattern)
        
        // Visit the loop body
        walk(node.body)
        
        // Check for ARC churn and exit loop context
        checkLoopARCChurn(at: node.position)
        loopDepth -= 1
        
        // Skip automatic children traversal since we did it manually
        return .skipChildren
    }

    // While loops: visit the conditions BEFORE incrementing loopDepth
    // because `while let x = iterator.next()` evaluates next() per iteration,
    // but the condition setup itself is evaluated before the body
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        // Visit conditions outside loop context - they're evaluated per iteration
        // but flagging them as "in loop" would be misleading since the user can't easily move them out
        // Actually, we SHOULD flag these since they run per iteration, but we'll be more lenient
        // and only flag obvious patterns inside the body
        walk(node.conditions)
        
        // Enter loop body context
        loopDepth += 1
        referenceAccessesInLoop.removeAll()
        
        // Visit the loop body
        walk(node.body)
        
        // Check for ARC churn and exit loop context
        checkLoopARCChurn(at: node.position)
        loopDepth -= 1
        
        return .skipChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        // Enter loop body context
        loopDepth += 1
        referenceAccessesInLoop.removeAll()
        
        // Visit the loop body
        walk(node.body)
        
        // Check for ARC churn
        checkLoopARCChurn(at: node.position)
        loopDepth -= 1
        
        // Visit condition outside loop context (it runs per iteration but at the end)
        walk(node.condition)
        
        return .skipChildren
    }

    // MARK: - Closure Detection

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        closureDepth += 1

        if checkClosureCaptures && loopDepth > 0 {
            // Check for self captures in closures inside loops
            checkClosureCapturesInLoop(node)
        }

        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        closureDepth -= 1
    }

    // MARK: - Member Access Detection

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if loopDepth > 0 && checkPropertyAccess {
            // Track reference type property access in loops
            let memberName = node.declName.baseName.text

            // Check for self access
            if let base = node.base, base.description.trimmingCharacters(in: .whitespaces) == "self" {
                selfAccessCount += 1
                referenceAccessesInLoop["self.\(memberName)", default: 0] += 1
            }

            // Check for optional chaining which causes additional retain/release
            if checkOptionalChaining && node.base?.description.contains("?") == true {
                referenceAccessesInLoop["optional.\(memberName)", default: 0] += 1
            }
        }

        return .visitChildren
    }

    // MARK: - Function Call Detection

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if loopDepth > 0 && checkArrayOperations {
            // Check for array/collection operations that cause ARC churn
            if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
                let methodName = memberAccess.declName.baseName.text

                if retainCausingMethods.contains(methodName) {
                    let key = "arrayOp.\(methodName)"
                    referenceAccessesInLoop[key, default: 0] += 1

                    // Higher-order functions are only flagged when explicitly enabled
                    // (they're common patterns that are often acceptable)
                    if checkHigherOrderFunctions && ["map", "filter", "compactMap", "flatMap", "reduce", "sorted"].contains(methodName) {
                        checkHigherOrderFunctionInLoop(node, methodName: methodName)
                    }
                }
            }
        }

        return .visitChildren
    }

    // MARK: - Variable Declaration Detection

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if loopDepth > 0 {
            // Check for reference type allocations in loops
            for binding in node.bindings {
                if let typeAnnotation = binding.typeAnnotation {
                    let typeName = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
                    if isReferenceType(typeName) {
                        addViolation(
                            at: node.position,
                            message: "Reference type '\(typeName)' allocated in loop causes ARC churn",
                            suggestion: "Consider moving allocation outside the loop or using a value type",
                            severity: isInHotPath ? .error : .warning
                        )
                    }
                }

                // Check for class instantiation
                if let initializer = binding.initializer?.value {
                    checkInitializerForARCChurn(initializer)
                }
            }
        }

        return .visitChildren
    }

    // MARK: - Helper Methods

    private func hasHotPathAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if case let .attribute(attr) = attribute {
                let attrName = attr.attributeName.description.trimmingCharacters(in: .whitespaces)
                if attrName == "hotPath" || attrName == "HotPath" {
                    return true
                }
            }
        }
        return false
    }

    private func checkLoopARCChurn(at position: AbsolutePosition) {
        // Check for excessive reference accesses in the loop
        let totalAccesses = referenceAccessesInLoop.values.reduce(0, +)

        if totalAccesses > maxRetainsInLoop {
            let topOffenders = referenceAccessesInLoop
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { "\($0.key): \($0.value)x" }
                .joined(separator: ", ")

            addViolation(
                at: position,
                message: "Loop contains \(totalAccesses) potential ARC operations (threshold: \(maxRetainsInLoop)). Hot spots: \(topOffenders)",
                suggestion: "Cache reference type values before the loop or use local variables to reduce retain/release cycles",
                severity: isInHotPath ? .error : .warning
            )
        }

        // Check for repeated self access
        if selfAccessCount > maxRetainsInLoop * 2 {
            addViolation(
                at: position,
                message: "Loop accesses 'self' \(selfAccessCount) times, causing repeated retain/release",
                suggestion: "Capture self properties in local variables before the loop: `let value = self.property`",
                severity: isInHotPath ? .error : .warning
            )
        }
    }

    private func checkClosureCapturesInLoop(_ closure: ClosureExprSyntax) {
        // Check capture list
        if let signature = closure.signature, let capture = signature.capture {
            let captureCount = capture.items.count

            if captureCount > 2 {
                addViolation(
                    at: closure.position,
                    message: "Closure in loop captures \(captureCount) values, causing ARC overhead per iteration",
                    suggestion: "Reduce captured values or move closure creation outside the loop",
                    severity: isInHotPath ? .error : .warning
                )
            }

            // Check for strong self capture
            for item in capture.items {
                let captureText = item.description
                if captureText.contains("self") && !captureText.contains("weak") && !captureText.contains("unowned") {
                    addViolation(
                        at: closure.position,
                        message: "Strong self capture in closure inside loop causes retain/release per iteration",
                        suggestion: "Use [weak self] or [unowned self] to avoid ARC churn",
                        severity: .warning
                    )
                }
            }
        }

        // Check closure body for self references without capture list
        let closureSource = closure.description
        if closureSource.contains("self.") && closure.signature?.capture == nil {
            addViolation(
                at: closure.position,
                message: "Closure in loop implicitly captures self, causing ARC operations per iteration",
                suggestion: "Add explicit capture list [weak self] or cache self properties before the loop",
                severity: isInHotPath ? .error : .warning
            )
        }
    }

    private func checkHigherOrderFunctionInLoop(_ call: FunctionCallExprSyntax, methodName: String) {
        // Higher-order functions create new collections and closures
        addViolation(
            at: call.position,
            message: "'\(methodName)' in loop creates new collection and closure per iteration",
            suggestion: "Consider using a single '\(methodName)' call on the entire collection outside the loop, or use imperative approach",
            severity: isInHotPath ? .error : .warning
        )
    }

    private func checkInitializerForARCChurn(_ initializer: ExprSyntax) {
        // Check for function calls that create reference types
        if let functionCall = initializer.as(FunctionCallExprSyntax.self) {
            let calledExpr = functionCall.calledExpression.description.trimmingCharacters(in: .whitespaces)

            // Common reference type initializers
            let referenceTypeInitializers = [
                "NSObject", "UIView", "UIViewController", "NSView", "NSViewController",
                "NSMutableArray", "NSMutableDictionary", "NSMutableString",
                "DispatchQueue", "OperationQueue", "URLSession",
                "CALayer", "CAAnimation", "SKNode", "SCNNode"
            ]

            for typeName in referenceTypeInitializers {
                if calledExpr.hasPrefix(typeName) {
                    addViolation(
                        at: functionCall.position,
                        message: "'\(typeName)' instantiation in loop causes heap allocation and ARC overhead per iteration",
                        suggestion: "Move instantiation outside the loop and reuse the object",
                        severity: isInHotPath ? .error : .warning
                    )
                    break
                }
            }
        }
    }

    private func isReferenceType(_ typeName: String) -> Bool {
        // Check against known reference types
        for refType in referenceTypes {
            if typeName.contains(refType) {
                return true
            }
        }

        // Check for class-like naming conventions (not perfect but helpful)
        // Types starting with NS, UI, CA, SK, SCN are typically classes
        let classyPrefixes = ["NS", "UI", "CA", "SK", "SCN", "CK", "MK", "PK", "WK"]
        for prefix in classyPrefixes {
            if typeName.hasPrefix(prefix) {
                return true
            }
        }

        return false
    }

    private func addViolation(at position: AbsolutePosition, message: String, suggestion: String, severity: DiagnosticSeverity) {
        let location = sourceFile.location(for: position)
        let violation = ViolationBuilder(
            ruleId: "arc_churn",
            category: .performance,
            location: location
        )
        .message(message)
        .suggestFix(suggestion)
        .severity(severity)
        .build()

        violations.append(violation)
    }
}
