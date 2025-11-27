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

    // Resources that require cleanup, mapped to their cleanup code
    // Only track well-known Swift types where we can reliably suggest cleanup
    // C types (OpaquePointer, sqlite3_stmt, etc.) are excluded because:
    // 1. We lack type information to determine the correct cleanup API
    // 2. The same OpaquePointer could be sqlite3*, sqlite3_stmt*, CFTypeRef, etc.
    // 3. Wrong cleanup suggestions (e.g., sqlite3_finalize for a db handle) cause bugs
    private let trackedResources: [String: String] = [
        "FileHandle": "close()",
        "InputStream": "close()",
        "OutputStream": "close()",
        "FileDescriptor": "close()",
        "DispatchIO": "close()",
        "URLSession": "invalidateAndCancel()"
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
            
            // 2. Check if it's a tracked resource and get its cleanup method
            let resourceInfo = getTrackedResourceInfo(initExpr, typeAnnotation: binding.typeAnnotation)
            guard let (resourceType, cleanupMethod) = resourceInfo else { continue }
            
            // 3. Check if there is a defer block *after* this declaration that closes it
            if !hasCleanupInDefer(varName: varName, statements: statements, startIndex: index + 1) {
                var builder = ViolationBuilder(
                    ruleId: "resource_leak",
                    category: .safety,
                    location: sourceFile.location(of: varDecl)
                )
                .severity(.warning)
                
                // Customize message based on whether auto-fix is available
                // All tracked resources now have known cleanup methods
                builder = builder
                    .message("Resource '\(varName)' created without a corresponding defer block for cleanup")
                    .suggestFix("Add 'defer { \(varName).\(cleanupMethod) }' immediately after initialization")
                
                builder = builder.addStructuredFix(
                    title: "Add defer cleanup",
                    kind: .refactor
                ) { fix in
                    // Get indentation of the current line
                    let indentation = self.getIndentation(from: varDecl)
                    
                    // Insert after the declaration
                    fix.addEdit(TextEdit.insert(
                        at: self.sourceFile.location(endOf: varDecl), 
                        text: "\n\(indentation)defer { \(varName).\(cleanupMethod) }"
                    ))
                }
                
                violations.append(builder.build())
            }
        }
    }
    
    /// Returns (resourceType, cleanupMethod) if tracked, nil if not tracked
    /// Only returns matches for well-known Swift types where cleanup is unambiguous
    private func getTrackedResourceInfo(_ initExpr: String, typeAnnotation: TypeAnnotationSyntax?) -> (String, String)? {
        // Check explicit type annotation first (most reliable)
        if let typeName = typeAnnotation?.type.trimmedDescription {
            for (resourceType, cleanup) in trackedResources {
                if typeName.contains(resourceType) {
                    return (resourceType, cleanup)
                }
            }
        }
        
        // Check initializer for known Swift types only
        // Be conservative - only match clear patterns like FileHandle.init or FileHandle(
        for (resourceType, cleanup) in trackedResources {
            // Match Type( or Type.init( patterns
            if initExpr.contains(resourceType + "(") || 
               initExpr.contains(resourceType + ".init(") ||
               initExpr.contains(resourceType + ".standardInput") ||
               initExpr.contains(resourceType + ".standardOutput") ||
               initExpr.contains(resourceType + ".standardError") {
                return (resourceType, cleanup)
            }
        }
        
        return nil
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
