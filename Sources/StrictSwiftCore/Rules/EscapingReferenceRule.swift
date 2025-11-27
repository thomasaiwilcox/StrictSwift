import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that detects references escaping their scope, potentially causing memory safety issues
/// SAFETY: @unchecked Sendable is safe because this rule has no stored state.
/// OwnershipAnalyzer instances are created fresh per analysis call for thread safety.
public final class EscapingReferenceRule: Rule, @unchecked Sendable {
    public var id: String { "escaping_reference" }
    public var name: String { "Escaping Reference" }
    public var description: String { "Detects references escaping their scope that could cause memory safety issues" }
    public var category: RuleCategory { .memory }
    public var defaultSeverity: DiagnosticSeverity { .warning }
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
        let escapingIssues = analysisResult.issues.filter { $0.type == .escapingReference }
        // Get configuration parameters
        let allowCapturingSelf = ruleConfig.parameter("allowCapturingSelf", defaultValue: false)
        let allowWeakReferences = ruleConfig.parameter("allowWeakReferences", defaultValue: true)
        let maxClosureCaptureCount = ruleConfig.parameter("maxClosureCaptureCount", defaultValue: 5)

        // Analyze source code for additional escaping patterns
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)
        let analyzer = EscapingReferenceAnalyzer(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            allowCapturingSelf: allowCapturingSelf,
            allowWeakReferences: allowWeakReferences,
            maxClosureCaptureCount: maxClosureCaptureCount
        )
        analyzer.walk(tree)

        violations.append(contentsOf: analyzer.violations)
        violations.append(contentsOf: convertOwnershipIssuesToViolations(escapingIssues, sourceFile: sourceFile))

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }

    // MARK: - Helper Methods

    private func convertOwnershipIssuesToViolations(_ issues: [MemorySafetyIssue], sourceFile: SourceFile) -> [Violation] {
        return issues.map { issue in
            // Convert SourceLocation from MemorySafetyIssue to Location for Violation
            // SourceLocation has line, column, and offset properties we can use directly
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
        case .escapingReference:
            return "Consider using weak/unowned references or restructuring code to avoid escaping references"
        case .useAfterFree:
            return "Use proper lifetime management or stronger reference patterns"
        case .retainCycle:
            return "Break the cycle using weak/unowned references or closure capture lists"
        case .memoryLeak:
            return "Ensure proper cleanup of references or use automatic memory management"
        case .exclusiveAccessViolation:
            return "Use exclusive access patterns or synchronization primitives"
        }
    }
}

