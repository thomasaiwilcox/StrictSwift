import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that detects delegate properties that are not marked as weak
/// Non-weak delegates in classes can create retain cycles
public final class WeakDelegateRule: Rule, @unchecked Sendable {
    public var id: String { "weak_delegate" }
    public var name: String { "Weak Delegate" }
    public var description: String { "Detects delegate properties that should be weak to avoid retain cycles" }
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
        
        let analyzer = WeakDelegateAnalyzer(sourceFile: sourceFile)
        analyzer.walk(tree)
        
        return analyzer.violations
    }
    
    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Analyzes delegate property patterns
private class WeakDelegateAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    var violations: [Violation] = []
    
    // Track type context - only report for classes
    private var isInClass = false
    private var currentTypeName: String?
    private var isInStruct = false
    private var isInEnum = false
    
    init(sourceFile: SourceFile) {
        self.sourceFile = sourceFile
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        isInClass = true
        currentTypeName = node.name.text
        return .visitChildren
    }
    
    override func visitPost(_ node: ClassDeclSyntax) {
        isInClass = false
        currentTypeName = nil
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        isInStruct = true
        return .visitChildren
    }
    
    override func visitPost(_ node: StructDeclSyntax) {
        isInStruct = false
    }
    
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        isInEnum = true
        return .visitChildren
    }
    
    override func visitPost(_ node: EnumDeclSyntax) {
        isInEnum = false
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Only check class properties (structs/enums don't have retain cycles)
        guard isInClass && !isInStruct && !isInEnum else {
            return .visitChildren
        }
        
        // Skip if already weak
        if hasWeakModifier(node) {
            return .visitChildren
        }
        
        // Check each binding
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let propertyName = pattern.identifier.text.lowercased()
                
                // Check if name suggests it's a delegate
                if isDelegateName(propertyName) {
                    reportDelegateViolation(node: node, binding: binding, propertyName: pattern.identifier.text)
                    continue
                }
                
                // Check if type suggests it's a delegate
                if let typeAnnotation = binding.typeAnnotation {
                    let typeName = typeAnnotation.type.trimmedDescription
                    if isDelegateType(typeName) {
                        reportDelegateViolation(node: node, binding: binding, propertyName: pattern.identifier.text)
                    }
                }
            }
        }
        
        return .visitChildren
    }
    
    private func hasWeakModifier(_ node: VariableDeclSyntax) -> Bool {
        for modifier in node.modifiers {
            if modifier.name.text == "weak" {
                return true
            }
        }
        return false
    }
    
    private func isDelegateName(_ name: String) -> Bool {
        // Common delegate/dataSource property names
        let delegatePatterns = [
            "delegate",
            "datasource",
            "data_source",
        ]
        
        for pattern in delegatePatterns {
            if name.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    private func isDelegateType(_ typeName: String) -> Bool {
        // Check if type name ends with Delegate or DataSource
        let cleanType = typeName
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        return cleanType.hasSuffix("Delegate") ||
               cleanType.hasSuffix("DataSource") ||
               cleanType.hasSuffix("Delegating")
    }
    
    private func reportDelegateViolation(node: VariableDeclSyntax, binding: PatternBindingSyntax, propertyName: String) {
        let location = sourceFile.location(for: binding.position)
        let className = currentTypeName ?? "class"
        
        // Determine the type for the message
        let typeDesc: String
        if let typeAnnotation = binding.typeAnnotation {
            typeDesc = typeAnnotation.type.trimmedDescription
        } else {
            typeDesc = "(inferred type)"
        }
        
        // Check if this is a let binding - weak only works with var
        let bindingKeyword = node.bindingSpecifier
        let isLetBinding = bindingKeyword.tokenKind == .keyword(.let)
        
        // Create structured fix to add weak modifier
        var fixBuilder = StructuredFixBuilder(
            title: "Make delegate weak",
            kind: .addAnnotation,
            ruleId: "weak_delegate"
        )
        
        // Find the keyword location
        let keywordLocation = sourceFile.location(for: bindingKeyword.position)
        let keywordEndColumn = keywordLocation.column + bindingKeyword.text.count
        
        if isLetBinding {
            // Replace 'let' with 'weak var' (weak requires var, not let)
            fixBuilder.addEdit(TextEdit(
                range: SourceRange(
                    startLine: keywordLocation.line,
                    startColumn: keywordLocation.column,
                    endLine: keywordLocation.line,
                    endColumn: keywordEndColumn,
                    file: sourceFile.url.path
                ),
                newText: "weak var"
            ))
            fixBuilder.setDescription("Change 'let' to 'weak var' to prevent retain cycles (weak requires var)")
        } else {
            // Insert 'weak ' before 'var'
            fixBuilder.addEdit(TextEdit(
                range: SourceRange(
                    startLine: keywordLocation.line,
                    startColumn: keywordLocation.column,
                    endLine: keywordLocation.line,
                    endColumn: keywordLocation.column,
                    file: sourceFile.url.path
                ),
                newText: "weak "
            ))
            fixBuilder.setDescription("Add 'weak' modifier to prevent retain cycles")
        }
        
        fixBuilder.setConfidence(.suggested)
        fixBuilder.markPreferred()
        
        let violation = ViolationBuilder(
            ruleId: "weak_delegate",
            category: .memory,
            location: location
        )
        .message("Property '\(propertyName)' of type '\(typeDesc)' in '\(className)' should be weak to avoid retain cycles")
        .suggestFix("Add 'weak' modifier: weak var \(propertyName): ...")
        .severity(.warning)
        .addStructuredFix(fixBuilder.build())
        .addContext(key: "propertyName", value: propertyName)
        .addContext(key: "className", value: className)
        .build()
        
        violations.append(violation)
    }
}
