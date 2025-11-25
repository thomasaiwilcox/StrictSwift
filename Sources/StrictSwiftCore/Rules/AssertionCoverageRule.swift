import Foundation
import SwiftSyntax

/// Detects test methods that have no assertions
public final class AssertionCoverageRule: Rule {
    public var id: String { "assertion_coverage" }
    public var name: String { "Test Assertion Coverage" }
    public var description: String { "Detects test methods without any assertions, which may indicate incomplete tests" }
    public var category: RuleCategory { .testing }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = AssertionCoverageVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        let path = sourceFile.url.path.lowercased()
        // Only analyze test files
        return sourceFile.url.pathExtension == "swift" &&
               (path.contains("test") || path.contains("spec"))
    }
}

/// Syntax visitor that checks test methods for assertions
private final class AssertionCoverageVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    /// XCTest assertion functions
    private static let xctestAssertions: Set<String> = [
        "XCTAssert", "XCTAssertTrue", "XCTAssertFalse",
        "XCTAssertNil", "XCTAssertNotNil",
        "XCTAssertEqual", "XCTAssertNotEqual",
        "XCTAssertIdentical", "XCTAssertNotIdentical",
        "XCTAssertGreaterThan", "XCTAssertGreaterThanOrEqual",
        "XCTAssertLessThan", "XCTAssertLessThanOrEqual",
        "XCTAssertThrowsError", "XCTAssertNoThrow",
        "XCTFail", "XCTSkip", "XCTSkipIf", "XCTSkipUnless",
        "XCTUnwrap", "XCTExpectFailure"
    ]
    
    /// Swift Testing macros
    private static let swiftTestingAssertions: Set<String> = [
        "#expect", "#require", "expect", "require",
        "Issue.record", "withKnownIssue"
    ]
    
    /// Track if we're in a test class
    private var inTestClass = false
    private var testClassStack: [Bool] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if this is a test class (inherits from XCTestCase)
        let isTestClass = isXCTestCaseSubclass(node.inheritanceClause)
        testClassStack.append(inTestClass)
        inTestClass = isTestClass
        return .visitChildren
    }
    
    override func visitPost(_ node: ClassDeclSyntax) {
        inTestClass = testClassStack.popLast() ?? false
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for XCTest test methods (func test...)
        let functionName = node.name.text
        let isXCTestMethod = inTestClass && functionName.hasPrefix("test")
        
        // Check for Swift Testing @Test attribute
        let hasTestAttribute = node.attributes.contains { attr in
            if case .attribute(let attribute) = attr {
                let attrName = attribute.attributeName.description.trimmingCharacters(in: .whitespaces)
                return attrName == "Test"
            }
            return false
        }
        
        guard isXCTestMethod || hasTestAttribute else {
            return .visitChildren
        }
        
        // Check if the function body contains assertions
        guard let body = node.body else {
            return .visitChildren
        }
        
        let assertionChecker = AssertionChecker()
        assertionChecker.walk(body)
        
        if !assertionChecker.hasAssertion && !assertionChecker.hasThrow {
            let location = sourceFile.location(of: node)
            
            violations.append(
                ViolationBuilder(
                    ruleId: "assertion_coverage",
                    category: .testing,
                    location: location
                )
                .message("Test method '\(functionName)' has no assertions")
                .suggestFix("Add XCTAssert*, #expect, or throw to verify expected behavior")
                .severity(.warning)
                .build()
            )
        }
        
        return .skipChildren // Don't need to visit nested functions
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
}

/// Helper visitor to check for assertions in a function body
private final class AssertionChecker: SyntaxVisitor {
    var hasAssertion = false
    var hasThrow = false
    
    /// XCTest assertion functions
    private static let xctestAssertions: Set<String> = [
        "XCTAssert", "XCTAssertTrue", "XCTAssertFalse",
        "XCTAssertNil", "XCTAssertNotNil",
        "XCTAssertEqual", "XCTAssertNotEqual",
        "XCTAssertIdentical", "XCTAssertNotIdentical",
        "XCTAssertGreaterThan", "XCTAssertGreaterThanOrEqual",
        "XCTAssertLessThan", "XCTAssertLessThanOrEqual",
        "XCTAssertThrowsError", "XCTAssertNoThrow",
        "XCTFail", "XCTSkip", "XCTSkipIf", "XCTSkipUnless",
        "XCTUnwrap", "XCTExpectFailure"
    ]
    
    init() {
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let functionName = extractFunctionName(from: node.calledExpression)
        
        // Check XCTest assertions
        if Self.xctestAssertions.contains(functionName) {
            hasAssertion = true
        }
        
        // Check for Issue.record (Swift Testing)
        if functionName == "record" {
            let fullExpr = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
            if fullExpr.contains("Issue") {
                hasAssertion = true
            }
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        // Check Swift Testing macros (#expect, #require)
        let macroName = node.macroName.text
        if macroName == "expect" || macroName == "require" {
            hasAssertion = true
        }
        return .visitChildren
    }
    
    override func visit(_ node: ThrowStmtSyntax) -> SyntaxVisitorContinueKind {
        // Throwing an error is a valid test assertion mechanism
        hasThrow = true
        return .visitChildren
    }
    
    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        // try expression without ? or ! can throw
        if node.questionOrExclamationMark == nil {
            // This is a plain `try` which propagates errors
            hasThrow = true
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
}
