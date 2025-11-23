import Foundation
import SwiftSyntax

/// Walks the syntax tree and collects import statements
public final class ImportTracker: SyntaxAnyVisitor {
    public private(set) var imports: [Import] = []
    private let fileURL: URL
    private let converter: SourceLocationConverter

    public init(fileURL: URL, tree: SourceFileSyntax) {
        self.fileURL = fileURL
        self.converter = SourceLocationConverter(fileName: fileURL.path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    public override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // Extract the module name
        let moduleName: String
        if let simpleImport = node.path.first?.as(ImportPathComponentSyntax.self) {
            moduleName = simpleImport.name.text
        } else {
            moduleName = node.path.trimmedDescription
        }

        // Determine import kind
        let kind: ImportKind
        if let importKind = node.importKindSpecifier {
            switch importKind.tokenKind {
            case .keyword(.typealias):
                kind = .typealias
            case .keyword(.struct):
                kind = .struct
            case .keyword(.class):
                kind = .class
            case .keyword(.enum):
                kind = .enum
            case .keyword(.protocol):
                kind = .protocol
            case .keyword(.var):
                kind = .var
            case .keyword(.func):
                kind = .func
            case .keyword(.let):
                kind = .let
            default:
                kind = .regular
            }
        } else {
            kind = .regular
        }

        let location = Location(
            file: fileURL,
            line: converter.location(for: node.position).line,
            column: converter.location(for: node.position).column
        )

        let `import` = Import(
            moduleName: moduleName,
            kind: kind,
            location: location
        )

        imports.append(`import`)
        return .skipChildren
    }
}