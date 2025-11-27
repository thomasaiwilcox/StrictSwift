import Foundation
import SwiftSyntax

// MARK: - Ambiguity Detector

/// Identifies references in code that require semantic analysis to resolve accurately
///
/// In hybrid mode, we only query SourceKit for references where syntactic analysis
/// is insufficient. This detector identifies those cases:
///
/// 1. Type-inferred variables (let x = someFunc())
/// 2. Protocol method calls (obj.method() where obj conforms to protocol)
/// 3. Generic type instantiations (Container<T>())
/// 4. Overloaded function calls
/// 5. Dynamic dispatch through protocol types
/// 6. Subscript access on generic collections
/// 7. Operator overloads
/// 8. Property access on type-inferred receivers
public struct AmbiguityDetector: Sendable {
    
    // MARK: - Types
    
    /// Represents an ambiguous reference that needs semantic resolution
    public struct AmbiguousReference: Sendable, Hashable {
        /// Location in source
        public let location: SourceLocation
        
        /// The expression or identifier text
        public let text: String
        
        /// Why this reference is ambiguous
        public let reason: AmbiguityReason
        
        /// Confidence that semantic analysis would help (0.0 - 1.0)
        public let confidenceNeed: Double
        
        /// Context about the reference
        public let context: ReferenceContext
    }
    
    /// Why a reference is ambiguous
    public enum AmbiguityReason: String, Sendable, Hashable {
        /// Variable declared with type inference
        case typeInferred = "type_inferred"
        
        /// Method call on a protocol type or existential
        case protocolDispatch = "protocol_dispatch"
        
        /// Generic type that could resolve to multiple concrete types
        case genericType = "generic_type"
        
        /// Function that has multiple overloads
        case overloadedFunction = "overloaded_function"
        
        /// Property access where receiver type is inferred
        case inferredReceiverProperty = "inferred_receiver_property"
        
        /// Method call where receiver type is inferred  
        case inferredReceiverMethod = "inferred_receiver_method"
        
        /// Subscript access on generic collection
        case genericSubscript = "generic_subscript"
        
        /// Operator that may be overloaded
        case operatorOverload = "operator_overload"
        
        /// Closure parameter with inferred type
        case closureParameter = "closure_parameter"
        
        /// Static member access that could be on extension
        case staticMemberAccess = "static_member_access"
    }
    
    /// Additional context about the reference
    public struct ReferenceContext: Sendable, Hashable {
        /// The identifier being referenced
        public let identifier: String
        
        /// Parent expression if this is a member access
        public let parentExpression: String?
        
        /// Whether this is in a return position
        public let isReturnValue: Bool
        
        /// Whether this is an argument to a function
        public let isArgument: Bool
        
        /// The containing function/method name if applicable
        public let containingFunction: String?
        
        public init(
            identifier: String,
            parentExpression: String? = nil,
            isReturnValue: Bool = false,
            isArgument: Bool = false,
            containingFunction: String? = nil
        ) {
            self.identifier = identifier
            self.parentExpression = parentExpression
            self.isReturnValue = isReturnValue
            self.isArgument = isArgument
            self.containingFunction = containingFunction
        }
    }
    
    /// Source location
    public struct SourceLocation: Sendable, Hashable {
        public let file: String
        public let line: Int
        public let column: Int
        
        public init(file: String, line: Int, column: Int) {
            self.file = file
            self.line = line
            self.column = column
        }
    }
    
    // MARK: - Detection
    
    /// Analyze a syntax tree and identify ambiguous references
    /// - Parameters:
    ///   - syntax: The parsed syntax tree
    ///   - filePath: Path to the source file
    ///   - knownTypes: Set of type names known from the codebase (helps filter)
    /// - Returns: List of ambiguous references that need semantic analysis
    public func detectAmbiguities(
        in syntax: SourceFileSyntax,
        filePath: String,
        knownTypes: Set<String> = []
    ) -> [AmbiguousReference] {
        let visitor = AmbiguityVisitor(filePath: filePath, knownTypes: knownTypes)
        visitor.walk(syntax)
        return visitor.ambiguities
    }
    
    /// Filter ambiguities to only high-value ones worth querying
    /// - Parameters:
    ///   - ambiguities: All detected ambiguities
    ///   - threshold: Minimum confidence threshold (default 0.6)
    /// - Returns: Filtered list of ambiguities worth querying
    public func filterHighValue(
        _ ambiguities: [AmbiguousReference],
        threshold: Double = 0.6
    ) -> [AmbiguousReference] {
        return ambiguities.filter { $0.confidenceNeed >= threshold }
    }
    
    /// Group ambiguities by file for efficient batch querying
    public func groupByFile(
        _ ambiguities: [AmbiguousReference]
    ) -> [String: [AmbiguousReference]] {
        return Dictionary(grouping: ambiguities) { $0.location.file }
    }
}

