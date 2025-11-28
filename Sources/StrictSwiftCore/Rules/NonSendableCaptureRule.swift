import Foundation
import SwiftSyntax

/// Detects non-Sendable types captured in asynchronous contexts which can cause data races
///
/// This rule uses semantic analysis (when available) to accurately determine if captured
/// types conform to Sendable. Falls back to syntactic analysis with known-type lists.
public final class NonSendableCaptureRule: Rule {
    public var id: String { "non_sendable_capture" }
    public var name: String { "Non-Sendable Capture" }
    public var description: String { "Detects non-Sendable types captured in asynchronous contexts which can cause data races" }
    public var category: RuleCategory { .concurrency }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let tree = sourceFile.tree
        
        // First pass: collect all potential captures using syntactic analysis
        let collector = CaptureCollector(sourceFile: sourceFile)
        collector.walk(tree)
        
        // If no potential captures found, return early
        guard !collector.potentialCaptures.isEmpty else {
            return []
        }
        
        // Try semantic resolution if available for THIS rule (respects per-rule overrides)
        if let resolver = context.semanticResolver, context.hasSemanticAnalysis(forRule: id) {
            return await analyzeWithSemantics(
                captures: collector.potentialCaptures,
                sourceFile: sourceFile,
                resolver: resolver
            )
        } else {
            // Fall back to syntactic-only analysis
            return analyzeSyntactically(captures: collector.potentialCaptures, sourceFile: sourceFile)
        }
    }
    
    /// Analyze captures using semantic type resolution
    private func analyzeWithSemantics(
        captures: [PotentialCapture],
        sourceFile: SourceFile,
        resolver: SemanticTypeResolver
    ) async -> [Violation] {
        var violations: [Violation] = []
        
        // Build batch of locations to resolve
        var locationsToResolve: [SemanticTypeResolver.ReferenceLocation] = []
        var locationToCapture: [SemanticTypeResolver.ReferenceLocation: PotentialCapture] = [:]
        
        for capture in captures {
            let location = SemanticTypeResolver.ReferenceLocation(
                from: capture.node,
                in: sourceFile,
                identifier: capture.identifier
            )
            locationsToResolve.append(location)
            locationToCapture[location] = capture
        }
        
        // Batch resolve all types
        let resolvedTypes = await BatchTypeResolver.resolveTypes(
            at: locationsToResolve,
            using: resolver
        )
        
        // Process each capture with resolved type info
        for capture in captures {
            let location = SemanticTypeResolver.ReferenceLocation(
                from: capture.node,
                in: sourceFile,
                identifier: capture.identifier
            )
            
            if let resolvedType = resolvedTypes[location] {
                // We have semantic info - use it for accurate detection
                if TypeSafetyChecker.isLikelyNonSendable(resolvedType) {
                    let violation = createViolation(
                        capture: capture,
                        sourceFile: sourceFile,
                        typeName: resolvedType.simpleName,
                        confidence: "high"
                    )
                    violations.append(violation)
                } else if TypeSafetyChecker.isLikelySendable(resolvedType) {
                    // Type is Sendable - no violation
                    continue
                } else if resolvedType.kind == .class {
                    // Unknown class - flag with medium confidence
                    let violation = createViolation(
                        capture: capture,
                        sourceFile: sourceFile,
                        typeName: resolvedType.simpleName,
                        confidence: "medium"
                    )
                    violations.append(violation)
                }
                // Value types (struct/enum) are assumed Sendable unless known otherwise
            } else {
                // No semantic info - fall back to syntactic check for this capture
                if let violation = checkCaptureSyntactically(capture, sourceFile: sourceFile) {
                    violations.append(violation)
                }
            }
        }
        
        return violations
    }
    
    /// Analyze captures using only syntactic information
    private func analyzeSyntactically(
        captures: [PotentialCapture],
        sourceFile: SourceFile
    ) -> [Violation] {
        var violations: [Violation] = []
        
        for capture in captures {
            if let violation = checkCaptureSyntactically(capture, sourceFile: sourceFile) {
                violations.append(violation)
            }
        }
        
        return violations
    }
    
    /// Check a single capture syntactically
    private func checkCaptureSyntactically(_ capture: PotentialCapture, sourceFile: SourceFile) -> Violation? {
        // For syntactic analysis, we search for type information in multiple places:
        // 1. The closure text itself (for inline types)
        // 2. The entire file (for variable declarations matching captured identifiers)
        
        let closureText = capture.closureText ?? capture.node.trimmedDescription
        let fileText = sourceFile.tree.trimmedDescription
        
        // For "self" captures, look for property declarations with non-Sendable types
        if capture.identifier == "self" {
            for nonSendableType in TypeSafetyChecker.knownNonSendableTypes {
                // Look for property declarations like "var view: UIView" or "let label: UILabel"
                if fileText.contains(": \(nonSendableType)") || 
                   fileText.contains(":\(nonSendableType)") ||
                   fileText.contains("= \(nonSendableType)(") {
                    return createViolation(
                        capture: capture,
                        sourceFile: sourceFile,
                        typeName: nonSendableType,
                        confidence: "syntactic"
                    )
                }
            }
        } else {
            // For explicit captures, look for the variable's type annotation
            for nonSendableType in TypeSafetyChecker.knownNonSendableTypes {
                // Look for "let/var identifier: Type" pattern
                let patterns = [
                    "var \(capture.identifier): \(nonSendableType)",
                    "let \(capture.identifier): \(nonSendableType)",
                    "var \(capture.identifier):\(nonSendableType)",
                    "let \(capture.identifier):\(nonSendableType)"
                ]
                for pattern in patterns {
                    if fileText.contains(pattern) {
                        return createViolation(
                            capture: capture,
                            sourceFile: sourceFile,
                            typeName: nonSendableType,
                            confidence: "syntactic"
                        )
                    }
                }
            }
        }
        
        // Also check if closure text directly mentions non-Sendable types
        for nonSendableType in TypeSafetyChecker.knownNonSendableTypes {
            if closureText.contains(nonSendableType) {
                return createViolation(
                    capture: capture,
                    sourceFile: sourceFile,
                    typeName: nonSendableType,
                    confidence: "syntactic"
                )
            }
        }
        
        return nil
    }
    
    /// Create a violation for a non-Sendable capture
    private func createViolation(
        capture: PotentialCapture,
        sourceFile: SourceFile,
        typeName: String,
        confidence: String
    ) -> Violation {
        let location = sourceFile.location(of: capture.node)
        
        let message: String
        let severity: DiagnosticSeverity
        
        switch confidence {
        case "high", "syntactic":  // syntactic matches are also high confidence when type matches
            message = "Potential non-Sendable capture of '\(typeName)' in \(capture.contextType)"
            severity = .error
        case "medium":
            message = "Potentially non-Sendable class '\(typeName)' captured in \(capture.contextType)"
            severity = .warning
        default:
            message = "Possible non-Sendable capture of '\(typeName)' in \(capture.contextType)"
            severity = .warning
        }
        
        return ViolationBuilder(
            ruleId: id,
            category: category,
            location: location
        )
        .message(message)
        .suggestFix("Ensure captured values are Sendable or use proper synchronization (actors, locks, etc.)")
        .suggestFix("Consider using @Sendable closure or making '\(typeName)' conform to Sendable")
        .severity(severity)
        .build()
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

// MARK: - Supporting Types

/// Represents a potential capture that needs checking
private struct PotentialCapture {
    let identifier: String
    let node: SyntaxProtocol
    let contextType: String  // "Task", "async closure", "DispatchQueue", etc.
    let closureText: String?  // Full closure text for syntactic fallback
}

// MARK: - Capture Collector

/// First-pass visitor that collects potential captures in concurrent contexts
private final class CaptureCollector: SyntaxVisitor {
    let sourceFile: SourceFile
    var potentialCaptures: [PotentialCapture] = []
    
    // Track concurrent context depth
    private var contextStack: [String] = []
    
    private var isInConcurrentContext: Bool { !contextStack.isEmpty }
    private var currentContext: String { contextStack.last ?? "concurrent context" }
    
    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }
    
    // MARK: - Task Detection
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.trimmedDescription
        
        // Detect Task { } and Task.detached { }
        if callee == "Task" || callee == "Task.detached" {
            contextStack.append("Task")
            
            // Collect captures from trailing closure
            if let closure = node.trailingClosure {
                collectCapturesFromClosure(closure)
            }
            
            // Also check argument closures
            for arg in node.arguments {
                if let closure = arg.expression.as(ClosureExprSyntax.self) {
                    collectCapturesFromClosure(closure)
                }
            }
        }
        
        // Detect DispatchQueue.*.async { }
        if callee.contains("DispatchQueue") && 
           (callee.hasSuffix(".async") || callee.hasSuffix(".sync")) {
            contextStack.append("DispatchQueue")
            
            if let closure = node.trailingClosure {
                collectCapturesFromClosure(closure)
            }
        }
        
        // Detect withTaskGroup, withThrowingTaskGroup
        if callee.contains("withTaskGroup") || callee.contains("withThrowingTaskGroup") {
            contextStack.append("TaskGroup")
            
            if let closure = node.trailingClosure {
                collectCapturesFromClosure(closure)
            }
        }
        
        return .visitChildren
    }
    
    override func visitPost(_ node: FunctionCallExprSyntax) {
        let callee = node.calledExpression.trimmedDescription
        
        if callee == "Task" || callee == "Task.detached" ||
           (callee.contains("DispatchQueue") && (callee.hasSuffix(".async") || callee.hasSuffix(".sync"))) ||
           callee.contains("withTaskGroup") || callee.contains("withThrowingTaskGroup") {
            if !contextStack.isEmpty {
                contextStack.removeLast()
            }
        }
    }
    
    // MARK: - Async Function Detection
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for async functions
        if let effectSpecifiers = node.signature.effectSpecifiers,
           effectSpecifiers.asyncSpecifier != nil {
            contextStack.append("async function")
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: FunctionDeclSyntax) {
        if let effectSpecifiers = node.signature.effectSpecifiers,
           effectSpecifiers.asyncSpecifier != nil {
            if !contextStack.isEmpty {
                contextStack.removeLast()
            }
        }
    }
    
    // MARK: - Closure Capture Collection
    
    private func collectCapturesFromClosure(_ closure: ClosureExprSyntax) {
        let closureText = closure.trimmedDescription
        
        // Check explicit capture list
        if let signature = closure.signature,
           let captureClause = signature.capture {
            for item in captureClause.items {
                let expr = item.expression
                let identifier = extractIdentifier(from: expr)
                    
                // Skip weak/unowned captures - they're already handled
                let itemText = item.trimmedDescription
                if itemText.hasPrefix("weak ") || itemText.hasPrefix("unowned ") {
                    continue
                }
                
                potentialCaptures.append(PotentialCapture(
                    identifier: identifier,
                    node: item,
                    contextType: currentContext,
                    closureText: closureText
                ))
            }
        }
        
        // Also scan closure body for implicit captures of self
        scanForSelfCaptures(in: closure, closureText: closureText)
    }
    
    private func scanForSelfCaptures(in closure: ClosureExprSyntax, closureText: String) {
        let bodyText = closure.statements.trimmedDescription
        
        // Check if "self." appears (implicit capture)
        if bodyText.contains("self.") || bodyText.contains("[self]") {
            var selfInCaptureList = false
            if let signature = closure.signature,
               let captureClause = signature.capture {
                for item in captureClause.items {
                    if item.trimmedDescription.contains("self") {
                        selfInCaptureList = true
                        break
                    }
                }
            }
            
            if !selfInCaptureList && isInConcurrentContext {
                potentialCaptures.append(PotentialCapture(
                    identifier: "self",
                    node: closure,
                    contextType: currentContext,
                    closureText: closureText
                ))
            }
        }
    }
    
    private func extractIdentifier(from expr: ExprSyntax) -> String {
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
        let text = expr.trimmedDescription
        if text == "self" {
            return "self"
        }
        return text
    }
}