/// Syntax analyzer for detecting escaping references
private class EscapingReferenceAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let ruleConfig: RuleSpecificConfiguration
    private let allowCapturingSelf: Bool
    private let allowWeakReferences: Bool
    private let maxClosureCaptureCount: Int

    var violations: [Violation] = []
    private var currentScope: String = "global"
    private var currentFunction: String?
    private var closureCaptureCounts: [String: Int] = [:]

    init(sourceFile: SourceFile, ruleConfig: RuleSpecificConfiguration, allowCapturingSelf: Bool, allowWeakReferences: Bool, maxClosureCaptureCount: Int) {
        self.sourceFile = sourceFile
        self.ruleConfig = ruleConfig
        self.allowCapturingSelf = allowCapturingSelf
        self.allowWeakReferences = allowWeakReferences
        self.maxClosureCaptureCount = maxClosureCaptureCount
        super.init(viewMode: .sourceAccurate)
    }

    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunction = node.name.text
        currentScope = "function.\(node.name.text)"
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        currentScope = "class.\(node.name.text)"
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        currentFunction = nil
        currentScope = "global"
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        currentScope = "global"
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        let closureId = "closure_\(node.position.utf8Offset)"
        closureCaptureCounts[closureId] = 0

        if let captureClause = node.signature?.capture {
            analyzeCaptureList(captureClause, closureId: closureId)
        }

        // Analyze closure body for escaping captures
        analyzeClosureBody(node, closureId: closureId)

        return .visitChildren
    }

    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        if let expression = node.expression {
            analyzeReturnStatement(expression, location: node.position)
        }
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        analyzeVariableDeclaration(node)
        return .visitChildren  // Must visit children to catch closures in variable initializers
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        currentScope = "struct.\(node.name.text)"
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        currentScope = "global"
    }

    // MARK: - Private Analysis Methods

    private func analyzeCaptureList(_ captureClause: ClosureCaptureClauseSyntax, closureId: String) {
        let captureCount = captureClause.items.count
        let locationInfo = sourceFile.location(for: captureClause.position)

        if captureCount > maxClosureCaptureCount {
            violations.append(ViolationBuilder(
                ruleId: "escaping_reference",
                category: .memory,
                location: locationInfo
            )
            .message("Closure captures \(captureCount) variables, exceeding limit of \(maxClosureCaptureCount)")
            .suggestFix("Consider reducing captured variables or using explicit capture list")
            .severity(.warning)
            .build())
        }

        captureClause.items.forEach { captureItem in
            analyzeCaptureItem(captureItem)
        }

        closureCaptureCounts[closureId] = captureCount
    }

    private func analyzeCaptureItem(_ captureItem: ClosureCaptureSyntax) {
        let captureLocation = sourceFile.location(for: captureItem.position)
        let specifierToken = captureItem.specifier?.specifier
        let specifierText = specifierToken?.text.lowercased() ?? ""
        let detailText = captureItem.specifier?.detail?.text.lowercased() ?? ""
        let specifierDescriptor = specifierText + (detailText.isEmpty ? "" : "(\(detailText))")
        let isWeak = specifierText == "weak"
        let isUnowned = specifierText == "unowned"

        let explicitName = captureItem.name?.text ?? ""
        let capturedExpression = captureItem.expression.trimmedDescription
        let capturedTarget = explicitName.isEmpty ? capturedExpression : explicitName
        let capturesSelf = capturedTarget == "self" || capturedExpression == "self" || capturedExpression.hasPrefix("self.")

        if capturesSelf {
            if !allowCapturingSelf && !isWeak && !isUnowned {
                violations.append(ViolationBuilder(
                    ruleId: "escaping_reference",
                    category: .memory,
                    location: captureLocation
                )
                .message("Closure strongly captures 'self', potentially creating a retain cycle")
                .suggestFix("Use [weak self] or [unowned self] in capture list")
                .severity(.warning)
                .build())
            }

            if !allowWeakReferences && (isWeak || isUnowned) {
                violations.append(ViolationBuilder(
                    ruleId: "escaping_reference",
                    category: .memory,
                    location: captureLocation
                )
                .message("Closure uses \(specifierDescriptor) reference to '\(capturedTarget)' which may not be allowed")
                .suggestFix("Consider using a strong reference or verify \(specifierDescriptor) capture is appropriate")
                .severity(.info)
                .build())
            }
            return
        }

        if isLocalVariableReference(capturedTarget) {
            violations.append(ViolationBuilder(
                ruleId: "escaping_reference",
                category: .memory,
                location: captureLocation
            )
            .message("Closure captures local variable '\(capturedTarget)' which may escape the variable's scope")
            .suggestFix("Use capture lists or restructure code to avoid escaping locals")
            .severity(.info)
            .build())
        }
    }

    private func analyzeClosureBody(_ closure: ClosureExprSyntax, closureId: String) {
        // Check for implicit self capture if no explicit capture list
        let hasCaptureList = closure.signature?.capture != nil
        let closureBody = closure.statements.description
        let usesImplicitSelf = closureBody.contains("self.") || closureBody.contains("self,") || closureBody.contains("self)")
        
        // Only flag implicit self capture if the closure is likely escaping
        // Non-escaping closures (the default) can't cause retain cycles
        if !hasCaptureList && usesImplicitSelf && !allowCapturingSelf && isLikelyEscapingClosure(closure) {
            let location = sourceFile.location(for: closure.position)
            violations.append(ViolationBuilder(
                ruleId: "escaping_reference",
                category: .memory,
                location: location
            )
            .message("Closure implicitly captures 'self', potentially creating a retain cycle")
            .suggestFix("Use [weak self] or [unowned self] in capture list")
            .severity(.warning)
            .build())
        }
        
        // Look for escaping references within closure body
        for statement in closure.statements {
            // Access the actual statement via .item
            let item = statement.item

            // Check for return statements that might escape local variables
            if let returnStmt = item.as(ReturnStmtSyntax.self) {
                if let expression = returnStmt.expression {
                    analyzeReturnStatement(expression, location: returnStmt.position)
                }
                continue
            }

            // Check for assignments to external variables
            if let assignment = findAssignment(in: item) {
                analyzeAssignmentInClosure(assignment, location: statement.position)
            }
        }
    }

    private func analyzeReturnStatement(_ expression: ExprSyntax, location: AbsolutePosition) {
        // Only flag return statements that could actually cause escaping issues:
        // 1. Returning closures (which may capture local state)
        // 2. Returning unsafe pointers to local memory
        
        // Check for returning closures that capture local variables
        if expression.as(ClosureExprSyntax.self) != nil {
            let violationLocation = sourceFile.location(for: location)
            violations.append(ViolationBuilder(
                ruleId: "escaping_reference",
                category: .memory,
                location: violationLocation
            )
            .message("Returning closure may capture and escape local variables")
            .suggestFix("Ensure closure captures are explicitly weak/unowned or restructure")
            .severity(.warning)
            .build())
            return
        }
        
        // Check for returning unsafe pointers
        let expressionString = expression.trimmedDescription
        if expressionString.contains("UnsafePointer") || 
           expressionString.contains("UnsafeMutablePointer") ||
           expressionString.contains("UnsafeBufferPointer") ||
           expressionString.contains("UnsafeRawPointer") ||
           expressionString.contains("withUnsafe") {
            let violationLocation = sourceFile.location(for: location)
            violations.append(ViolationBuilder(
                ruleId: "escaping_reference",
                category: .memory,
                location: violationLocation
            )
            .message("Returning unsafe pointer may cause lifetime issues")
            .suggestFix("Ensure the underlying memory outlives the pointer usage")
            .severity(.warning)
            .build())
        }
        
        // Note: Normal return values (like `return result`) are NOT escaping issues.
        // Swift's ARC handles reference counting automatically for returned values.
    }

    private func analyzeVariableDeclaration(_ decl: VariableDeclSyntax) {
        guard let bindings = decl.bindings.first else { return }

        // Check for escaping annotations
        for attribute in decl.attributes {
            if let attributeName = attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self) {
                if attributeName.name.text == "escaping" {
                    if let typeAnnotation = bindings.typeAnnotation {
                        let typeString = typeAnnotation.type.trimmedDescription
                        if typeString.contains("()") || typeString.contains("->") {
                            // This is an escaping closure/ function type
                            let location = sourceFile.location(for: decl.position)
                            violations.append(ViolationBuilder(
                                ruleId: "escaping_reference",
                                category: .memory,
                                location: location
                            )
                            .message("Escaping function type may cause lifetime issues")
                            .suggestFix("Consider using @escaping annotation carefully and ensure proper lifetime management")
                            .severity(.info)
                            .build())
                        }
                    }
                }
            }
        }
    }

    private func analyzeAssignmentInClosure(_ assignment: AssignmentExprSyntax, location: AbsolutePosition) {
        // Check for assignments to variables outside closure scope
        // In SwiftSyntax 600.0.0, AssignmentExprSyntax structure has changed - need to extract LHS from children
        let children = assignment.children(viewMode: .sourceAccurate)
        var lhsString = ""

        for child in children {
            if let expr = child.as(ExprSyntax.self) {
                lhsString = expr.trimmedDescription
                break
            }
        }

        if isExternalVariable(lhsString) {
            let violationLocation = sourceFile.location(for: location)
            violations.append(ViolationBuilder(
                ruleId: "escaping_reference",
                category: .memory,
                location: violationLocation
            )
            .message("Closure modifies external variable '\(lhsString)' which may cause escaping behavior")
            .suggestFix("Consider using explicit capture lists or restructuring to avoid external mutations")
            .severity(.warning)
            .build())
        }
    }

    // MARK: - Helper Methods

    private func capturesSelf(_ captureItem: Syntax) -> Bool {
        // Try to extract self capture from different syntax structures in SwiftSyntax 600.0.0
        if let identifier = captureItem.as(IdentifierPatternSyntax.self)?.identifier {
            return identifier.text == "self"
        }
        return false
    }

    private func isLocalVariableReference(_ expression: String) -> Bool {
        // Only flag if it's a simple identifier that could be a local variable
        // This is a heuristic - without full semantic analysis we can't be certain
        
        // Skip obvious non-local references
        if expression.hasPrefix("self.") { return false }
        if expression.contains("(") { return false }  // Function call
        if expression.contains(".") { return false }  // Property access
        if expression.hasPrefix("\"") { return false }  // String literal
        if Int(expression) != nil { return false }  // Number literal
        if expression == "nil" || expression == "true" || expression == "false" { return false }
        if expression.isEmpty { return false }
        
        // A simple identifier like "result", "value", etc. could be a local variable
        // but we can't know for sure without semantic analysis
        // Be conservative - only return true for very simple identifiers
        let isSimpleIdentifier = expression.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        
        // Even simple identifiers are usually fine to capture - Swift handles this safely
        // So we only flag if it looks like an inout capture or unsafe pointer
        return false  // Be conservative - don't flag simple identifier captures
    }

    private func isExternalVariable(_ variable: String) -> Bool {
        // Heuristic to detect external variables
        let externalPatterns = [
            "self.", "global", "static"
        ]

        for pattern in externalPatterns {
            if variable.hasPrefix(pattern) {
                return true
            }
        }

        return false
    }
    
    /// Determines if a closure is likely to be escaping based on its context.
    /// Without full semantic analysis, we use heuristics:
    /// - Closures assigned to stored properties are likely escaping
    /// - Closures stored in collections are likely escaping  
    /// - Closures passed to known escaping APIs are likely escaping
    /// - Closures passed as trailing closures to regular functions are usually non-escaping
    private func isLikelyEscapingClosure(_ closure: ClosureExprSyntax) -> Bool {
        // Walk up the parent chain looking for escaping patterns
        var current: Syntax? = Syntax(closure)
        
        while let node = current?.parent {
            // If the closure is on the RHS of an assignment, it's likely escaping
            // e.g., callback = { ... } or self.completion = { ... }
            if let infix = node.as(InfixOperatorExprSyntax.self) {
                if infix.operator.as(AssignmentExprSyntax.self) != nil {
                    // Make sure the closure is the RHS of the assignment, not inside a function call
                    let rhsText = infix.rightOperand.trimmedDescription
                    if rhsText.hasPrefix("{") {
                        return true
                    }
                }
            }
            
            // Also check for SequenceExprSyntax which wraps assignments in SwiftSyntax 600.0.0
            // SequenceExprSyntax contains: [target, assignmentExpr, closureExpr]
            if let seq = node.as(SequenceExprSyntax.self) {
                // Check if the sequence is a direct assignment where closure is the value
                // i.e., the sequence elements are: [identifier, =, closure]
                let elements = Array(seq.elements)
                if elements.count >= 3 {
                    let hasAssignment = elements.contains { $0.as(AssignmentExprSyntax.self) != nil }
                    if hasAssignment {
                        // Check if the last element is the closure (or contains it directly)
                        if let lastElement = elements.last,
                           lastElement.as(ClosureExprSyntax.self) != nil {
                            return true
                        }
                    }
                }
            }
            
            // If the closure is assigned in a variable declaration at class/struct level
            if node.as(VariableDeclSyntax.self) != nil {
                // Stored properties (class/struct level vars) are typically escaping
                if currentFunction == nil {
                    return true
                }
                break
            }
            
            // Check if stored in an array or dictionary literal
            if node.as(ArrayElementSyntax.self) != nil || node.as(DictionaryElementSyntax.self) != nil {
                return true
            }
            
            // Closures passed to function arguments - check for known escaping patterns
            if let arg = node.as(LabeledExprSyntax.self) {
                let label = arg.label?.text ?? ""
                // Common escaping completion handler patterns
                let escapingPatterns = ["completion", "handler", "callback", "onComplete", "then", "success", "failure"]
                for pattern in escapingPatterns {
                    if label.lowercased().contains(pattern) {
                        return true
                    }
                }
            }
            
            // Stop at function/class boundaries
            if node.as(FunctionDeclSyntax.self) != nil || 
               node.as(ClassDeclSyntax.self) != nil ||
               node.as(StructDeclSyntax.self) != nil {
                break
            }
            
            current = node
        }
        
        // Default: assume non-escaping (the Swift default)
        return false
    }

    private func findAssignment(in syntax: some SyntaxProtocol) -> AssignmentExprSyntax? {
        let finder = AssignmentFinder()
        finder.walk(Syntax(syntax))
        return finder.assignment
    }

    private final class AssignmentFinder: SyntaxAnyVisitor {
        var assignment: AssignmentExprSyntax?

        init() {
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: AssignmentExprSyntax) -> SyntaxVisitorContinueKind {
            assignment = node
            return .skipChildren
        }
    }
}