// MARK: - Syntax Visitor

private class AmbiguityVisitor: SyntaxVisitor {
    let filePath: String
    let knownTypes: Set<String>
    var ambiguities: [AmbiguityDetector.AmbiguousReference] = []
    
    // Track context as we descend
    private var currentFunction: String?
    private var isInReturnStatement = false
    private var isInArgumentList = false
    
    // Track variable declarations with inferred types
    private var inferredVariables: Set<String> = []
    
    init(filePath: String, knownTypes: Set<String>) {
        self.filePath = filePath
        self.knownTypes = knownTypes
        super.init(viewMode: .sourceAccurate)
    }
    
    // MARK: - Function Context
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunction = node.name.text
        return .visitChildren
    }
    
    override func visitPost(_ node: FunctionDeclSyntax) {
        currentFunction = nil
    }
    
    // MARK: - Return Statement Context
    
    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        isInReturnStatement = true
        return .visitChildren
    }
    
    override func visitPost(_ node: ReturnStmtSyntax) {
        isInReturnStatement = false
    }
    
    // MARK: - Variable Declarations with Inferred Types
    
    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        // Check if this is a variable without explicit type annotation
        if node.typeAnnotation == nil && node.initializer != nil {
            // This variable has an inferred type
            if let identPattern = node.pattern.as(IdentifierPatternSyntax.self) {
                inferredVariables.insert(identPattern.identifier.text)
                
                // Add ambiguity for the declaration if the initializer is complex
                if let initializer = node.initializer?.value,
                   isComplexInitializer(initializer) {
                    addAmbiguity(
                        node: initializer,
                        text: identPattern.identifier.text,
                        reason: .typeInferred,
                        confidence: 0.7,
                        context: AmbiguityDetector.ReferenceContext(
                            identifier: identPattern.identifier.text,
                            containingFunction: currentFunction
                        )
                    )
                }
            }
        }
        return .visitChildren
    }
    
    // MARK: - Member Access on Inferred Types
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Check if base is an identifier with inferred type
        if let base = node.base,
           let identifier = base.as(DeclReferenceExprSyntax.self),
           inferredVariables.contains(identifier.baseName.text) {
            addAmbiguity(
                node: node,
                text: "\(identifier.baseName.text).\(node.declName.baseName.text)",
                reason: .inferredReceiverProperty,
                confidence: 0.8,
                context: AmbiguityDetector.ReferenceContext(
                    identifier: node.declName.baseName.text,
                    parentExpression: identifier.baseName.text,
                    isReturnValue: isInReturnStatement,
                    isArgument: isInArgumentList,
                    containingFunction: currentFunction
                )
            )
        }
        
        return .visitChildren
    }
    
    // MARK: - Function Calls
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for method calls on inferred types
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base,
           let identifier = base.as(DeclReferenceExprSyntax.self),
           inferredVariables.contains(identifier.baseName.text) {
            addAmbiguity(
                node: node,
                text: "\(identifier.baseName.text).\(memberAccess.declName.baseName.text)()",
                reason: .inferredReceiverMethod,
                confidence: 0.85,
                context: AmbiguityDetector.ReferenceContext(
                    identifier: memberAccess.declName.baseName.text,
                    parentExpression: identifier.baseName.text,
                    isReturnValue: isInReturnStatement,
                    isArgument: isInArgumentList,
                    containingFunction: currentFunction
                )
            )
        }
        
        // Check for overloaded functions (multiple arguments with same name)
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let funcName = declRef.baseName.text
            // Simple heuristic: common function names that are often overloaded
            if isLikelyOverloaded(funcName) {
                addAmbiguity(
                    node: node,
                    text: funcName,
                    reason: .overloadedFunction,
                    confidence: 0.5,
                    context: AmbiguityDetector.ReferenceContext(
                        identifier: funcName,
                        isReturnValue: isInReturnStatement,
                        isArgument: isInArgumentList,
                        containingFunction: currentFunction
                    )
                )
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Subscript Access
    
    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for subscript on inferred type
        if let identifier = node.calledExpression.as(DeclReferenceExprSyntax.self),
           inferredVariables.contains(identifier.baseName.text) {
            addAmbiguity(
                node: node,
                text: "\(identifier.baseName.text)[]",
                reason: .genericSubscript,
                confidence: 0.75,
                context: AmbiguityDetector.ReferenceContext(
                    identifier: identifier.baseName.text,
                    isReturnValue: isInReturnStatement,
                    isArgument: isInArgumentList,
                    containingFunction: currentFunction
                )
            )
        }
        
        return .visitChildren
    }
    
    // MARK: - Closure Parameters
    
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for closure parameters without type annotations
        if let signature = node.signature,
           let parameterClause = signature.parameterClause {
            
            if let shorthand = parameterClause.as(ClosureShorthandParameterListSyntax.self) {
                for param in shorthand {
                    addAmbiguity(
                        node: param,
                        text: param.name.text,
                        reason: .closureParameter,
                        confidence: 0.6,
                        context: AmbiguityDetector.ReferenceContext(
                            identifier: param.name.text,
                            containingFunction: currentFunction
                        )
                    )
                }
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Operators
    
    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for custom operators
        if let op = node.operator.as(BinaryOperatorExprSyntax.self) {
            let opText = op.operator.text
            if isCustomOperator(opText) {
                addAmbiguity(
                    node: node,
                    text: opText,
                    reason: .operatorOverload,
                    confidence: 0.5,
                    context: AmbiguityDetector.ReferenceContext(
                        identifier: opText,
                        isReturnValue: isInReturnStatement,
                        isArgument: isInArgumentList,
                        containingFunction: currentFunction
                    )
                )
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Generic Types
    
    override func visit(_ node: GenericArgumentClauseSyntax) -> SyntaxVisitorContinueKind {
        // Mark uses of generic types as potentially ambiguous
        for arg in node.arguments {
            if let typeIdentifier = arg.argument.as(IdentifierTypeSyntax.self) {
                let typeName = typeIdentifier.name.text
                // Skip well-known stdlib types
                if !isStandardLibraryType(typeName) {
                    addAmbiguity(
                        node: arg,
                        text: typeName,
                        reason: .genericType,
                        confidence: 0.4,
                        context: AmbiguityDetector.ReferenceContext(
                            identifier: typeName,
                            containingFunction: currentFunction
                        )
                    )
                }
            }
        }
        
        return .visitChildren
    }
    
    // MARK: - Helpers
    
    private func addAmbiguity(
        node: some SyntaxProtocol,
        text: String,
        reason: AmbiguityDetector.AmbiguityReason,
        confidence: Double,
        context: AmbiguityDetector.ReferenceContext
    ) {
        let position = node.positionAfterSkippingLeadingTrivia
        let location = AmbiguityDetector.SourceLocation(
            file: filePath,
            line: position.line,
            column: position.column
        )
        
        let ambiguity = AmbiguityDetector.AmbiguousReference(
            location: location,
            text: text,
            reason: reason,
            confidenceNeed: confidence,
            context: context
        )
        
        ambiguities.append(ambiguity)
    }
    
    private func isComplexInitializer(_ expr: ExprSyntax) -> Bool {
        // Function call
        if expr.is(FunctionCallExprSyntax.self) { return true }
        // Method call chain
        if let member = expr.as(MemberAccessExprSyntax.self),
           member.base != nil { return true }
        // Subscript
        if expr.is(SubscriptCallExprSyntax.self) { return true }
        // Ternary
        if expr.is(TernaryExprSyntax.self) { return true }
        // Try expression
        if expr.is(TryExprSyntax.self) { return true }
        // Await expression
        if expr.is(AwaitExprSyntax.self) { return true }
        
        return false
    }
    
    private func isLikelyOverloaded(_ name: String) -> Bool {
        // Common function names that are often overloaded
        let overloadedNames: Set<String> = [
            "init", "make", "create", "build", "get", "set",
            "add", "remove", "update", "find", "search",
            "parse", "encode", "decode", "convert",
            "map", "filter", "reduce", "flatMap",
            "append", "insert", "contains"
        ]
        return overloadedNames.contains(name)
    }
    
    private func isCustomOperator(_ op: String) -> Bool {
        // Standard operators that are built-in
        let standardOperators: Set<String> = [
            "+", "-", "*", "/", "%",
            "==", "!=", "<", ">", "<=", ">=",
            "&&", "||", "!",
            "&", "|", "^", "~", "<<", ">>",
            "=", "+=", "-=", "*=", "/=",
            "..<", "...",
            "??", "?."
        ]
        return !standardOperators.contains(op)
    }
    
    private func isStandardLibraryType(_ name: String) -> Bool {
        let stdTypes: Set<String> = [
            "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Float", "Double", "String", "Bool",
            "Array", "Dictionary", "Set", "Optional",
            "Result", "Error", "Void", "Never",
            "Any", "AnyObject", "AnyHashable",
            "Comparable", "Equatable", "Hashable", "Codable",
            "Sendable", "Identifiable"
        ]
        return stdTypes.contains(name)
    }
}

// MARK: - Position Helper

private extension AbsolutePosition {
    /// Line number (1-indexed)
    var line: Int {
        // This is a placeholder - real implementation would use SourceLocationConverter
        return 1
    }
    
    /// Column number (1-indexed)
    var column: Int {
        // This is a placeholder - real implementation would use SourceLocationConverter
        return Int(utf8Offset)
    }
}
