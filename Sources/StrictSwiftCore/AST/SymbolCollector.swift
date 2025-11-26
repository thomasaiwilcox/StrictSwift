import Foundation
import SwiftSyntax

/// Represents a scope in the symbol hierarchy
private struct ScopeEntry {
    let name: String
    let symbolID: SymbolID
}

/// Walks the syntax tree and collects symbol information with parent-child relationships
public final class SymbolCollector: SyntaxAnyVisitor {
    public private(set) var symbols: [Symbol] = []
    private var currentAccessibility: Accessibility = .internal
    private let fileURL: URL
    private let converter: SourceLocationConverter
    private let moduleName: String
    
    /// Stack tracking the current scope hierarchy for qualified name generation
    private var scopeStack: [ScopeEntry] = []

    public init(fileURL: URL, tree: SourceFileSyntax, moduleName: String = "Unknown") {
        self.fileURL = fileURL
        self.moduleName = moduleName
        self.converter = SourceLocationConverter(fileName: fileURL.path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }
    
    // MARK: - Scope Management
    
    /// Returns the current qualified name prefix based on the scope stack
    private var currentQualifiedPrefix: String {
        scopeStack.map(\.name).joined(separator: ".")
    }
    
    /// Returns the parent ID if we're inside a scope
    private var currentParentID: SymbolID? {
        scopeStack.last?.symbolID
    }
    
    /// Builds a qualified name from the current scope and a symbol name
    private func qualifiedName(for name: String) -> String {
        if scopeStack.isEmpty {
            return name
        }
        return "\(currentQualifiedPrefix).\(name)"
    }
    
    /// Creates a symbol and optionally visits children with scope tracking
    private func createSymbol(
        name: String,
        kind: SymbolKind,
        position: AbsolutePosition,
        modifiers: DeclModifierListSyntax,
        attributes: AttributeListSyntax,
        visitChildren: (() -> Void)? = nil
    ) {
        let loc = location(from: position)
        let qualified = qualifiedName(for: name)
        
        let symbolID = SymbolID.create(
            moduleName: moduleName,
            qualifiedName: qualified,
            kind: kind,
            filePath: fileURL.path,
            line: loc.line
        )
        
        let symbol = Symbol(
            id: symbolID,
            name: name,
            qualifiedName: qualified,
            kind: kind,
            location: loc,
            accessibility: accessibility(from: modifiers),
            attributes: extractAttributes(from: attributes),
            parentID: currentParentID
        )
        symbols.append(symbol)
        
        // If we should visit children, push scope and visit
        if let visitChildren = visitChildren {
            scopeStack.append(ScopeEntry(name: name, symbolID: symbolID))
            visitChildren()
            scopeStack.removeLast()
        }
    }

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .class,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        ) {
            // Visit members to collect nested types and methods
            for member in node.memberBlock.members {
                self.walk(member)
            }
        }
        return .skipChildren
    }

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .struct,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        ) {
            for member in node.memberBlock.members {
                self.walk(member)
            }
        }
        return .skipChildren
    }

    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .enum,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        ) {
            for member in node.memberBlock.members {
                self.walk(member)
            }
        }
        return .skipChildren
    }

    public override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .protocol,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        ) {
            for member in node.memberBlock.members {
                self.walk(member)
            }
        }
        return .skipChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .function,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        )
        // Functions don't create a new scope for collecting symbols
        return .skipChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Collect all variable declarations (handles let x = 1, y = 2 patterns)
        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
                continue
            }

            createSymbol(
                name: identifier.text,
                kind: .variable,
                position: binding.position,
                modifiers: node.modifiers,
                attributes: node.attributes
            )
        }
        return .skipChildren
    }

    public override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Get the extended type name
        let name: String
        if let simpleType = node.extendedType.as(IdentifierTypeSyntax.self) {
            name = simpleType.name.text
        } else {
            name = node.extendedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        createSymbol(
            name: name,
            kind: .extension,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        ) {
            for member in node.memberBlock.members {
                self.walk(member)
            }
        }
        return .skipChildren
    }
    
    public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: "init",
            kind: .initializer,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        )
        return .skipChildren
    }
    
    public override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: "deinit",
            kind: .deinitializer,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        )
        return .skipChildren
    }
    
    public override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: "subscript",
            kind: .subscript,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        )
        return .skipChildren
    }
    
    public override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .typeAlias,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        )
        return .skipChildren
    }
    
    public override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .associatedType,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        )
        return .skipChildren
    }
    
    // MARK: - Actor Declaration
    
    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .actor,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        ) {
            for member in node.memberBlock.members {
                self.walk(member)
            }
        }
        return .skipChildren
    }
    
    // MARK: - Operator Declarations
    
    public override func visit(_ node: OperatorDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .operator,
            position: node.position,
            modifiers: DeclModifierListSyntax([]),
            attributes: AttributeListSyntax([])
        )
        return .skipChildren
    }
    
    public override func visit(_ node: PrecedenceGroupDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .precedenceGroup,
            position: node.position,
            modifiers: DeclModifierListSyntax([]),
            attributes: AttributeListSyntax([])
        )
        return .skipChildren
    }
    
    // MARK: - Macro Declarations
    
    public override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        createSymbol(
            name: node.name.text,
            kind: .macro,
            position: node.position,
            modifiers: node.modifiers,
            attributes: node.attributes
        )
        return .skipChildren
    }
    
    public override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        // Each element in an enum case declaration creates a separate symbol
        for element in node.elements {
            let loc = location(from: element.position)
            let name = element.name.text
            let qualified = qualifiedName(for: name)
            
            let symbolID = SymbolID.create(
                moduleName: moduleName,
                qualifiedName: qualified,
                kind: .case,
                filePath: fileURL.path,
                line: loc.line
            )
            
            let symbol = Symbol(
                id: symbolID,
                name: name,
                qualifiedName: qualified,
                kind: .case,
                location: loc,
                accessibility: currentParentID != nil ? .internal : .internal,
                attributes: extractAttributes(from: node.attributes),
                parentID: currentParentID
            )
            symbols.append(symbol)
        }
        return .skipChildren
    }

    // MARK: - Helper Methods

    private func location(from position: AbsolutePosition) -> Location {
        let location = converter.location(for: position)
        return Location(
            file: fileURL,
            line: location.line,
            column: location.column
        )
    }

    private func accessibility(from modifiers: DeclModifierListSyntax) -> Accessibility {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.private):
                return .private
            case .keyword(.fileprivate):
                return .fileprivate
            case .keyword(.internal):
                return .internal
            case .keyword(.package):
                return .package
            case .keyword(.public):
                return .public
            case .keyword(.open):
                return .open
            default:
                continue
            }
        }
        return .internal
    }

    private func extractAttributes(from attributes: AttributeListSyntax) -> [Attribute] {
        var result: [Attribute] = []

        for attribute in attributes {
            if let attribute = attribute.as(AttributeSyntax.self) {
                let name = attribute.attributeName.trimmedDescription
                var arguments: [String] = []

                if let argumentList = attribute.arguments?.as(LabeledExprListSyntax.self) {
                    arguments = argumentList.description
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                }

                result.append(Attribute(name: name, arguments: arguments))
            }
        }

        return result
    }
}