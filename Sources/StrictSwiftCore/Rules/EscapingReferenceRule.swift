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
        return .skipChildren
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
        
        if !hasCaptureList && usesImplicitSelf && !allowCapturingSelf {
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
        let expressionString = expression.trimmedDescription

        // Check if returning a local variable that could escape
        if isLocalVariableReference(expressionString) && currentScope != "global" {
            let violationLocation = sourceFile.location(for: location)
            violations.append(ViolationBuilder(
                ruleId: "escaping_reference",
                category: .memory,
                location: violationLocation
            )
            .message("Returning local variable '\(expressionString)' may extend its lifetime unexpectedly")
            .suggestFix("Consider using copy or move semantics, or restructure the code")
            .severity(.warning)
            .build())
        }

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
        }
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
        // Heuristic to detect local variable references
        // In a real implementation, this would be more sophisticated
        let localVariablePatterns = [
            "let ", "var ", "self."
        ]

        for pattern in localVariablePatterns {
            if expression.contains(pattern) {
                return true
            }
        }

        return false
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
