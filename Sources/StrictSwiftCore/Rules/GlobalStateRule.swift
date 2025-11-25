import Foundation
import SwiftSyntax
import SwiftParser

/// Detects use of global mutable state using AST-based analysis
public final class GlobalStateRule: Rule {
    public var id: String { "global_state" }
    public var name: String { "Global State" }
    public var description: String { "Detects use of global mutable state" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)
        
        let analyzer = GlobalStateAnalyzer(sourceFile: sourceFile)
        analyzer.walk(tree)
        
        return analyzer.violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// AST-based analyzer for global mutable state
private final class GlobalStateAnalyzer: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []
    
    // Track nesting depth - only flag vars at depth 0 (file scope)
    private var scopeDepth = 0
    
    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }
    
    // MARK: - Scope Tracking
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        scopeDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: ClassDeclSyntax) {
        scopeDepth -= 1
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        scopeDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: StructDeclSyntax) {
        scopeDepth -= 1
    }
    
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        scopeDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: EnumDeclSyntax) {
        scopeDepth -= 1
    }
    
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        scopeDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: ActorDeclSyntax) {
        scopeDepth -= 1
    }
    
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        scopeDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: ExtensionDeclSyntax) {
        scopeDepth -= 1
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        scopeDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: FunctionDeclSyntax) {
        scopeDepth -= 1
    }
    
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        scopeDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: InitializerDeclSyntax) {
        scopeDepth -= 1
    }
    
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        scopeDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: ClosureExprSyntax) {
        scopeDepth -= 1
    }
    
    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        scopeDepth += 1
        return .visitChildren
    }
    
    override func visitPost(_ node: AccessorDeclSyntax) {
        scopeDepth -= 1
    }
    
    // MARK: - Variable Detection
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Only flag `var` declarations (not `let`)
        guard node.bindingSpecifier.text == "var" else {
            return .skipChildren
        }
        
        // Check if this is a truly global variable (file scope, depth 0)
        let isFileScope = scopeDepth == 0
        
        // Check for static/class variables (these are global state even inside types)
        let isStatic = node.modifiers.contains { modifier in
            modifier.name.text == "static" || modifier.name.text == "class"
        }
        
        // Check access level
        let isPrivate = node.modifiers.contains { modifier in
            modifier.name.text == "private" || modifier.name.text == "fileprivate"
        }
        
        // Flag:
        // 1. File-scope `var` (true global variables)
        // 2. Non-private static/class var (shared mutable state)
        let shouldFlag = isFileScope || (isStatic && !isPrivate)
        
        if shouldFlag {
            let location = sourceFile.location(for: node.position)
            let varName = node.bindings.first?.pattern.trimmedDescription ?? "unknown"
            
            let message: String
            if isFileScope {
                message = "Global mutable variable '\(varName)' at file scope"
            } else {
                message = "Static/class mutable variable '\(varName)' is shared mutable state"
            }
            
            violations.append(ViolationBuilder(
                ruleId: "global_state",
                category: .architecture,
                location: location
            )
            .message(message)
            .suggestFix("Consider using dependency injection, actor isolation, or making it immutable (let)")
            .severity(.warning)
            .build())
        }
        
        return .skipChildren
    }
    
    // MARK: - Singleton Access Detection
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let memberName = node.declName.baseName.text
        let baseExpr = node.base?.trimmedDescription ?? ""
        
        // Known problematic singleton patterns
        let problematicSingletons: [String: Set<String>] = [
            "UserDefaults": ["standard"],
            "FileManager": ["default"],
            "NotificationCenter": ["default"],
            "URLSession": ["shared"],
            "URLCache": ["shared"],
            "HTTPCookieStorage": ["shared"],
            "UIApplication": ["shared"],
            "NSApplication": ["shared"]
        ]
        
        if let members = problematicSingletons[baseExpr], members.contains(memberName) {
            let location = sourceFile.location(for: node.position)
            
            violations.append(ViolationBuilder(
                ruleId: "global_state",
                category: .architecture,
                location: location
            )
            .message("Access to global singleton '\(baseExpr).\(memberName)'")
            .suggestFix("Consider injecting this dependency instead of accessing the global singleton")
            .severity(.warning)
            .build())
        }
        
        return .visitChildren
    }
}