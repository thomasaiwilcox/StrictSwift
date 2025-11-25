import Foundation
import SwiftSyntax

/// Detects potential actor isolation violations using AST-based analysis
public final class ActorIsolationRule: Rule, Sendable {
    public var id: String { "actor_isolation" }
    public var name: String { "Actor Isolation" }
    public var description: String { "Detects potential actor isolation violations" }
    public var category: RuleCategory { .concurrency }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        let tree = sourceFile.tree
        let visitor = ActorIsolationVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        return visitor.violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// AST-based visitor that finds potential actor isolation violations
private final class ActorIsolationVisitor: SyntaxVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    // Track actor context
    private var isInActorDeclaration = false
    private var isMainActorIsolated = false
    private var currentActorName: String?

    // Risky APIs that should be used carefully in actor contexts
    private let riskyAPIs: Set<String> = [
        "DispatchQueue", "NotificationCenter", "UserDefaults",
        "FileManager", "Timer", "RunLoop"
    ]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Track Actor Declarations

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        isInActorDeclaration = true
        currentActorName = node.name.text
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        isInActorDeclaration = false
        currentActorName = nil
    }

    // MARK: - Track @MainActor Attribute

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        let attrName = node.attributeName.trimmedDescription
        if attrName == "MainActor" {
            isMainActorIsolated = true
        }
        return .visitChildren
    }

    // MARK: - Check Function Declarations in Actors

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for nonisolated functions that access actor state
        // We need to check the modifiers directly on the function node
        let hasNonisolated = node.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.nonisolated)
        }
        
        if isInActorDeclaration && hasNonisolated {
            // Check function body for self access
            if let body = node.body {
                let bodyDescription = body.trimmedDescription
                if bodyDescription.contains("self.") {
                    let location = sourceFile.location(of: node)
                    let violation = ViolationBuilder(
                        ruleId: "actor_isolation",
                        category: .concurrency,
                        location: location
                    )
                    .message("nonisolated function '\(node.name.text)' accesses actor state via 'self'")
                    .suggestFix("Remove nonisolated modifier or avoid accessing actor-isolated state")
                    .severity(.warning)
                    .build()

                    violations.append(violation)
                }
            }
        }

        return .visitChildren
    }

    // MARK: - Check for Risky API Usage in Actor Context

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if isInActorDeclaration || isMainActorIsolated {
            if let base = node.base {
                let baseName = base.trimmedDescription

                // Check for risky API access
                for riskyAPI in riskyAPIs {
                    if baseName.contains(riskyAPI) {
                        let location = sourceFile.location(of: node)
                        let violation = ViolationBuilder(
                            ruleId: "actor_isolation",
                            category: .concurrency,
                            location: location
                        )
                        .message("Potentially unsafe '\(riskyAPI)' access in actor-isolated context")
                        .suggestFix("Use Task.detached for non-isolated work or ensure API is thread-safe")
                        .severity(.warning)
                        .build()

                        violations.append(violation)
                        break
                    }
                }
            }
        }

        return .visitChildren
    }

    // MARK: - Check for @unchecked Sendable Without Justification

    override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
        let typeDescription = node.type.trimmedDescription

        if typeDescription.contains("@unchecked") && typeDescription.contains("Sendable") {
            // Look for a comment justification in multiple places:
            // 1. Leading trivia of the inherited type itself
            // 2. Leading trivia of the parent declaration (class/struct/enum)
            
            var hasJustification = false
            
            // Check leading trivia of the @unchecked Sendable itself
            let leadingTrivia = node.leadingTrivia.description
            if leadingTrivia.contains("SAFETY") || leadingTrivia.contains("//") || leadingTrivia.contains("/*") {
                hasJustification = true
            }
            
            // Check the parent declaration's doc comments
            if !hasJustification {
                // Walk up to find the parent class/struct/actor declaration
                var parent: Syntax? = node._syntaxNode.parent
                while let p = parent {
                    if let classDecl = p.as(ClassDeclSyntax.self) {
                        let classTrivia = classDecl.leadingTrivia.description
                        if classTrivia.contains("SAFETY") {
                            hasJustification = true
                        }
                        break
                    } else if let structDecl = p.as(StructDeclSyntax.self) {
                        let structTrivia = structDecl.leadingTrivia.description
                        if structTrivia.contains("SAFETY") {
                            hasJustification = true
                        }
                        break
                    } else if let actorDecl = p.as(ActorDeclSyntax.self) {
                        let actorTrivia = actorDecl.leadingTrivia.description
                        if actorTrivia.contains("SAFETY") {
                            hasJustification = true
                        }
                        break
                    } else if let enumDecl = p.as(EnumDeclSyntax.self) {
                        let enumTrivia = enumDecl.leadingTrivia.description
                        if enumTrivia.contains("SAFETY") {
                            hasJustification = true
                        }
                        break
                    }
                    parent = p.parent
                }
            }

            if !hasJustification {
                let location = sourceFile.location(of: node)
                let violation = ViolationBuilder(
                    ruleId: "actor_isolation",
                    category: .concurrency,
                    location: location
                )
                .message("@unchecked Sendable conformance without documented justification")
                .suggestFix("Add a comment explaining why @unchecked Sendable is safe: // SAFETY: ...")
                .severity(.warning)
                .build()

                violations.append(violation)
            }
        }

        return .visitChildren
    }

    // MARK: - Check for Task.detached in MainActor Context

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callDescription = node.calledExpression.trimmedDescription

        // Check for Task.detached usage in MainActor context
        if isMainActorIsolated && callDescription == "Task.detached" {
            // This is actually a valid pattern, but warn about potential issues
            let location = sourceFile.location(of: node)
            let violation = ViolationBuilder(
                ruleId: "actor_isolation",
                category: .concurrency,
                location: location
            )
            .message("Task.detached in MainActor context - ensure no MainActor-isolated state is captured")
            .suggestFix("Verify captured values are Sendable or use explicit capture list")
            .severity(.info)
            .build()

            violations.append(violation)
        }

        return .visitChildren
    }
}