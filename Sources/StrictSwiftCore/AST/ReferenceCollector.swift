import Foundation
import SwiftSyntax

/// Represents a scope entry for tracking context during reference collection
private struct ScopeEntry {
    let name: String
    let kind: SymbolKind
    /// Local variable types declared in this scope: variable name → type name
    var localTypes: [String: String] = [:]
}

/// Walks the syntax tree and collects symbol references (usages)
/// Used for dead code detection to identify which symbols are actually used
public final class ReferenceCollector: SyntaxAnyVisitor {
    public private(set) var references: [SymbolReference] = []
    private let fileURL: URL
    private let converter: SourceLocationConverter
    private let moduleName: String
    
    /// Stack tracking the current scope hierarchy for context
    private var scopeStack: [ScopeEntry] = []
    
    /// Set of built-in types to exclude from type references
    private static let builtInTypes: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Float", "Double", "Bool", "String", "Character",
        "Void", "Never", "Any", "AnyObject", "Self",
        "Optional", "Array", "Dictionary", "Set",
        "Result", "Error"
    ]
    
    public init(fileURL: URL, tree: SourceFileSyntax, moduleName: String = "Unknown") {
        self.fileURL = fileURL
        self.moduleName = moduleName
        self.converter = SourceLocationConverter(fileName: fileURL.path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }
    
    // MARK: - Scope Management
    
    /// Returns the current scope context as a qualified name
    private var currentScopeContext: String {
        scopeStack.map(\.name).joined(separator: ".")
    }
    
    /// Push a new scope onto the stack
    private func pushScope(name: String, kind: SymbolKind) {
        scopeStack.append(ScopeEntry(name: name, kind: kind))
    }
    
    /// Pop the current scope from the stack
    private func popScope() {
        if !scopeStack.isEmpty {
            scopeStack.removeLast()
        }
    }
    
    // MARK: - Local Type Tracking
    
    /// Register a local variable's type in the current scope
    private func registerLocalType(name: String, typeName: String) {
        guard !scopeStack.isEmpty else { return }
        scopeStack[scopeStack.count - 1].localTypes[name] = typeName
    }
    
    /// Look up a variable's type from the scope stack (innermost first)
    private func lookupLocalType(_ name: String) -> String? {
        for scope in scopeStack.reversed() {
            if let typeName = scope.localTypes[name] {
                return typeName
            }
        }
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func location(from position: AbsolutePosition) -> Location {
        let loc = converter.location(for: position)
        return Location(
            file: fileURL,
            line: loc.line,
            column: loc.column
        )
    }
    
    /// Creates and records a symbol reference
    private func recordReference(
        name: String,
        fullExpression: String,
        kind: ReferenceKind,
        position: AbsolutePosition,
        inferredBaseType: String? = nil
    ) {
        let reference = SymbolReference(
            referencedName: name,
            fullExpression: fullExpression,
            kind: kind,
            location: location(from: position),
            scopeContext: currentScopeContext,
            inferredBaseType: inferredBaseType
        )
        references.append(reference)
    }
    
    /// Checks if a type name is a built-in Swift type
    private func isBuiltInType(_ name: String) -> Bool {
        Self.builtInTypes.contains(name)
    }
    
    /// Extracts a simple type name from a type syntax, handling optionals and arrays
    private func extractTypeName(from type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return extractTypeName(from: optional.wrappedType)
        }
        if let implicitOptional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return extractTypeName(from: implicitOptional.wrappedType)
        }
        if let array = type.as(ArrayTypeSyntax.self) {
            return extractTypeName(from: array.element)
        }
        if let dictionary = type.as(DictionaryTypeSyntax.self) {
            // Record both key and value types
            return extractTypeName(from: dictionary.value)
        }
        if let memberType = type.as(MemberTypeSyntax.self) {
            return memberType.name.text
        }
        return nil
    }
    
    // MARK: - Scope Tracking Visitors
    
    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope(name: node.name.text, kind: .class)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ClassDeclSyntax) {
        popScope()
    }
    
    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope(name: node.name.text, kind: .struct)
        return .visitChildren
    }
    
    public override func visitPost(_ node: StructDeclSyntax) {
        popScope()
    }
    
    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope(name: node.name.text, kind: .enum)
        return .visitChildren
    }
    
    public override func visitPost(_ node: EnumDeclSyntax) {
        popScope()
    }
    
    public override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope(name: node.name.text, kind: .protocol)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ProtocolDeclSyntax) {
        popScope()
    }
    
    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope(name: node.name.text, kind: .actor)
        return .visitChildren
    }
    
    public override func visitPost(_ node: ActorDeclSyntax) {
        popScope()
    }
    
    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope(name: node.name.text, kind: .function)
        return .visitChildren
    }
    
    public override func visitPost(_ node: FunctionDeclSyntax) {
        popScope()
    }
    
    public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        pushScope(name: "init", kind: .initializer)
        return .visitChildren
    }
    
    public override func visitPost(_ node: InitializerDeclSyntax) {
        popScope()
    }
    
    // MARK: - Variable Declaration Tracking (for type resolution)
    
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Track local variable types for better reference resolution
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            let varName = pattern.identifier.text
            
            // Try to get the type from explicit annotation
            if let typeAnnotation = binding.typeAnnotation {
                if let typeName = extractTypeName(from: typeAnnotation.type) {
                    registerLocalType(name: varName, typeName: typeName)
                    continue
                }
            }
            
            // Try to infer type from initializer
            if let initializer = binding.initializer?.value {
                if let inferredType = inferTypeFromExpression(initializer) {
                    registerLocalType(name: varName, typeName: inferredType)
                }
            }
        }
        return .visitChildren
    }
    
    /// Infer the type from an initializer expression
    private func inferTypeFromExpression(_ expr: ExprSyntax) -> String? {
        // Type() initializer call
        if let functionCall = expr.as(FunctionCallExprSyntax.self),
           let calledExpr = functionCall.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = calledExpr.baseName.text
            // If it starts with uppercase, it's likely a type initializer
            if let firstChar = name.first, firstChar.isUppercase {
                return name
            }
        }
        
        // Explicit type via "as Type" or "as? Type"
        if let asExpr = expr.as(AsExprSyntax.self) {
            return extractTypeName(from: asExpr.type)
        }
        
        // Member access: Module.Type() or EnumType.case
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            // For Type.init() pattern, the base is the type
            if let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
                let baseName = base.baseName.text
                if let firstChar = baseName.first, firstChar.isUppercase {
                    return baseName
                }
            }
        }
        
        // String/Array/Dictionary literals have known types
        if expr.is(StringLiteralExprSyntax.self) { return "String" }
        if expr.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if expr.is(FloatLiteralExprSyntax.self) { return "Double" }
        if expr.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        if expr.is(ArrayExprSyntax.self) { return "Array" }
        if expr.is(DictionaryExprSyntax.self) { return "Dictionary" }
        
        return nil
    }

    // MARK: - Expression Reference Visitors
    
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let calledExpr = node.calledExpression
        
        // Handle different call patterns
        if let declRef = calledExpr.as(DeclReferenceExprSyntax.self) {
            // Simple call: foo() or Type()
            let name = declRef.baseName.text
            
            // Check if it looks like a type (uppercase first letter) - likely initializer
            let kind: ReferenceKind
            if let firstChar = name.first, firstChar.isUppercase {
                kind = .initializer
            } else {
                kind = .functionCall
            }
            
            recordReference(
                name: name,
                fullExpression: name,
                kind: kind,
                position: declRef.position
            )
        } else if let memberAccess = calledExpr.as(MemberAccessExprSyntax.self) {
            // Method call: obj.method() or Type.staticMethod()
            let memberName = memberAccess.declName.baseName.text
            let fullExpr = calledExpr.description.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Try to determine if this is an initializer call (Type.init())
            // by checking if the base is a type reference
            if let base = memberAccess.base,
               let baseRef = base.as(DeclReferenceExprSyntax.self) {
                let baseName = baseRef.baseName.text
                // If member is "init", record as initializer of the base type
                if memberName == "init" {
                    recordReference(
                        name: baseName,
                        fullExpression: fullExpr,
                        kind: .initializer,
                        position: memberAccess.position
                    )
                } else {
                    // Resolve base type: self/Self → enclosing type, variable → tracked type
                    let resolvedBaseType: String?
                    if baseName == "self" || baseName == "Self" {
                        resolvedBaseType = findEnclosingType()
                    } else if let localType = lookupLocalType(baseName) {
                        resolvedBaseType = localType
                        // Record the base variable as being READ
                        recordReference(
                            name: baseName,
                            fullExpression: baseName,
                            kind: .identifier,
                            position: baseRef.position
                        )
                    } else {
                        resolvedBaseType = baseName
                        // Record untracked base variables as being accessed (e.g., swiftSyntaxVisitorMethods.union())
                        if let firstChar = baseName.first, !firstChar.isUppercase {
                            recordReference(
                                name: baseName,
                                fullExpression: baseName,
                                kind: .identifier,
                                position: baseRef.position
                            )
                        }
                    }
                    
                    recordReference(
                        name: memberName,
                        fullExpression: fullExpr,
                        kind: .functionCall,
                        position: memberAccess.declName.position,
                        inferredBaseType: resolvedBaseType
                    )
                }
            } else {
                recordReference(
                    name: memberName,
                    fullExpression: fullExpr,
                    kind: .functionCall,
                    position: memberAccess.declName.position
                )
            }
        }
        
        return .visitChildren
    }
    
    public override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Skip if this is part of a function call (handled by FunctionCallExprSyntax)
        // We check if the parent is a function call with this as the called expression
        if let parent = node.parent?.as(FunctionCallExprSyntax.self),
           parent.calledExpression.id == node.id {
            return .visitChildren
        }
        
        let memberName = node.declName.baseName.text
        let fullExpr = node.description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Determine the kind based on context
        var kind: ReferenceKind = .propertyAccess
        var inferredType: String? = nil
        
        // Check if base is a type name or variable
        if let base = node.base,
           let baseRef = base.as(DeclReferenceExprSyntax.self) {
            let baseName = baseRef.baseName.text
            
            // Handle self/Self member access - infer type from scope
            if baseName == "self" || baseName == "Self" {
                // Find the enclosing type from scope stack
                inferredType = findEnclosingType()
            } else if let localType = lookupLocalType(baseName) {
                // Variable with tracked type: instance.method() → resolve to type
                inferredType = localType
                
                // Record the base variable as being READ (fixes false positive for stored properties)
                recordReference(
                    name: baseName,
                    fullExpression: baseName,
                    kind: .identifier,
                    position: baseRef.position
                )
            } else {
                // Could be a type name for static access, or untracked variable
                inferredType = baseName
                
                // If base starts with uppercase, might be enum case or static member
                if let firstChar = baseName.first, firstChar.isUppercase {
                    // Could be enum case like MyEnum.value
                    kind = .enumCase
                    
                    // Record the type as being referenced for static member access
                    recordReference(
                        name: baseName,
                        fullExpression: baseName,
                        kind: .typeReference,
                        position: baseRef.position,
                        inferredBaseType: nil
                    )
                    
                    // For metatype access (TypeName.self), don't also record .self as a member
                    if memberName == "self" {
                        return .visitChildren
                    }
                } else {
                    // Lowercase base without tracked type - likely a property/variable being accessed
                    // Record it as being READ to prevent false positive dead code detection
                    recordReference(
                        name: baseName,
                        fullExpression: baseName,
                        kind: .identifier,
                        position: baseRef.position
                    )
                }
            }
        }
        
        recordReference(
            name: memberName,
            fullExpression: fullExpr,
            kind: kind,
            position: node.position,
            inferredBaseType: inferredType
        )
        
        return .visitChildren
    }
    
    /// Find the enclosing type name from the scope stack
    private func findEnclosingType() -> String? {
        // Walk the scope stack from innermost to outermost to find a type
        for entry in scopeStack.reversed() {
            switch entry.kind {
            case .class, .struct, .enum, .actor, .protocol, .extension:
                return entry.name
            default:
                continue
            }
        }
        return nil
    }
    
    public override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        // Skip 'self' and 'super' references
        let name = node.baseName.text
        if name == "self" || name == "super" || name == "Self" {
            return .visitChildren
        }
        
        // Skip if this is part of a function call or member access (handled elsewhere)
        if let parent = node.parent {
            if parent.is(FunctionCallExprSyntax.self) {
                return .visitChildren
            }
            if let memberAccess = parent.as(MemberAccessExprSyntax.self),
               memberAccess.base?.id == node.id {
                return .visitChildren
            }
        }
        
        recordReference(
            name: name,
            fullExpression: name,
            kind: .identifier,
            position: node.position
        )
        
        return .visitChildren
    }
    
    // MARK: - Type Reference Visitors
    
    public override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.name.text
        
        // Skip built-in types
        guard !isBuiltInType(typeName) else {
            return .visitChildren
        }
        
        recordReference(
            name: typeName,
            fullExpression: typeName,
            kind: .typeReference,
            position: node.position
        )
        
        // Also collect generic arguments
        if let genericArgs = node.genericArgumentClause {
            for arg in genericArgs.arguments {
                if let argTypeName = extractTypeName(from: arg.argument),
                   !isBuiltInType(argTypeName) {
                    recordReference(
                        name: argTypeName,
                        fullExpression: arg.argument.description.trimmingCharacters(in: .whitespacesAndNewlines),
                        kind: .genericArgument,
                        position: arg.position
                    )
                }
            }
        }
        
        return .visitChildren
    }
    
    public override func visit(_ node: InheritanceClauseSyntax) -> SyntaxVisitorContinueKind {
        for inheritedType in node.inheritedTypes {
            if let typeName = extractTypeName(from: inheritedType.type),
               !isBuiltInType(typeName) {
                // Determine if this is inheritance or conformance
                // Protocols start with uppercase and are often suffixed with -able, -ible, -Protocol
                // Classes also start with uppercase
                // Without type info, we default to conformance (more common)
                let kind: ReferenceKind = .conformance
                
                recordReference(
                    name: typeName,
                    fullExpression: inheritedType.type.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: kind,
                    position: inheritedType.position
                )
            }
        }
        
        return .visitChildren
    }
    
    public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Record the extended type as a reference
        let typeName: String
        if let simpleType = node.extendedType.as(IdentifierTypeSyntax.self) {
            typeName = simpleType.name.text
        } else {
            typeName = node.extendedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if !isBuiltInType(typeName) {
            recordReference(
                name: typeName,
                fullExpression: typeName,
                kind: .extensionTarget,
                position: node.position
            )
        }
        
        // Push scope for the extension
        pushScope(name: typeName, kind: .extension)
        
        return .visitChildren
    }
    
    public override func visitPost(_ node: ExtensionDeclSyntax) {
        popScope()
    }
    
    // MARK: - Additional Type Context Visitors
    
    public override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        // Handle qualified type names like Module.Type
        let typeName = node.name.text
        
        if !isBuiltInType(typeName) {
            recordReference(
                name: typeName,
                fullExpression: node.description.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .typeReference,
                position: node.position
            )
        }
        
        return .visitChildren
    }
    
    public override func visit(_ node: TypeExprSyntax) -> SyntaxVisitorContinueKind {
        // Handle .self type expressions like MyType.self
        if let typeName = extractTypeName(from: node.type),
           !isBuiltInType(typeName) {
            recordReference(
                name: typeName,
                fullExpression: node.description.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .typeReference,
                position: node.position
            )
        }
        
        return .visitChildren
    }
    
    // MARK: - Switch Case Pattern Visitors
    
    public override func visit(_ node: ExpressionPatternSyntax) -> SyntaxVisitorContinueKind {
        // Handle enum case patterns in switch statements like: case .enumCase:
        // The expression inside is typically a MemberAccessExprSyntax like .enumCase
        if let memberAccess = node.expression.as(MemberAccessExprSyntax.self) {
            let memberName = memberAccess.declName.baseName.text
            
            // This is an implicit member expression (shorthand enum case)
            // If base is nil, it's .enumCase (implicit enum type)
            // If base is present, it's EnumType.case
            var inferredType: String? = nil
            if let base = memberAccess.base,
               let baseRef = base.as(DeclReferenceExprSyntax.self) {
                inferredType = baseRef.baseName.text
            }
            
            recordReference(
                name: memberName,
                fullExpression: node.expression.description.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: .enumCase,
                position: node.position,
                inferredBaseType: inferredType
            )
        }
        
        return .visitChildren
    }
}
