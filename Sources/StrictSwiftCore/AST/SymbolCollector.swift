import Foundation
import SwiftSyntax

/// Walks the syntax tree and collects symbol information
public final class SymbolCollector: SyntaxAnyVisitor {
    public private(set) var symbols: [Symbol] = []
    private var currentAccessibility: Accessibility = .internal
    private let fileURL: URL
    private let converter: SourceLocationConverter

    public init(fileURL: URL, tree: SourceFileSyntax) {
        self.fileURL = fileURL
        self.converter = SourceLocationConverter(fileName: fileURL.path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = Symbol(
            name: node.name.text,
            kind: .class,
            location: location(from: node.position),
            accessibility: accessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes)
        )
        symbols.append(symbol)
        return .skipChildren
    }

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = Symbol(
            name: node.name.text,
            kind: .struct,
            location: location(from: node.position),
            accessibility: accessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes)
        )
        symbols.append(symbol)
        return .skipChildren
    }

    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = Symbol(
            name: node.name.text,
            kind: .enum,
            location: location(from: node.position),
            accessibility: accessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes)
        )
        symbols.append(symbol)
        return .skipChildren
    }

    public override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = Symbol(
            name: node.name.text,
            kind: .protocol,
            location: location(from: node.position),
            accessibility: accessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes)
        )
        symbols.append(symbol)
        return .skipChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let symbol = Symbol(
            name: node.name.text,
            kind: .function,
            location: location(from: node.position),
            accessibility: accessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes)
        )
        symbols.append(symbol)
        return .skipChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Only collect top-level variable declarations
        guard let binding = node.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier else {
            return .skipChildren
        }

        let symbol = Symbol(
            name: identifier.text,
            kind: .variable,
            location: location(from: node.position),
            accessibility: accessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes)
        )
        symbols.append(symbol)
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

        let symbol = Symbol(
            name: name,
            kind: .extension,
            location: location(from: node.position),
            accessibility: accessibility(from: node.modifiers),
            attributes: extractAttributes(from: node.attributes)
        )
        symbols.append(symbol)
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

                if let argumentList = attribute.arguments?.as(TupleExprElementListSyntax.self) {
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