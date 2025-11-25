import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that validates import dependency directions and architectural layering
/// SAFETY: @unchecked Sendable is safe because moduleValidator is created in init()
/// with an immutable policy and only performs read-only analysis.
public final class ImportDirectionRule: Rule, @unchecked Sendable {
    public var id: String { "import_direction" }
    public var name: String { "Import Direction" }
    public var description: String { "Validates import dependency directions and prevents architectural layering violations" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    // Infrastructure components for thread safety
    private let moduleValidator: ModuleBoundaryValidator

    public init() {
        self.moduleValidator = ModuleBoundaryValidator(policy: ModuleBoundaryValidator.cleanArchitecturePolicy())
    }

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []

        // Get configuration
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }

        // Get configuration parameters
        let defaultPolicyType = ruleConfig.parameter("policyType", defaultValue: "clean_architecture")
        let architecturePattern = ruleConfig.parameter("architecturePattern", defaultValue: defaultPolicyType)
        let policyType = architecturePattern.isEmpty ? defaultPolicyType : architecturePattern
        let enforceStrictLayering = ruleConfig.parameter("enforceStrictLayering", defaultValue: true)
        let allowTestImports = ruleConfig.parameter("allowTestImports", defaultValue: true)

        // Perform import analysis
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)

        let analyzer = ImportDirectionAnalyzer(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            policyType: policyType,
            enforceStrictLayering: enforceStrictLayering,
            allowTestImports: allowTestImports
        )
        analyzer.walk(tree)

        violations.append(contentsOf: analyzer.violations)

        let maxImportsPerFile = ruleConfig.parameter("maxImportsPerFile", defaultValue: 25)
        if analyzer.totalImports > maxImportsPerFile, let importLocation = analyzer.firstImportLocation {
            let locationInfo = sourceFile.location(for: importLocation)
            let violation = ViolationBuilder(
                ruleId: id,
                category: .architecture,
                location: locationInfo
            )
            .message("File imports \(analyzer.totalImports) modules (limit: \(maxImportsPerFile))")
            .suggestFix("Reduce the number of imports or split responsibilities across smaller files")
            .severity(.info)
            .build()

            violations.append(violation)
        }

        // Add architectural layer analysis
        violations.append(contentsOf: analyzeArchitecturalLayers(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            policyType: policyType
        ))

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }

    // MARK: - Helper Methods

    private func analyzeArchitecturalLayers(
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration,
        policyType: String
    ) -> [Violation] {
        var violations: [Violation] = []

        let currentLayer = determineArchitecturalLayer(for: sourceFile, policyType: policyType)
        if currentLayer.isEmpty {
            return violations
        }

        let source = sourceFile.source()
        let tree = Parser.parse(source: source)

        let layerAnalyzer = ArchitecturalLayerAnalyzer(
            sourceFile: sourceFile,
            currentLayer: currentLayer,
            policyType: policyType,
            ruleConfig: ruleConfig
        )
        layerAnalyzer.walk(tree)

        violations.append(contentsOf: layerAnalyzer.violations)

        return violations
    }

    private func determineArchitecturalLayer(for sourceFile: SourceFile, policyType: String) -> String {
        let pathComponents = sourceFile.url.pathComponents

        switch policyType {
        case "clean_architecture":
            // Check for clean architecture layer indicators
            if pathComponents.contains("Core") || pathComponents.contains("Entities") {
                return "core"
            } else if pathComponents.contains("UseCases") {
                return "use_cases"
            } else if pathComponents.contains("Data") || pathComponents.contains("Repository") {
                return "data"
            } else if pathComponents.contains("Presentation") || pathComponents.contains("View") {
                return "presentation"
            } else if pathComponents.contains("Network") {
                return "network"
            }

        case "mvc":
            if pathComponents.contains("Model") {
                return "model"
            } else if pathComponents.contains("View") {
                return "view"
            } else if pathComponents.contains("Controller") {
                return "controller"
            }

        case "mvvm":
            if pathComponents.contains("Model") {
                return "model"
            } else if pathComponents.contains("View") {
                return "view"
            } else if pathComponents.contains("ViewModel") {
                return "viewmodel"
            }

        default:
            break
        }

        return ""
    }
}

