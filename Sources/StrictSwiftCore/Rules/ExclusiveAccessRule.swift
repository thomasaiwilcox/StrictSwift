import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that detects exclusive access violations that could cause data races
/// SAFETY: @unchecked Sendable is safe because this rule has no stored state.
/// OwnershipAnalyzer instances are created fresh per analysis call for thread safety.
public final class ExclusiveAccessRule: Rule, @unchecked Sendable {
    public var id: String { "exclusive_access" }
    public var name: String { "Exclusive Access" }
    public var description: String { "Detects exclusive access violations that could cause data races and memory corruption" }
    public var category: RuleCategory { .memory }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    // Infrastructure components for thread safety
    // Note: OwnershipAnalyzer is created per analysis to ensure thread safety

    public init() {
        // No shared analyzer - create new instance per analysis
    }

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []

        // Get configuration
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }

        // Perform ownership analysis - create new analyzer per file for thread safety
        let ownershipAnalyzer = OwnershipAnalyzer()
        let analysisResult = await ownershipAnalyzer.analyze(sourceFile)
        let exclusiveAccessIssues = analysisResult.issues.filter { $0.type == .exclusiveAccessViolation }
        // Get configuration parameters
        let maxConcurrentAccess = ruleConfig.parameter("maxConcurrentAccess", defaultValue: 1)
        let checkInOutParameters = ruleConfig.parameter("checkInOutParameters", defaultValue: true)
        let checkMutableGlobalState = ruleConfig.parameter("checkMutableGlobalState", defaultValue: true)

        // Analyze source code for additional exclusive access patterns
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)
        let analyzer = ExclusiveAccessAnalyzer(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            maxConcurrentAccess: maxConcurrentAccess,
            checkInOutParameters: checkInOutParameters,
            checkMutableGlobalState: checkMutableGlobalState
        )
        analyzer.walk(tree)

        violations.append(contentsOf: analyzer.violations)
        violations.append(contentsOf: convertOwnershipIssuesToViolations(exclusiveAccessIssues, sourceFile: sourceFile))

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }

    // MARK: - Helper Methods

    private func convertOwnershipIssuesToViolations(_ issues: [MemorySafetyIssue], sourceFile: SourceFile) -> [Violation] {
        return issues.map { issue in
            // Use the real location from MemorySafetyIssue instead of hardcoded line 1
            let location = Location(
                file: sourceFile.url,
                line: issue.location.line,
                column: issue.location.column
            )

            return ViolationBuilder(
                ruleId: id,
                category: .memory,
                location: location
            )
            .message(issue.message)
            .suggestFix(suggestion(for: issue.type))
            .severity(issue.severity)
            .build()
        }
    }

    private func suggestion(for issueType: MemorySafetyIssueType) -> String {
        switch issueType {
        case .exclusiveAccessViolation:
            return "Use synchronization mechanisms (actors, locks, queues) or avoid concurrent access"
        case .escapingReference:
            return "Consider using weak/unowned references or restructuring code"
        case .useAfterFree:
            return "Use proper lifetime management or stronger reference patterns"
        case .retainCycle:
            return "Break cycles using weak/unowned references"
        case .memoryLeak:
            return "Ensure proper cleanup of references"
        }
    }
}

