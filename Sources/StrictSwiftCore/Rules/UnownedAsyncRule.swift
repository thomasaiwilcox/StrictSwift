import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that detects [unowned self] usage in async contexts like Task closures
/// Using unowned in async contexts is dangerous because Tasks can outlive the captured object
/// This rule uses .error severity because it's a likely crash, not just a leak
public final class UnownedAsyncRule: Rule, @unchecked Sendable {
    public var id: String { "unowned_async" }
    public var name: String { "Unowned in Async Context" }
    public var description: String { "Detects dangerous use of [unowned self] in async closures that may outlive the object" }
    public var category: RuleCategory { .concurrency }
    public var defaultSeverity: DiagnosticSeverity { .error }  // Crash risk, not just a leak
    public var enabledByDefault: Bool { true }
    
    public init() {}
    
    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }
        
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)
        
        let analyzer = UnownedAsyncAnalyzer(sourceFile: sourceFile)
        analyzer.walk(tree)
        
        return analyzer.violations
    }
    
    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Analyzes unowned usage in async contexts
private class UnownedAsyncAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    var violations: [Violation] = []
    
    // Track async context depth
    private var asyncContextStack: [AsyncContext] = []
    
    // Track closures we've already analyzed to avoid duplicates
    private var analyzedClosures: Set<SyntaxIdentifier> = []
    
    private enum AsyncContext {
        case task
        case taskDetached
        case asyncClosure
        case asyncFunction
    }
    
    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }
    
    // Track Task { } and Task.detached { }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let context = identifyAsyncContext(node)
        
        if let ctx = context {
            asyncContextStack.append(ctx)
            
            // Check trailing closure
            if let trailingClosure = node.trailingClosure {
                checkClosureCaptureList(trailingClosure, context: ctx)
            }
            
            // Check closure arguments
            for arg in node.arguments {
                if let closure = arg.expression.as(ClosureExprSyntax.self) {
                    checkClosureCaptureList(closure, context: ctx)
                }
            }
        }
        
        return .visitChildren
    }
    
    override func visitPost(_ node: FunctionCallExprSyntax) {
        if identifyAsyncContext(node) != nil && !asyncContextStack.isEmpty {
            asyncContextStack.removeLast()
        }
    }
    
    // Track async functions
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.signature.effectSpecifiers?.asyncSpecifier != nil {
            asyncContextStack.append(.asyncFunction)
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: FunctionDeclSyntax) {
        if node.signature.effectSpecifiers?.asyncSpecifier != nil && !asyncContextStack.isEmpty {
            asyncContextStack.removeLast()
        }
    }
    
    // Check closures for unowned self in async context
    // Note: Direct async call closures (Task { }, etc.) are handled in FunctionCallExprSyntax.visit
    // This handles nested closures within async contexts
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        // Skip closures we've already analyzed via the direct function call path
        if analyzedClosures.contains(node.id) {
            return .visitChildren
        }
        
        // If we're already in an async context, check this closure
        if !asyncContextStack.isEmpty {
            if let captureClause = node.signature?.capture {
                checkCaptureClauseForUnowned(captureClause)
            }
        }
        return .visitChildren
    }
    
    private func identifyAsyncContext(_ node: FunctionCallExprSyntax) -> AsyncContext? {
        let callText = node.calledExpression.trimmedDescription
        
        // Task { }
        if callText == "Task" {
            return .task
        }
        
        // Task.detached { }
        if callText == "Task.detached" {
            return .taskDetached
        }
        
        // DispatchQueue.*.async { } - also dangerous with unowned
        if callText.contains("DispatchQueue") && callText.contains("async") {
            return .asyncClosure
        }
        
        // Check for async in member access
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let member = memberAccess.declName.baseName.text
            
            if member == "detached" {
                if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
                    if base.baseName.text == "Task" {
                        return .taskDetached
                    }
                }
            }
            
            if member == "async" {
                return .asyncClosure
            }
        }
        
        return nil
    }
    
    private func checkClosureCaptureList(_ closure: ClosureExprSyntax, context: AsyncContext) {
        guard let captureClause = closure.signature?.capture else {
            return
        }
        
        // Mark this closure as analyzed to avoid duplicate detections
        analyzedClosures.insert(closure.id)
        
        checkCaptureClauseForUnowned(captureClause, context: context)
    }
    
    private func checkCaptureClauseForUnowned(_ captureClause: ClosureCaptureClauseSyntax, context: AsyncContext? = nil) {
        for item in captureClause.items {
            let specifier = item.specifier?.specifier.text.lowercased() ?? ""
            let capturedName = item.expression.trimmedDescription
            
            // Check for unowned self
            if specifier == "unowned" && (capturedName == "self" || capturedName.hasPrefix("self.")) {
                let location = sourceFile.location(for: item.position)
                
                let contextDesc: String
                let effectiveContext = context ?? asyncContextStack.last
                switch effectiveContext {
                case .task:
                    contextDesc = "Task"
                case .taskDetached:
                    contextDesc = "Task.detached"
                case .asyncClosure:
                    contextDesc = "async closure"
                case .asyncFunction:
                    contextDesc = "async function"
                case .none:
                    contextDesc = "async context"
                }
                
                // Create structured fix to replace unowned with weak
                var fixBuilder = StructuredFixBuilder(
                    title: "Replace with [weak self]",
                    kind: .replace,
                    ruleId: "unowned_async"
                )
                
                let specifierToken = item.specifier!.specifier
                let specifierLocation = sourceFile.location(for: specifierToken.position)
                let specifierEndLocation = sourceFile.location(for: specifierToken.endPosition)
                
                fixBuilder.addEdit(TextEdit(
                    range: SourceRange(
                        startLine: specifierLocation.line,
                        startColumn: specifierLocation.column,
                        endLine: specifierEndLocation.line,
                        endColumn: specifierEndLocation.column,
                        file: sourceFile.url.path
                    ),
                    newText: "weak"
                ))
                
                fixBuilder.setConfidence(.safe)
                fixBuilder.markPreferred()
                fixBuilder.setDescription("Use [weak self] with guard let self in async contexts")
                
                let violation = ViolationBuilder(
                    ruleId: "unowned_async",
                    category: .concurrency,
                    location: location
                )
                .message("[unowned self] in \(contextDesc) is dangerous: the task may outlive 'self', causing a crash")
                .suggestFix("Use [weak self] with 'guard let self' instead: the task may outlive the captured object")
                .severity(.error)
                .addStructuredFix(fixBuilder.build())
                .addContext(key: "asyncContext", value: contextDesc)
                .build()
                
                violations.append(violation)
            }
        }
    }
}
