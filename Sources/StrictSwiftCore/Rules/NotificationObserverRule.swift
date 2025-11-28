import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that detects NotificationCenter.addObserver(self, selector:...) calls
/// without corresponding removeObserver in deinit, which can lead to crashes
public final class NotificationObserverRule: Rule, @unchecked Sendable {
    public var id: String { "notification_observer" }
    public var name: String { "Notification Observer Cleanup" }
    public var description: String { "Detects NotificationCenter observers that may not be properly removed" }
    public var category: RuleCategory { .memory }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }
    
    public init() {}
    
    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }
        
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)
        
        let analyzer = NotificationObserverAnalyzer(sourceFile: sourceFile)
        analyzer.walk(tree)
        
        return analyzer.violations
    }
    
    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Analyzes notification observer patterns
private class NotificationObserverAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    var violations: [Violation] = []
    
    // Track class-level info
    private var isInClass = false
    private var currentClassName: String?
    private var classStartPosition: AbsolutePosition?
    
    // Track addObserver calls and deinit presence
    private var addObserverCalls: [(location: Location, methodName: String)] = []
    private var hasDeinit = false
    private var hasRemoveObserverInDeinit = false
    
    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // Reset tracking for each class
        isInClass = true
        currentClassName = node.name.text
        classStartPosition = node.position
        addObserverCalls = []
        hasDeinit = false
        hasRemoveObserverInDeinit = false
        return .visitChildren
    }
    
    override func visitPost(_ node: ClassDeclSyntax) {
        // After visiting class, check if we have issues
        reportViolationsForCurrentClass()
        
        isInClass = false
        currentClassName = nil
        classStartPosition = nil
        addObserverCalls = []
        hasDeinit = false
        hasRemoveObserverInDeinit = false
    }
    
    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        hasDeinit = true
        
        // Check if deinit contains removeObserver
        let removalChecker = RemoveObserverChecker()
        removalChecker.walk(node)
        hasRemoveObserverInDeinit = removalChecker.hasRemoveObserver
        
        return .skipChildren
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isInClass else { return .visitChildren }
        
        // Check for NotificationCenter.default.addObserver(self, selector:...)
        if isAddObserverWithSelfCall(node) {
            let location = sourceFile.location(for: node.position)
            addObserverCalls.append((location: location, methodName: "addObserver"))
        }
        
        return .visitChildren
    }
    
    private func isAddObserverWithSelfCall(_ node: FunctionCallExprSyntax) -> Bool {
        // Check if this is a addObserver call
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return false
        }
        
        let methodName = memberAccess.declName.baseName.text
        guard methodName == "addObserver" else {
            return false
        }
        
        // Check if it's on NotificationCenter
        let baseText = memberAccess.base?.trimmedDescription ?? ""
        let isNotificationCenter = baseText.contains("NotificationCenter") || 
                                   baseText.contains("notificationCenter")
        
        guard isNotificationCenter else {
            return false
        }
        
        // Check if first argument is self (the selector-based API)
        // addObserver(_ observer: Any, selector: Selector, name: Notification.Name?, object: Any?)
        if let firstArg = node.arguments.first {
            let argText = firstArg.expression.trimmedDescription
            if argText == "self" {
                return true
            }
        }
        
        return false
    }
    
    private func reportViolationsForCurrentClass() {
        guard !addObserverCalls.isEmpty else { return }
        
        let className = currentClassName ?? "class"
        
        for call in addObserverCalls {
            // Case 1: No deinit at all
            // Case 2: Has deinit but no removeObserver
            if !hasDeinit || !hasRemoveObserverInDeinit {
                let suggestion: String
                if !hasDeinit {
                    suggestion = "Add a deinit that calls NotificationCenter.default.removeObserver(self)"
                } else {
                    suggestion = "Add NotificationCenter.default.removeObserver(self) to deinit"
                }
                
                let violation = ViolationBuilder(
                    ruleId: "notification_observer",
                    category: .memory,
                    location: call.location
                )
                .message("NotificationCenter observer registered with selector-based API in '\(className)' without cleanup in deinit")
                .suggestFix(suggestion)
                .severity(.warning)
                .addContext(key: "className", value: className)
                .addContext(key: "hasDeinit", value: String(hasDeinit))
                .build()
                
                violations.append(violation)
            }
        }
    }
}

/// Checks if a node contains removeObserver calls
private class RemoveObserverChecker: SyntaxAnyVisitor {
    var hasRemoveObserver = false
    
    init() {
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let methodName = memberAccess.declName.baseName.text
            if methodName == "removeObserver" {
                hasRemoveObserver = true
            }
        }
        return .visitChildren
    }
}
