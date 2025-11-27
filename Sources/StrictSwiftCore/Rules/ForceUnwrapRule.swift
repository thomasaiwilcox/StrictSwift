import Foundation
import SwiftSyntax

/// Detects force unwraps in Swift code
public final class ForceUnwrapRule: Rule {
    public var id: String { "force_unwrap" }
    public var name: String { "Force Unwrap" }
    public var description: String { "Detects force unwrapping of optional values" }
    public var category: RuleCategory { .safety }
    public var defaultSeverity: DiagnosticSeverity { .error }
    public var enabledByDefault: Bool { true }

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let tree = sourceFile.tree

        // Visit the tree to find force unwrap expressions
        let visitor = ForceUnwrapVisitor(sourceFile: sourceFile)
        visitor.walk(tree)
        violations = visitor.violations

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax visitor that finds force unwrap expressions
private final class ForceUnwrapVisitor: SyntaxAnyVisitor {
    let sourceFile: SourceFile
    var violations: [Violation] = []

    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }

    public override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        // Get the location from the position (skipping leading trivia for accurate line numbers)
        let location = sourceFile.location(of: node)
        
        // Extract the expression being force-unwrapped
        let expression = node.expression.description.trimmingCharacters(in: .whitespaces)
        
        // Generate a binding name from the expression
        let bindingName = generateBindingName(from: expression)
        
        // Calculate the source range for the force unwrap expression
        let endLocation = sourceFile.location(for: node.endPosition)
        let range = SourceRange(start: location, end: endLocation)
        
        // Build the violation with structured fixes
        var builder = ViolationBuilder(
            ruleId: "force_unwrap",
            category: .safety,
            location: location
        )
        .message("Force unwrap (!) of optional value. Consider using optional binding or guard let")
        .suggestFix("Replace with optional binding: if let \(bindingName) = \(expression) { ... }")
        .severity(.error)
        
        // Add structured fix for nil-coalescing operator (simplest fix)
        let nilCoalescingFix = StructuredFix(
            title: "Use nil-coalescing operator",
            kind: .replace,
            edits: [TextEdit(range: range, newText: "\(expression) ?? <#default#>")],
            isPreferred: false,
            confidence: .suggested,
            description: "Replace force unwrap with nil-coalescing operator",
            ruleId: "force_unwrap"
        )
        builder = builder.addStructuredFix(nilCoalescingFix)
        
        // Add structured fix for optional chaining (if applicable)
        let optionalChainingFix = StructuredFix(
            title: "Use optional chaining",
            kind: .replace,
            edits: [TextEdit(range: range, newText: "\(expression)?")],
            isPreferred: false,
            confidence: .suggested,
            description: "Replace force unwrap with optional chaining",
            ruleId: "force_unwrap"
        )
        builder = builder.addStructuredFix(optionalChainingFix)
        
        // Add context for the expression
        builder = builder.addContext(key: "expression", value: expression)
        builder = builder.addContext(key: "bindingName", value: bindingName)

        violations.append(builder.build())

        return .skipChildren
    }

    public override func visit(_ node: OptionalChainingExprSyntax) -> SyntaxVisitorContinueKind {
        // Look for force unwrap within optional chaining (e.g., value!.property)
        if let forcedValue = node.expression.as(ForceUnwrapExprSyntax.self) {
            let location = sourceFile.location(for: forcedValue.position)
            
            // Get the expression being force-unwrapped
            let expression = forcedValue.expression.description.trimmingCharacters(in: .whitespaces)
            
            // Calculate the source range
            let startLocation = sourceFile.location(for: forcedValue.position)
            let endLocation = sourceFile.location(for: forcedValue.endPosition)
            let range = SourceRange(start: startLocation, end: endLocation)

            var builder = ViolationBuilder(
                ruleId: "force_unwrap",
                category: .safety,
                location: location
            )
            .message("Force unwrap in optional chaining. Consider safe optional chaining instead")
            .suggestFix("Replace '?' instead of '!' if nil values are acceptable")
            .severity(.error)
            
            // Add structured fix to replace ! with ?
            let optionalFix = StructuredFix(
                title: "Replace ! with ?",
                kind: .replace,
                edits: [TextEdit(range: range, newText: "\(expression)?")],
                isPreferred: true,
                confidence: .safe,
                description: "Replace force unwrap with optional chaining",
                ruleId: "force_unwrap"
            )
            builder = builder.addStructuredFix(optionalFix)

            violations.append(builder.build())
        }

        return .visitChildren
    }
    
    /// Generate a reasonable binding name from an expression
    private func generateBindingName(from expression: String) -> String {
        // Remove common prefixes and clean up
        var name = expression
        
        // Handle property access (e.g., "self.value" -> "value")
        if let dotIndex = name.lastIndex(of: ".") {
            name = String(name[name.index(after: dotIndex)...])
        }
        
        // Handle method calls (e.g., "getValue()" -> "value")
        if name.hasSuffix("()") {
            name = String(name.dropLast(2))
            if name.hasPrefix("get") {
                name = String(name.dropFirst(3))
                if let first = name.first {
                    name = first.lowercased() + name.dropFirst()
                }
            }
        }
        
        // Handle array subscripts (e.g., "array[0]" -> "element")
        if name.contains("[") {
            name = "element"
        }
        
        // Clean up and validate as identifier
        name = name.trimmingCharacters(in: .whitespaces)
        guard let firstChar = name.first, firstChar.isLetter else {
            name = "unwrappedValue"
            return name
        }
        
        // Ensure it starts with lowercase
        if let first = name.first, first.isUppercase {
            name = first.lowercased() + name.dropFirst()
        }
        
        return name
    }
}
