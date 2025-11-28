import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that detects potential retain cycles in Combine publisher chains
/// Specifically targets .sink, .receive, .assign closures that capture `self` strongly
public final class CombineRetainCycleRule: Rule, @unchecked Sendable {
    public var id: String { "combine_retain_cycle" }
    public var name: String { "Combine Retain Cycle" }
    public var description: String { "Detects potential retain cycles in Combine publisher subscriptions" }
    public var category: RuleCategory { .memory }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }
    
    public init() {}
    
    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }
        
        // Check if file uses Combine (via import or AnyCancellable usage)
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)
        
        let combineDetector = CombineUsageDetector()
        combineDetector.walk(tree)
        
        // If no Combine usage detected, skip this file
        guard combineDetector.usesCombine else { return [] }
        
        // Analyze for retain cycles
        let analyzer = CombineRetainCycleAnalyzer(sourceFile: sourceFile)
        analyzer.walk(tree)
        
        return analyzer.violations
    }
    
    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Detects if a file uses Combine framework
private class CombineUsageDetector: SyntaxAnyVisitor {
    var usesCombine = false
    
    init() {
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.first?.name.text ?? ""
        if moduleName == "Combine" || moduleName == "SwiftUI" {
            usesCombine = true
        }
        return .skipChildren
    }
    
    // Also detect AnyCancellable usage (covers transitive imports)
    override func visit(_ node: TypeAnnotationSyntax) -> SyntaxVisitorContinueKind {
        let typeText = node.type.trimmedDescription
        if typeText.contains("AnyCancellable") || typeText.contains("Cancellable") ||
           typeText.contains("AnyPublisher") || typeText.contains("Published") {
            usesCombine = true
        }
        return .skipChildren
    }
    
    // Detect Set<AnyCancellable> or [AnyCancellable] patterns
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let declText = node.trimmedDescription
        if declText.contains("AnyCancellable") || declText.contains("cancellables") {
            usesCombine = true
        }
        return .visitChildren
    }
}

/// Analyzes Combine chains for retain cycle patterns
private class CombineRetainCycleAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    var violations: [Violation] = []
    
    // Track class context for determining if we're in a reference type
    private var isInClass = false
    private var currentClassName: String?
    
    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        isInClass = true
        currentClassName = node.name.text
        return .visitChildren
    }
    
    override func visitPost(_ node: ClassDeclSyntax) {
        isInClass = false
        currentClassName = nil
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Only check within classes (structs don't have retain cycle issues)
        guard isInClass else { return .visitChildren }
        
        // Check for sink, receive, assign patterns
        let methodName = extractMethodName(from: node)
        
        guard isCombineSubscriptionMethod(methodName) else {
            return .visitChildren
        }
        
        // Check closure arguments for strong self capture
        for argument in node.arguments {
            if let closure = argument.expression.as(ClosureExprSyntax.self) {
                checkClosureForRetainCycle(closure, methodName: methodName)
            }
        }
        
        // Also check trailing closure
        if let trailingClosure = node.trailingClosure {
            checkClosureForRetainCycle(trailingClosure, methodName: methodName)
        }
        
        return .visitChildren
    }
    
    private func extractMethodName(from node: FunctionCallExprSyntax) -> String {
        // Handle chained method calls like publisher.sink { }
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
        return ""
    }
    
    private func isCombineSubscriptionMethod(_ name: String) -> Bool {
        // Methods that store subscriptions and can cause retain cycles
        let subscriptionMethods = [
            "sink",          // Most common - stores closure
            "receive",       // receive(on:) with closure
            "assign",        // assign(to:on:) captures the target object
            "handleEvents",  // handleEvents closures
            "map",           // Can capture self in mapping closure
            "filter",        // Can capture self in filter closure
            "flatMap",       // Can capture self
            "compactMap",    // Can capture self
            "tryMap",        // Can capture self
        ]
        return subscriptionMethods.contains(name)
    }
    
    private func checkClosureForRetainCycle(_ closure: ClosureExprSyntax, methodName: String) {
        // Check if closure has capture list with weak/unowned self
        var hasWeakSelf = false
        var hasUnownedSelf = false
        
        if let captureClause = closure.signature?.capture {
            for item in captureClause.items {
                let specifier = item.specifier?.specifier.text.lowercased() ?? ""
                let capturedName = item.expression.trimmedDescription
                
                if capturedName == "self" || capturedName.hasPrefix("self.") {
                    if specifier == "weak" {
                        hasWeakSelf = true
                    } else if specifier == "unowned" {
                        hasUnownedSelf = true
                    }
                }
            }
        }
        
        // If already has weak/unowned self, no issue
        if hasWeakSelf || hasUnownedSelf {
            return
        }
        
        // Check if closure body references self
        let selfChecker = SelfReferenceChecker()
        selfChecker.walk(closure)
        
        if selfChecker.referencesSelf {
            let location = sourceFile.location(for: closure.position)
            let className = currentClassName ?? "class"
            
            // Create structured fix
            var fixBuilder = StructuredFixBuilder(
                title: "Add [weak self] capture",
                kind: .addAnnotation,
                ruleId: "combine_retain_cycle"
            )
            
            // Determine where to insert the capture list
            if let signature = closure.signature {
                // Has existing signature, need to add capture clause
                let signatureStart = sourceFile.location(for: signature.position)
                fixBuilder.addEdit(TextEdit(
                    range: SourceRange(
                        startLine: signatureStart.line,
                        startColumn: signatureStart.column,
                        endLine: signatureStart.line,
                        endColumn: signatureStart.column,
                        file: sourceFile.url.path
                    ),
                    newText: "[weak self] "
                ))
            } else {
                // No signature, insert after opening brace
                let bracePos = closure.leftBrace.positionAfterSkippingLeadingTrivia
                let braceLocation = sourceFile.location(for: bracePos)
                fixBuilder.addEdit(TextEdit(
                    range: SourceRange(
                        startLine: braceLocation.line,
                        startColumn: braceLocation.column + 1, // After the {
                        endLine: braceLocation.line,
                        endColumn: braceLocation.column + 1,
                        file: sourceFile.url.path
                    ),
                    newText: " [weak self] in"
                ))
            }
            
            fixBuilder.setConfidence(.suggested)
            fixBuilder.markPreferred()
            
            let violation = ViolationBuilder(
                ruleId: "combine_retain_cycle",
                category: .memory,
                location: location
            )
            .message("Combine .\(methodName) closure captures 'self' strongly, creating a potential retain cycle in '\(className)'")
            .suggestFix("Add [weak self] to the closure capture list and use 'self?' or 'guard let self' inside")
            .severity(.warning)
            .addStructuredFix(fixBuilder.build())
            .build()
            
            violations.append(violation)
        }
    }
}

/// Checks if a closure body references self
private class SelfReferenceChecker: SyntaxAnyVisitor {
    var referencesSelf = false
    
    init() {
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if node.baseName.text == "self" {
            referencesSelf = true
        }
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for implicit self (e.g., `property` instead of `self.property`)
        // This is harder to detect without semantic analysis, so we focus on explicit self
        if let base = node.base?.as(DeclReferenceExprSyntax.self) {
            if base.baseName.text == "self" {
                referencesSelf = true
            }
        }
        return .visitChildren
    }
}
