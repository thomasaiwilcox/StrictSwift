import Foundation
import SwiftSyntax

/// Detects non-Sendable types captured in asynchronous contexts which can cause data races
public final class NonSendableCaptureRule: Rule {
    public var id: String { "non_sendable_capture" }
    public var name: String { "Non-Sendable Capture" }
    public var description: String { "Detects non-Sendable types captured in asynchronous contexts which can cause data races" }
    public var category: RuleCategory { .concurrency }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        let visitor = NonSendableCaptureVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds potential non-Sendable captures
private final class NonSendableCaptureVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    // Types that are commonly known to be non-Sendable
    private let nonSendableTypes: Set<String> = [
        // UIKit/AppKit types that are not Sendable
        "UIView", "UIViewController", "NSView", "NSViewController", "CALayer",
        "UILabel", "UIButton", "UIImageView", "UITextField", "UITextView",
        "NSObject", "NSMutableDictionary", "NSMutableArray", "NSMutableSet",

        // Core Graphics/Core Data types
        "CGContext", "CGImage", "CGColorSpace", "NSManagedObject",

        // General mutable collection types
        "NSMutableArray", "NSMutableDictionary", "NSMutableSet", "NSMutableData",
        "NSMutableArray?", "NSMutableDictionary?", "NSMutableSet?", "NSMutableData?",

        // Common non-Sendable classes
        "Timer", "UserDefaults", "URLSessionDataTask",
        "FileHandle", "Stream"
    ]

    // Context patterns that indicate async/concurrent execution
    private let asyncContexts: Set<String> = [
        "Task", "async", "await", "DispatchQueue", "DispatchGroup",
        "actor", "MainActor", "TaskGroup", "Throttle"
    ]

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        let nodeDescription = node.description

        // Look for Task creation with closures that might capture non-Sendable types
        if nodeDescription.contains("Task") && nodeDescription.contains("{") {
            analyzeTaskCapture(node, nodeDescription: nodeDescription)
            return .skipChildren
        }

        // Look for async/await patterns
        if nodeDescription.contains("async") && nodeDescription.contains("{") {
            analyzeAsyncContext(node, nodeDescription: nodeDescription)
            return .skipChildren
        }

        // Look for DispatchQueue operations
        if (nodeDescription.contains("DispatchQueue") || nodeDescription.contains(".async")) && nodeDescription.contains("{") {
            analyzeDispatchCapture(node, nodeDescription: nodeDescription)
            return .skipChildren
        }

        return .visitChildren
    }

    private func analyzeTaskCapture(_ node: Syntax, nodeDescription: String) {
        // Look for Task patterns with potential non-Sendable captures
        for type in nonSendableTypes {
            if nodeDescription.contains("Task") && nodeDescription.contains(type) {
                let location = sourceFile.location(for: node.position)

                let violation = ViolationBuilder(
                    ruleId: "non_sendable_capture",
                    category: .concurrency,
                    location: location
                )
                .message("Potential non-Sendable capture of '\(type)' in Task")
                .suggestFix("Ensure captured values are Sendable or use proper synchronization (actors, locks, etc.)")
                .severity(.error)
                .build()

                violations.append(violation)
                break
            }
        }
    }

    private func analyzeAsyncContext(_ node: Syntax, nodeDescription: String) {
        // Look for async patterns with potential non-Sendable captures
        for type in nonSendableTypes {
            if nodeDescription.contains("async") && nodeDescription.contains(type) {
                let location = sourceFile.location(for: node.position)

                let violation = ViolationBuilder(
                    ruleId: "non_sendable_capture",
                    category: .concurrency,
                    location: location
                )
                .message("Potential non-Sendable capture of '\(type)' in async context")
                .suggestFix("Mark the type as Sendable or use proper isolation patterns")
                .severity(.error)
                .build()

                violations.append(violation)
                break
            }
        }
    }

    private func analyzeDispatchCapture(_ node: Syntax, nodeDescription: String) {
        // Look for DispatchQueue patterns with potential non-Sendable captures
        for type in nonSendableTypes {
            if (nodeDescription.contains("DispatchQueue") || nodeDescription.contains(".async")) && nodeDescription.contains(type) {
                let location = sourceFile.location(for: node.position)

                let violation = ViolationBuilder(
                    ruleId: "non_sendable_capture",
                    category: .concurrency,
                    location: location
                )
                .message("Potential non-Sendable capture of '\(type)' in concurrent context")
                .suggestFix("Ensure thread-safe access or use actor isolation")
                .severity(.error)
                .build()

                violations.append(violation)
                break
            }
        }
    }
}