/// Syntax analyzer for import direction violations
private class ImportDirectionAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let ruleConfig: RuleSpecificConfiguration
    private let policyType: String
    private let enforceStrictLayering: Bool
    private let allowTestImports: Bool

    var violations: [Violation] = []
    private var importedModules: Set<String> = []
    private var importLocations: [String: AbsolutePosition] = [:]
    private var importCount: Int = 0
    private var firstImportPosition: AbsolutePosition?

    var totalImports: Int { importCount }
    var firstImportLocation: AbsolutePosition? { firstImportPosition }

    init(sourceFile: SourceFile, ruleConfig: RuleSpecificConfiguration, policyType: String, enforceStrictLayering: Bool, allowTestImports: Bool) {
        self.sourceFile = sourceFile
        self.ruleConfig = ruleConfig
        self.policyType = policyType
        self.enforceStrictLayering = enforceStrictLayering
        self.allowTestImports = allowTestImports
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let importedModule = extractImportedModule(from: node)
        let location = node.position

        importCount += 1
        if firstImportPosition == nil {
            firstImportPosition = location
        }
        importedModules.insert(importedModule)
        importLocations[importedModule] = location

        // Check for forbidden imports
        if isForbiddenImport(importedModule) {
            let locationInfo = sourceFile.location(for: location)
            let violation = ViolationBuilder(
                ruleId: "import_direction",
                category: .architecture,
                location: locationInfo
            )
            .message("Forbidden import detected: '\(importedModule)'")
            .suggestFix("Remove forbidden import or restructure dependencies")
            .severity(.error)
            .build()

            violations.append(violation)
        }

        // Check for deprecated imports
        if isDeprecatedImport(importedModule) {
            let locationInfo = sourceFile.location(for: location)
            let violation = ViolationBuilder(
                ruleId: "import_direction",
                category: .architecture,
                location: locationInfo
            )
            .message("Deprecated import detected: '\(importedModule)'")
            .suggestFix("Use modern alternative: \(suggestedAlternative(for: importedModule))")
            .severity(.warning)
            .build()

            violations.append(violation)
        }

        // Check for test imports in production code
        if !allowTestImports && isTestImport(importedModule) {
            let locationInfo = sourceFile.location(for: location)
            let violation = ViolationBuilder(
                ruleId: "import_direction",
                category: .architecture,
                location: locationInfo
            )
            .message("Test import in production code: '\(importedModule)'")
            .suggestFix("Remove test imports from production code")
            .severity(.error)
            .build()

            violations.append(violation)
        }

        // Check for redundant imports
        if isRedundantImport(importedModule) {
            let locationInfo = sourceFile.location(for: location)
            let violation = ViolationBuilder(
                ruleId: "import_direction",
                category: .architecture,
                location: locationInfo
            )
            .message("Redundant import: '\(importedModule)' is imported by default")
            .suggestFix("Remove redundant import")
            .severity(.info)
            .build()

            violations.append(violation)
        }

        return .skipChildren
    }

    // MARK: - Helper Methods

    private func extractImportedModule(from importDecl: ImportDeclSyntax) -> String {
        return importDecl.path.map { $0.trimmedDescription }.joined(separator: ".")
    }

    private func isForbiddenImport(_ module: String) -> Bool {
        let forbiddenModules = ruleConfig.parameter("forbiddenImports", defaultValue: [String]())

        // Check configuration
        if forbiddenModules.contains(module) {
            return true
        }

        // Check for pattern-based forbidden imports
        let forbiddenPatterns = ruleConfig.parameter("forbiddenImportPatterns", defaultValue: [String]())
        for pattern in forbiddenPatterns {
            if module.hasPrefix(pattern) {
                return true
            }
        }

        // Built-in forbidden imports based on architectural pattern
        switch policyType {
        case "clean_architecture":
            let forbiddenCleanArchitecture = ["Foundation"].contains(module)
            return false // Foundation is generally allowed

        case "mvc":
            // MVC specific rules
            break

        case "mvvm":
            // MVVM specific rules
            break

        default:
            break
        }

        return false
    }

    private func isDeprecatedImport(_ module: String) -> Bool {
        let deprecatedImports = [
            "UIKit": "Use SwiftUI instead",
            "AppKit": "Use SwiftUI instead",
            "CoreGraphics": "Use SwiftUI graphics primitives"
        ]

        return deprecatedImports.keys.contains(module)
    }

    private func suggestedAlternative(for deprecatedModule: String) -> String {
        let alternatives = [
            "UIKit": "SwiftUI",
            "AppKit": "SwiftUI",
            "CoreGraphics": "SwiftUI graphics"
        ]

        return alternatives[deprecatedModule] ?? "modern alternative"
    }

    private func isTestImport(_ module: String) -> Bool {
        return module.hasPrefix("XCTest") || module.contains("Testing") || module.contains("Test")
    }

    private func isRedundantImport(_ module: String) -> Bool {
        let automaticallyImported = [
            "Swift", "Foundation", "Darwin"
        ]

        // Only consider redundant if explicitly configured
        let checkRedundant = ruleConfig.parameter("checkRedundantImports", defaultValue: false)
        return checkRedundant && automaticallyImported.contains(module)
    }
}

