import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that detects blocking calls in @MainActor contexts
/// Blocking the main thread causes UI freezes and poor user experience
public final class MainActorBlockingRule: Rule, @unchecked Sendable {
    public var id: String { "mainactor_blocking" }
    public var name: String { "MainActor Blocking Call" }
    public var description: String { "Detects blocking calls (sync I/O, sleep, etc.) on the main actor/thread" }
    public var category: RuleCategory { .concurrency }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }
    
    public init() {}
    
    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }
        
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)
        
        let analyzer = MainActorBlockingAnalyzer(sourceFile: sourceFile)
        analyzer.walk(tree)
        
        return analyzer.violations
    }
    
    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Analyzes for blocking calls in MainActor contexts
private class MainActorBlockingAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    var violations: [Violation] = []
    
    // Track MainActor context
    private var mainActorDepth = 0
    private var isInMainActorClass = false
    private var currentFunctionName: String?
    
    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }
    
    // Track @MainActor class/struct
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if hasMainActorAttribute(node.attributes) {
            isInMainActorClass = true
            mainActorDepth += 1
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: ClassDeclSyntax) {
        if hasMainActorAttribute(node.attributes) {
            isInMainActorClass = false
            mainActorDepth -= 1
        }
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if hasMainActorAttribute(node.attributes) {
            mainActorDepth += 1
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: StructDeclSyntax) {
        if hasMainActorAttribute(node.attributes) {
            mainActorDepth -= 1
        }
    }
    
    // Track @MainActor functions
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunctionName = node.name.text
        if hasMainActorAttribute(node.attributes) {
            mainActorDepth += 1
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: FunctionDeclSyntax) {
        if hasMainActorAttribute(node.attributes) {
            mainActorDepth -= 1
        }
        currentFunctionName = nil
    }
    
    // Track @MainActor closures
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if let attributes = node.signature?.attributes, hasMainActorAttribute(attributes) {
            mainActorDepth += 1
        }
        return .visitChildren
    }
    
    override func visitPost(_ node: ClosureExprSyntax) {
        if let attributes = node.signature?.attributes, hasMainActorAttribute(attributes) {
            mainActorDepth -= 1
        }
    }
    
    // Check function calls for blocking APIs
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard mainActorDepth > 0 else { return .visitChildren }
        
        if let blockingCall = identifyBlockingCall(node) {
            let location = sourceFile.location(for: node.position)
            let functionName = currentFunctionName ?? "(closure)"
            
            let violation = ViolationBuilder(
                ruleId: "mainactor_blocking",
                category: .concurrency,
                location: location
            )
            .message("Blocking call '\(blockingCall.name)' in @MainActor context '\(functionName)' will freeze the UI")
            .suggestFix(blockingCall.suggestion)
            .severity(.warning)
            .addContext(key: "blockingCall", value: blockingCall.name)
            .addContext(key: "asyncAlternative", value: blockingCall.asyncAlternative ?? "")
            .build()
            
            violations.append(violation)
        }
        
        return .visitChildren
    }
    
    private func hasMainActorAttribute(_ attributes: AttributeListSyntax?) -> Bool {
        guard let attrs = attributes else { return false }
        
        for attr in attrs {
            if case .attribute(let attribute) = attr {
                let attrName = attribute.attributeName.trimmedDescription
                if attrName == "MainActor" || attrName == "main" {
                    return true
                }
            }
        }
        return false
    }
    
    private struct BlockingCallInfo {
        let name: String
        let suggestion: String
        let asyncAlternative: String?
    }
    
    private func identifyBlockingCall(_ node: FunctionCallExprSyntax) -> BlockingCallInfo? {
        let callText = node.calledExpression.trimmedDescription
        
        // Thread.sleep - definitely blocking
        if callText.contains("Thread.sleep") || callText == "sleep" {
            return BlockingCallInfo(
                name: "Thread.sleep",
                suggestion: "Use Task.sleep or async delay instead of Thread.sleep",
                asyncAlternative: "try await Task.sleep(nanoseconds:)"
            )
        }
        
        // Synchronous Data(contentsOf:) - blocks on I/O
        if callText == "Data" {
            for arg in node.arguments {
                let label = arg.label?.text ?? ""
                if label == "contentsOf" {
                    return BlockingCallInfo(
                        name: "Data(contentsOf:)",
                        suggestion: "Use async URLSession for network requests, or load file data on a background queue",
                        asyncAlternative: "try await URLSession.shared.data(from:)"
                    )
                }
            }
        }
        
        // String(contentsOf:) - blocks on I/O
        if callText == "String" {
            for arg in node.arguments {
                let label = arg.label?.text ?? ""
                if label == "contentsOf" || label == "contentsOfFile" {
                    return BlockingCallInfo(
                        name: "String(contentsOf:)",
                        suggestion: "Load string contents on a background queue or use async file reading",
                        asyncAlternative: nil
                    )
                }
            }
        }
        
        // FileManager synchronous operations
        if callText.contains("FileManager") {
            if callText.contains("contents") || callText.contains("createFile") ||
               callText.contains("copyItem") || callText.contains("moveItem") ||
               callText.contains("removeItem") {
                return BlockingCallInfo(
                    name: callText,
                    suggestion: "Perform FileManager operations on a background queue",
                    asyncAlternative: nil
                )
            }
        }
        
        // URLSession synchronous (deprecated but still used)
        if callText.contains("URLSession") && callText.contains("synchronousDataTask") {
            return BlockingCallInfo(
                name: "synchronousDataTask",
                suggestion: "Use async URLSession.data(from:) instead",
                asyncAlternative: "try await URLSession.shared.data(from:)"
            )
        }
        
        // DispatchSemaphore.wait - definitely blocking
        if callText.contains("wait") {
            // Check if we're calling wait() on something that looks like a semaphore
            if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
                let member = memberAccess.declName.baseName.text
                if member == "wait" {
                    let base = memberAccess.base?.trimmedDescription ?? ""
                    // Common semaphore variable patterns
                    if base.lowercased().contains("semaphore") || 
                       base.contains("Semaphore") {
                        return BlockingCallInfo(
                            name: "DispatchSemaphore.wait",
                            suggestion: "Avoid semaphores on MainActor; use async/await patterns instead",
                            asyncAlternative: nil
                        )
                    }
                }
            }
        }
        
        // Check for member access patterns
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let member = memberAccess.declName.baseName.text
            let base = memberAccess.base?.trimmedDescription ?? ""
            
            // DispatchGroup.wait
            if member == "wait" && base.contains("Group") {
                return BlockingCallInfo(
                    name: "DispatchGroup.wait",
                    suggestion: "Use async/await or DispatchGroup.notify instead of blocking wait",
                    asyncAlternative: nil
                )
            }
            
            // Process/Task.waitUntilExit
            if member == "waitUntilExit" {
                return BlockingCallInfo(
                    name: "waitUntilExit",
                    suggestion: "Run process operations on a background queue",
                    asyncAlternative: nil
                )
            }
        }
        
        return nil
    }
}
