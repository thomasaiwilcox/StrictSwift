import SwiftSyntax

/// Rule that enforces safe resource management using defer blocks
/// SAFETY: @unchecked Sendable is safe because the rule is stateless.
public final class ResourceLeakRule: Rule, @unchecked Sendable {
    public var id: String { "resource_leak" }
    public var name: String { "Resource Leak Prevention" }
    public var description: String { "Enforces the use of defer blocks for resource cleanup to prevent leaks" }
    public var category: RuleCategory { .safety }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let visitor = ResourceLeakVisitor(sourceFile: sourceFile)
        visitor.walk(sourceFile.tree)
        return visitor.violations
    }
}

private final class ResourceLeakVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    // Resources that require cleanup
    private let trackedTypes = [
        "FileHandle",
        "InputStream",
        "OutputStream",
        "sqlite3_stmt",
        "OpaquePointer" // Often used for C resources
    ]
    
    private let cleanupMethods = [
        "close",
        "closeFile",
        "deallocate",
        "finalize"
    ]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        // We analyze each code block (function body, if body, etc.) independently
        analyzeBlock(node)
        return .visitChildren
    }
    
    private func analyzeBlock(_ block: CodeBlockSyntax) {
        let statements = Array(block.statements)
        
        for (index, stmt) in statements.enumerated() {
            // 1. Find variable declarations
            guard let varDecl = stmt.item.as(VariableDeclSyntax.self) else { continue }
            
            analyzeVariableDeclaration(varDecl, statements: statements, index: index)
        }
    }
    
    private func analyzeVariableDeclaration(_ varDecl: VariableDeclSyntax, statements: [CodeBlockItemSyntax], index: Int) {
        for binding in varDecl.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let initializer = binding.initializer else { continue }
            
            let varName = pattern.identifier.text
            let initExpr = initializer.value.trimmedDescription
            
            // 2. Check if it's a tracked resource
            if isTrackedResource(initExpr, typeAnnotation: binding.typeAnnotation) {
                // 3. Check if there is a defer block *after* this declaration that closes it
                if !hasCleanupInDefer(varName: varName, statements: statements, startIndex: index + 1) {
                    var builder = ViolationBuilder(
                        ruleId: "resource_leak",
                        category: .safety,
                        location: sourceFile.location(of: varDecl)
                    )
                    .message("Resource '\(varName)' created without a corresponding defer block for cleanup")
                    .suggestFix("Add 'defer { \(varName).close() }' immediately after initialization")
                    .severity(.warning)
                    
                    // Auto-fix
                    builder = builder.addStructuredFix(
                        title: "Add defer cleanup",
                        kind: .refactor
                    ) { fix in
                        // Get indentation of the current line
                        let indentation = self.getIndentation(from: varDecl)
                        
                        // Insert after the declaration
                        fix.addEdit(TextEdit.insert(
                            at: self.sourceFile.location(endOf: varDecl), 
                            text: "\n\(indentation)defer { \(varName).close() }"
                        ))
                    }
                    
                    violations.append(builder.build())
                }
            }
        }
    }
    
    private func isTrackedResource(_ initExpr: String, typeAnnotation: TypeAnnotationSyntax?) -> Bool {
        // Check explicit type annotation
        if let typeName = typeAnnotation?.type.trimmedDescription {
            if trackedTypes.contains(where: { typeName.contains($0) }) {
                return true
            }
        }
        
        // Check initializer type (heuristic)
        return trackedTypes.contains { type in
            initExpr.contains(type + "(") || // Constructor: FileHandle(...)
            initExpr.contains(type + ".")    // Factory: FileHandle.standardInput
        }
    }
    
    private func hasCleanupInDefer(varName: String, statements: [CodeBlockItemSyntax], startIndex: Int) -> Bool {
        // Look through remaining statements for a defer block
        for i in startIndex..<statements.count {
            let stmt = statements[i]
            
            if let deferStmt = stmt.item.as(DeferStmtSyntax.self) {
                if closesResource(varName: varName, in: deferStmt.body) {
                    return true
                }
            }
        }
        return false
    }
    
    private func closesResource(varName: String, in body: CodeBlockSyntax) -> Bool {
        // Check if the defer body contains variable.close() or similar
        // We need to be careful about optional chaining (var?.close())
        let bodyText = body.trimmedDescription
        
        return cleanupMethods.contains { method in
            bodyText.contains("\(varName).\(method)()") || 
            bodyText.contains("\(varName)?.\(method)()")
        }
    }
    
    private func getIndentation(from node: SyntaxProtocol) -> String {
        for piece in node.leadingTrivia.reversed() {
            if case .spaces(let count) = piece {
                return String(repeating: " ", count: count)
            }
            if case .tabs(let count) = piece {
                return String(repeating: "\t", count: count)
            }
        }
        return ""
    }
}