/// Analyzer for architectural layer violations
private class ArchitecturalLayerAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let currentLayer: String
    private let policyType: String
    private let ruleConfig: RuleSpecificConfiguration

    var violations: [Violation] = []

    init(sourceFile: SourceFile, currentLayer: String, policyType: String, ruleConfig: RuleSpecificConfiguration) {
        self.sourceFile = sourceFile
        self.currentLayer = currentLayer
        self.policyType = policyType
        self.ruleConfig = ruleConfig
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let calledFunction = node.calledExpression.trimmedDescription
        checkLayerViolation(expression: calledFunction, location: node.position)
        return .visitChildren
    }

    override func visit(_ node: TypeExprSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.type.trimmedDescription
        checkLayerViolation(expression: typeName, location: node.position)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let memberAccess = node.trimmedDescription
        checkLayerViolation(expression: memberAccess, location: node.position)
        return .visitChildren
    }

    // MARK: - Helper Methods

    private func checkLayerViolation(expression: String, location: AbsolutePosition) {
        let targetLayer = determineTargetLayer(from: expression)

        if !targetLayer.isEmpty && isLayerViolation(from: currentLayer, to: targetLayer) {
            let locationInfo = sourceFile.location(for: location)
            let violation = ViolationBuilder(
                ruleId: "import_direction",
                category: .architecture,
                location: locationInfo
            )
            .message("Architectural layer violation: '\(currentLayer)' layer accessing '\(targetLayer)' layer")
            .suggestFix("Use proper architectural patterns to access layers: \(layeringGuidance(from: currentLayer, to: targetLayer))")
            .severity(.warning)
            .build()

            violations.append(violation)
        }
    }

    private func determineTargetLayer(from expression: String) -> String {
        switch policyType {
        case "clean_architecture":
            if expression.contains("ViewController") || expression.contains("View") {
                return "presentation"
            } else if expression.contains("Repository") || expression.contains("DataSource") {
                return "data"
            } else if expression.contains("Entity") || expression.contains("Core") {
                return "core"
            } else if expression.contains("UseCase") {
                return "use_cases"
            }

        case "mvc":
            if expression.contains("View") || expression.contains("Button") {
                return "view"
            } else if expression.contains("Controller") {
                return "controller"
            } else if expression.contains("Model") {
                return "model"
            }

        case "mvvm":
            if expression.contains("View") {
                return "view"
            } else if expression.contains("ViewModel") {
                return "viewmodel"
            } else if expression.contains("Model") {
                return "model"
            }

        default:
            break
        }

        return ""
    }

    private func isLayerViolation(from: String, to: String) -> Bool {
        // Define allowed layer transitions based on architectural pattern
        switch policyType {
        case "clean_architecture":
            // Clean Architecture: Outer layers can depend on inner layers, but not vice versa
            let layerOrder = ["core", "use_cases", "data", "presentation", "network"]
            let fromIndex = layerOrder.firstIndex(of: from) ?? -1
            let toIndex = layerOrder.firstIndex(of: to) ?? -1

            // Cannot depend on outer layers (higher index)
            return fromIndex < toIndex

        case "mvc":
            // MVC: Controller can depend on both Model and View, View can depend on Model
            switch (from, to) {
            case ("model", "view"), ("model", "controller"):
                return true
            case ("view", "controller"):
                return true
            default:
                return false
            }

        case "mvvm":
            // MVVM: ViewModel can depend on Model, View can depend on ViewModel
            switch (from, to) {
            case ("model", "viewmodel"), ("model", "view"):
                return true
            case ("viewmodel", "view"):
                return false // View depends on ViewModel, not vice versa
            case ("view", "viewmodel"):
                return true
            default:
                return false
            }

        default:
            return false
        }
    }

    private func layeringGuidance(from: String, to: String) -> String {
        switch policyType {
        case "clean_architecture":
            return "Use dependency injection and protocols to invert dependencies"
        case "mvc":
            return "Controller should coordinate between Model and View"
        case "mvvm":
            return "ViewModel should be injected into View, not accessed directly"
        default:
            return "Follow architectural layering principles"
        }
    }
}
