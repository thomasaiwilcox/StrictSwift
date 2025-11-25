import Foundation
import SwiftSyntax

/// Detects shared mutable state between tests that can cause test isolation issues
public final class TestIsolationRule: Rule {
    public var id: String { "test_isolation" }
    public var name: String { "Test Isolation" }
    public var description: String { "Detects shared mutable state between tests that can cause flaky or order-dependent tests" }
    public var category: RuleCategory { .testing }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = TestIsolationVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        let path = sourceFile.url.path.lowercased()
        return sourceFile.url.pathExtension == "swift" &&
               (path.contains("test") || path.contains("spec"))
    }
}

/// Syntax visitor that finds test isolation issues
private final class TestIsolationVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// Track if we're in a test class
    private var inTestClass = false
    private var testClassStack: [Bool] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let isTestClass = isXCTestCaseSubclass(node.inheritanceClause)
        testClassStack.append(inTestClass)
        inTestClass = isTestClass
        return .visitChildren
    }
    
    override func visitPost(_ node: ClassDeclSyntax) {
        inTestClass = testClassStack.popLast() ?? false
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for static var in test classes
        if inTestClass {
            let isStatic = node.modifiers.contains { modifier in
                modifier.name.tokenKind == .keyword(.static) ||
                modifier.name.tokenKind == .keyword(.class)
            }
            
            let isVar = node.bindingSpecifier.tokenKind == .keyword(.var)
            
            if isStatic && isVar {
                let location = sourceFile.location(of: node)
                
                violations.append(
                    ViolationBuilder(
                        ruleId: "test_isolation",
                        category: .testing,
                        location: location
                    )
                    .message("Static mutable variable in test class can cause test isolation issues")
                    .suggestFix("Use instance variables and setUp/tearDown, or make static properties immutable")
                    .severity(.warning)
                    .build()
                )
            }
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let fullExpr = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        
        // Check for UserDefaults.standard mutations
        if fullExpr.contains("UserDefaults.standard") {
            let functionName = extractFunctionName(from: node.calledExpression)
            let mutatingMethods = ["set", "setValue", "setObject", "setBool", "setInteger", "setFloat", "setDouble", "removeObject"]
            
            if mutatingMethods.contains(functionName) {
                let location = sourceFile.location(of: node)
                violations.append(
                    ViolationBuilder(
                        ruleId: "test_isolation",
                        category: .testing,
                        location: location
                    )
                    .message("Mutating UserDefaults.standard in tests affects other tests")
                    .suggestFix("Use a test-specific UserDefaults suite or mock UserDefaults")
                    .severity(.warning)
                    .build()
                )
            }
        }
        
        // Check for FileManager default operations
        if fullExpr.contains("FileManager.default") {
            let functionName = extractFunctionName(from: node.calledExpression)
            let mutatingMethods = [
                "createFile", "createDirectory", "removeItem", "moveItem",
                "copyItem", "trashItem", "setAttributes"
            ]
            
            if mutatingMethods.contains(functionName) {
                // Check if it's writing to a non-temp directory
                if !isWritingToTempDirectory(node) {
                    let location = sourceFile.location(of: node)
                    violations.append(
                        ViolationBuilder(
                            ruleId: "test_isolation",
                            category: .testing,
                            location: location
                        )
                        .message("File system operations in tests should use temporary directories")
                        .suggestFix("Use FileManager.default.temporaryDirectory or NSTemporaryDirectory()")
                        .severity(.info)
                        .build()
                    )
                }
            }
        }
        
        // Check for singleton access patterns that might share state
        if fullExpr.contains(".shared") || fullExpr.contains(".default") || fullExpr.contains(".current") {
            // Only flag if it's an assignment or mutation
            if let parent = node.parent {
                if isInMutatingContext(Syntax(node), parent: parent) {
                    let location = sourceFile.location(of: node)
                    violations.append(
                        ViolationBuilder(
                            ruleId: "test_isolation",
                            category: .testing,
                            location: location
                        )
                        .message("Mutating shared/singleton state in tests can affect other tests")
                        .suggestFix("Use dependency injection or create test-specific instances")
                        .severity(.info)
                        .build()
                    )
                }
            }
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for accessing global mutable state
        let memberName = node.declName.baseName.text
        
        // Check for environment variable mutations
        if let base = node.base, base.description.contains("ProcessInfo") {
            if memberName == "environment" {
                // This is read-only in Swift, but flag any access pattern that suggests mutation
                // (e.g., via setenv)
            }
        }
        
        return .visitChildren
    }
    
    private func extractFunctionName(from expr: ExprSyntax) -> String {
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
        return ""
    }
    
    private func isXCTestCaseSubclass(_ inheritanceClause: InheritanceClauseSyntax?) -> Bool {
        guard let inheritance = inheritanceClause else {
            return false
        }
        
        for inheritedType in inheritance.inheritedTypes {
            let typeName = inheritedType.type.description.trimmingCharacters(in: .whitespaces)
            if typeName == "XCTestCase" || typeName.hasSuffix("TestCase") {
                return true
            }
        }
        
        return false
    }
    
    private func isWritingToTempDirectory(_ node: FunctionCallExprSyntax) -> Bool {
        // Check if any argument contains temp directory references
        let fullCallText = node.description.lowercased()
        let tempIndicators = [
            "temporarydirectory", "nstemporarydirectory", "tmp", "temp",
            "fileprovider.temporarydirectory"
        ]
        
        for indicator in tempIndicators {
            if fullCallText.contains(indicator) {
                return true
            }
        }
        
        return false
    }
    
    private func isInMutatingContext(_ node: Syntax, parent: Syntax) -> Bool {
        // Check if the node is on the left side of an assignment
        if let infixOp = parent.as(InfixOperatorExprSyntax.self) {
            let opText = infixOp.operator.description.trimmingCharacters(in: .whitespaces)
            if opText == "=" {
                // Check if node is the left operand
                return infixOp.leftOperand.description.contains(node.description)
            }
        }
        
        // Check if it's in a function call that mutates
        if let funcCall = parent.as(FunctionCallExprSyntax.self) {
            let funcName = extractFunctionName(from: funcCall.calledExpression)
            let mutatingFuncs = ["set", "update", "remove", "add", "insert", "delete", "clear", "reset"]
            return mutatingFuncs.contains(where: { funcName.lowercased().contains($0) })
        }
        
        return false
    }
}