/// Syntax analyzer for detecting exclusive access violations
private class ExclusiveAccessAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let ruleConfig: RuleSpecificConfiguration
    private let maxConcurrentAccess: Int
    private let checkInOutParameters: Bool
    private let checkMutableGlobalState: Bool

    var violations: [Violation] = []
    private var mutableAccesses: [String: [AccessInfo]] = [:]
    private var functionStack: [String] = []
    private var classStack: [String] = []
    private var closureStack: [String] = []
    private var reportedConcurrentAccesses: Set<String> = []

    private var currentFunction: String? { functionStack.last }
    private var currentClass: String? { classStack.last }

    init(sourceFile: SourceFile, ruleConfig: RuleSpecificConfiguration, maxConcurrentAccess: Int, checkInOutParameters: Bool, checkMutableGlobalState: Bool) {
        self.sourceFile = sourceFile
        self.ruleConfig = ruleConfig
        self.maxConcurrentAccess = maxConcurrentAccess
        self.checkInOutParameters = checkInOutParameters
        self.checkMutableGlobalState = checkMutableGlobalState
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        functionStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        _ = functionStack.popLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        classStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        _ = classStack.popLast()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        closureStack.append("closure@\(node.position.utf8Offset)")
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        _ = closureStack.popLast()
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        analyzeVariableDeclaration(node)
        return .skipChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if node.operator.as(AssignmentExprSyntax.self) != nil {
            let lhs = ExprSyntax(node.leftOperand).trimmedDescription
            recordAccess(lhs, type: .write, location: node.position)
        }
        return .visitChildren
    }

    override func visit(_ node: InOutExprSyntax) -> SyntaxVisitorContinueKind {
        if checkInOutParameters {
            analyzeInOutExpression(node)
        }
        return .visitChildren
    }

    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        analyzeSubscriptAccess(node)
        return .visitChildren
    }

    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
        analyzeOptionalBinding(node)
        return .visitChildren
    }

    // MARK: - Private Analysis Methods

    private func analyzeVariableDeclaration(_ decl: VariableDeclSyntax) {
        guard let bindings = decl.bindings.first else { return }

        // Check for global mutable state
        if checkMutableGlobalState && currentFunction == nil && isMutableBinding(decl) {
            for modifier in decl.modifiers {
                if modifier.name.text == "static" || modifier.name.text == "class" {
                    if let identifier = bindings.pattern.as(IdentifierPatternSyntax.self)?.identifier {
                        let location = sourceFile.location(for: decl.position)
                        violations.append(ViolationBuilder(
                            ruleId: "exclusive_access",
                            category: .memory,
                            location: location
                        )
                        .message("Global mutable state '\(identifier.text)' can cause exclusive access violations in concurrent code")
                        .suggestFix("Consider using thread-safe alternatives or proper synchronization")
                        .severity(.warning)
                        .build())
                    }
                }
            }
        }

    }

    private func analyzeInOutExpression(_ inOut: InOutExprSyntax) {
        let expressionString = inOut.expression.trimmedDescription
        recordAccess(expressionString, type: .write, location: inOut.position)
    }

    private func analyzeSubscriptAccess(_ subscriptExpr: SubscriptCallExprSyntax) {
        // Subscript access can be both read and write
        let accessTarget = subscriptExpr.calledExpression.trimmedDescription
        recordAccess(accessTarget, type: .read, location: subscriptExpr.position)
    }

    private func analyzeOptionalBinding(_ optionalBinding: OptionalBindingConditionSyntax) {
        // Optional binding creates mutable access
        if let identifier = optionalBinding.pattern.as(IdentifierPatternSyntax.self)?.identifier {
            recordAccess(identifier.text, type: .write, location: optionalBinding.position)
        }
    }

    // MARK: - Helper Methods

    private func recordAccess(_ target: String, type: AccessType, location: AbsolutePosition) {
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else { return }
        
        // Filter out literal values - they cannot have exclusive access violations
        guard !isLiteralValue(trimmedTarget) else { return }

        let access = AccessInfo(
            target: trimmedTarget,
            type: type,
            location: location,
            function: currentFunction,
            classContext: currentClass,
            closure: closureStack.last
        )

        mutableAccesses[trimmedTarget, default: []].append(access)
        if type == .write {
            checkForConcurrentAccess(trimmedTarget)
        }
    }
    
    /// Checks if a target string represents a literal value that cannot have exclusive access violations
    private func isLiteralValue(_ target: String) -> Bool {
        // Nil literal
        if target == "nil" { return true }
        
        // Boolean literals
        if target == "true" || target == "false" { return true }
        
        // Empty array/dictionary literals
        if target == "[]" || target == "[:]" { return true }
        
        // Empty closure literal
        if target == "{}" || target.hasPrefix("{ ") && target.hasSuffix(" }") { return true }
        
        // Numeric literals (integers and floating point)
        if let _ = Int(target) { return true }
        if let _ = Double(target) { return true }
        
        // String literals (quoted strings)
        if (target.hasPrefix("\"") && target.hasSuffix("\"")) ||
           (target.hasPrefix("#\"") && target.hasSuffix("\"#")) ||
           (target.hasPrefix("\"\"\"") && target.hasSuffix("\"\"\"")) {
            return true
        }
        
        // Tuple with only literals like "()" or "(1, 2)"
        if target == "()" { return true }
        
        // Self and type references are valid targets, so don't filter them
        return false
    }

    private func checkForConcurrentAccess(_ target: String) {
        guard let accesses = mutableAccesses[target] else { return }
        let writeAccesses = accesses.filter { $0.type == .write }
        guard writeAccesses.count > maxConcurrentAccess else { return }

        // Only flag as concurrent access if writes happen in OVERLAPPING scopes
        // (e.g., nested closures, inout parameters passed to same function)
        // Different methods in the same class are NOT concurrent - they execute sequentially
        
        // Check for actual concurrent access patterns:
        // 1. Same closure/function with multiple writes (could be loop or recursive)
        // 2. Nested scopes where outer scope writes and inner scope also writes
        // 3. inout parameter aliasing
        
        // Group by function - only flag if multiple writes in same function/closure
        var writesByFunction: [String: [AccessInfo]] = [:]
        for access in writeAccesses {
            let funcKey = access.function ?? "global"
            writesByFunction[funcKey, default: []].append(access)
        }
        
        // For each function, check if there are writes from nested closures
        for (funcName, funcWrites) in writesByFunction {
            // Check for closure captures that might execute concurrently
            let closureWrites = funcWrites.filter { $0.closure != nil }
            let directWrites = funcWrites.filter { $0.closure == nil }
            
            // Flag if both direct writes and closure writes exist (potential escape)
            if !closureWrites.isEmpty && !directWrites.isEmpty {
                let cacheKey = "\(target)|\(funcName)|closure_capture"
                guard !reportedConcurrentAccesses.contains(cacheKey) else { continue }
                reportedConcurrentAccesses.insert(cacheKey)
                
                guard let latestWrite = closureWrites.last else { continue }
                let locationInfo = sourceFile.location(for: latestWrite.location)
                
                violations.append(ViolationBuilder(
                    ruleId: "exclusive_access",
                    category: .memory,
                    location: locationInfo
                )
                .message("Potential exclusive access violation: '\(target)' is written both directly and in a closure in '\(funcName)'")
                .suggestFix("Use a capture list or local copy to avoid potential data races")
                .severity(.warning)
                .build())
            }
            
            // Check for multiple closure scopes (could run concurrently)
            let uniqueClosures = Set(closureWrites.compactMap { $0.closure })
            if uniqueClosures.count > 1 {
                let cacheKey = "\(target)|\(funcName)|multi_closure"
                guard !reportedConcurrentAccesses.contains(cacheKey) else { continue }
                reportedConcurrentAccesses.insert(cacheKey)
                
                guard let latestWrite = closureWrites.last else { continue }
                let locationInfo = sourceFile.location(for: latestWrite.location)
                
                violations.append(ViolationBuilder(
                    ruleId: "exclusive_access",
                    category: .memory,
                    location: locationInfo
                )
                .message("Potential exclusive access violation: '\(target)' is written in multiple closures that may execute concurrently")
                .suggestFix("Ensure closures don't run concurrently or use proper synchronization")
                .severity(.warning)
                .build())
            }
        }
    }

    private func hasThreadSafetyAttributes(_ decl: VariableDeclSyntax) -> Bool {
        for attribute in decl.attributes {
            if let attributeName = attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self) {
                let threadSafetyAttributes = [
                    "MainActor", "actor", "@unchecked", "Sendable", "synchronized"
                ]
                if threadSafetyAttributes.contains(attributeName.name.text) {
                    return true
                }
            }
        }
        return false
    }

    private func isMutableBinding(_ decl: VariableDeclSyntax) -> Bool {
        guard let bindings = decl.bindings.first else { return false }
        guard decl.bindingSpecifier.tokenKind == .keyword(.var) else { return false }
        return bindings.pattern.as(IdentifierPatternSyntax.self) != nil
    }
}

/// Information about a memory access
private struct AccessInfo {
    let target: String
    let type: AccessType
    let location: AbsolutePosition
    let function: String?
    let classContext: String?
    let closure: String?

    var scopeIdentifier: String {
        var components: [String] = []
        if let classContext {
            components.append("class \(classContext)")
        }
        if let function {
            components.append("func \(function)")
        }
        if let closure {
            components.append(closure)
        }
        if components.isEmpty {
            components.append("global")
        }
        return components.joined(separator: " > ")
    }
}

/// Types of memory access
private enum AccessType {
    case read
    case write
}
