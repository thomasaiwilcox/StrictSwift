import Foundation
import SwiftSyntax
import SwiftParser

/// Validates module-level boundaries and architectural constraints
public final class ModuleBoundaryValidator: Sendable {
    /// Represents a module boundary violation
    public struct BoundaryViolation: Codable, Hashable, Sendable {
        public let fromModule: String
        public let toModule: String
        public let dependencyType: DependencyType
        public let location: Location
        public let severity: DiagnosticSeverity
        public let description: String

        public init(fromModule: String, toModule: String, dependencyType: DependencyType, location: Location, severity: DiagnosticSeverity, description: String) {
            self.fromModule = fromModule
            self.toModule = toModule
            self.dependencyType = dependencyType
            self.location = location
            self.severity = severity
            self.description = description
        }
    }

    /// Types of dependencies that can violate module boundaries
    public enum DependencyType: String, Codable, CaseIterable, Sendable {
        case `import` = "import"
        case typeReference = "type_reference"
        case functionCall = "function_call"
        case inheritance = "inheritance"
        case conformance = "conformance"
        case property = "property"
        case parameter = "parameter"
        case returnValue = "return"
        case `extension` = "extension"
    }

    /// Module boundary policy
    public struct Policy: Codable, Sendable {
        public let allowedDependencies: [ModuleDependency]
        public let forbiddenDependencies: [ModuleDependency]
        public let moduleHierarchy: [ModuleHierarchy]
        public let internalModules: Set<String>

        public init(
            allowedDependencies: [ModuleDependency] = [],
            forbiddenDependencies: [ModuleDependency] = [],
            moduleHierarchy: [ModuleHierarchy] = [],
            internalModules: Set<String> = []
        ) {
            self.allowedDependencies = allowedDependencies
            self.forbiddenDependencies = forbiddenDependencies
            self.moduleHierarchy = moduleHierarchy
            self.internalModules = internalModules
        }
    }

    /// Represents a module dependency rule
    public struct ModuleDependency: Codable, Hashable, Sendable {
        public let fromModule: String
        public let toModule: String
        public let dependencyTypes: Set<DependencyType>

        public init(fromModule: String, toModule: String, dependencyTypes: Set<DependencyType> = Set(DependencyType.allCases)) {
            self.fromModule = fromModule
            self.toModule = toModule
            self.dependencyTypes = dependencyTypes
        }
    }

    /// Represents module hierarchy for architectural layers
    public struct ModuleHierarchy: Codable, Hashable, Sendable {
        public let layer: String
        public let modules: [String]
        public let allowedLowerLayers: [String]

        public init(layer: String, modules: [String], allowedLowerLayers: [String] = []) {
            self.layer = layer
            self.modules = modules
            self.allowedLowerLayers = allowedLowerLayers
        }
    }

    /// Module analysis result
    public struct ValidationResult: Sendable {
        public let violations: [BoundaryViolation]
        public let modules: Set<String>
        public let dependencies: [ModuleDependency]
        public let statistics: ValidationStatistics

        public init(violations: [BoundaryViolation], modules: Set<String>, dependencies: [ModuleDependency], statistics: ValidationStatistics) {
            self.violations = violations
            self.modules = modules
            self.dependencies = dependencies
            self.statistics = statistics
        }
    }

    /// Validation statistics
    public struct ValidationStatistics: Codable, Sendable {
        public let totalModules: Int
        public let totalDependencies: Int
        public let violationsCount: Int
        public let violationsBySeverity: [DiagnosticSeverity: Int]
        public let violationsByType: [DependencyType: Int]

        public init(totalModules: Int, totalDependencies: Int, violationsCount: Int, violationsBySeverity: [DiagnosticSeverity: Int], violationsByType: [DependencyType: Int]) {
            self.totalModules = totalModules
            self.totalDependencies = totalDependencies
            self.violationsCount = violationsCount
            self.violationsBySeverity = violationsBySeverity
            self.violationsByType = violationsByType
        }
    }

    private let policy: Policy

    public init(policy: Policy = ModuleBoundaryValidator.defaultPolicy()) {
        self.policy = policy
    }

    /// Validate module boundaries for source files
    public func validate(_ sourceFiles: [SourceFile]) -> ValidationResult {
        var allViolations: [BoundaryViolation] = []
        var allModules: Set<String> = []
        var allDependencies: Set<ModuleDependency> = []

        for sourceFile in sourceFiles {
            let result = validate(sourceFile)
            allViolations.append(contentsOf: result.violations)
            allModules.formUnion(result.modules)
            allDependencies.formUnion(result.dependencies)
        }

        let statistics = ValidationStatistics(
            totalModules: allModules.count,
            totalDependencies: allDependencies.count,
            violationsCount: allViolations.count,
            violationsBySeverity: Dictionary(grouping: allViolations) { $0.severity }.mapValues { $0.count },
            violationsByType: Dictionary(grouping: allViolations) { $0.dependencyType }.mapValues { $0.count }
        )

        return ValidationResult(
            violations: allViolations,
            modules: allModules,
            dependencies: Array(allDependencies),
            statistics: statistics
        )
    }

    /// Validate a single source file
    public func validate(_ sourceFile: SourceFile) -> ValidationResult {
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)

        var analyzer = ModuleBoundaryAnalyzer(
            sourceFile: sourceFile,
            policy: policy,
            tree: tree
        )
        analyzer.walk(tree)

        return analyzer.result
    }

    /// Check if dependency is allowed
    public func isDependencyAllowed(from fromModule: String, to toModule: String, type: DependencyType) -> Bool {
        // Check forbidden dependencies first
        for forbidden in policy.forbiddenDependencies {
            if modulesMatch(forbidden.fromModule, fromModule) &&
               modulesMatch(forbidden.toModule, toModule) &&
               forbidden.dependencyTypes.contains(type) {
                return false
            }
        }

        // Check allowed dependencies
        for allowed in policy.allowedDependencies {
            if modulesMatch(allowed.fromModule, fromModule) &&
               modulesMatch(allowed.toModule, toModule) &&
               allowed.dependencyTypes.contains(type) {
                return true
            }
        }

        // Check module hierarchy
        return checkHierarchyAllowed(from: fromModule, to: toModule)
    }

    // MARK: - Private Helper Methods

    private func checkHierarchyAllowed(from fromModule: String, to toModule: String) -> Bool {
        for hierarchy in policy.moduleHierarchy {
            if hierarchy.modules.contains(fromModule) {
                // Can depend on lower layers or same layer
                return hierarchy.allowedLowerLayers.contains(toModule) ||
                       hierarchy.modules.contains(toModule)
            }
        }

        // If not in hierarchy, default to allowed
        return true
    }

    private func modulesMatch(_ pattern: String, _ module: String) -> Bool {
        // Support wildcards and patterns
        if pattern == "*" {
            return true
        }

        if pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast())
            return module.hasPrefix(prefix)
        }

        if pattern.hasPrefix("*") {
            let suffix = String(pattern.dropFirst())
            return module.hasSuffix(suffix)
        }

        return pattern == module
    }

    // MARK: - Default Policies

    /// Clean architecture default policy
    public static func cleanArchitecturePolicy() -> Policy {
        let coreModules = ["Core", "Entities", "UseCases", "RepositoryInterfaces"]
        let dataModules = ["Data", "RepositoryImpl", "DataSource"]
        let presentationModules = ["Presentation", "ViewControllers", "Views"]
        let networkModules = ["Network", "API"]

        let hierarchy = [
            ModuleHierarchy(layer: "core", modules: coreModules),
            ModuleHierarchy(layer: "data", modules: dataModules, allowedLowerLayers: coreModules),
            ModuleHierarchy(layer: "presentation", modules: presentationModules, allowedLowerLayers: coreModules + dataModules),
            ModuleHierarchy(layer: "network", modules: networkModules, allowedLowerLayers: coreModules)
        ]

        return Policy(
            allowedDependencies: [],
            forbiddenDependencies: [
                ModuleDependency(fromModule: "core", toModule: "presentation"),
                ModuleDependency(fromModule: "core", toModule: "data"),
                ModuleDependency(fromModule: "data", toModule: "presentation"),
                ModuleDependency(fromModule: "presentation", toModule: "data"),
                ModuleDependency(fromModule: "network", toModule: "presentation")
            ],
            moduleHierarchy: hierarchy,
            internalModules: Set(coreModules + dataModules + presentationModules + networkModules)
        )
    }

    /// MVC architecture default policy
    public static func mvcPolicy() -> Policy {
        let modelModules = ["Model", "Entities"]
        let viewModules = ["View", "Views", "Views.*"]
        let controllerModules = ["Controller", "Controllers", "Controllers.*"]

        return Policy(
            allowedDependencies: [
                ModuleDependency(fromModule: "controller", toModule: "model"),
                ModuleDependency(fromModule: "controller", toModule: "view"),
                ModuleDependency(fromModule: "view", toModule: "model")
            ],
            forbiddenDependencies: [
                ModuleDependency(fromModule: "model", toModule: "controller"),
                ModuleDependency(fromModule: "model", toModule: "view"),
                ModuleDependency(fromModule: "view", toModule: "controller")
            ],
            moduleHierarchy: [],
            internalModules: Set(modelModules + viewModules + controllerModules)
        )
    }

    /// Default policy with common constraints
    public static func defaultPolicy() -> Policy {
        return Policy(
            allowedDependencies: [],
            forbiddenDependencies: [
                ModuleDependency(fromModule: "Test", toModule: "Production"),
                ModuleDependency(fromModule: "UI", toModule: "Business")
            ],
            moduleHierarchy: [],
            internalModules: Set()
        )
    }
}

/// Syntax analyzer for module boundary violations
private class ModuleBoundaryAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let policy: ModuleBoundaryValidator.Policy
    private let converter: SourceLocationConverter

    private var violations: [ModuleBoundaryValidator.BoundaryViolation] = []
    private var modules: Set<String> = []
    private var dependencies: Set<ModuleBoundaryValidator.ModuleDependency> = []
    private var currentModule: String = ""

    init(sourceFile: SourceFile, policy: ModuleBoundaryValidator.Policy, tree: SourceFileSyntax) {
        self.sourceFile = sourceFile
        self.policy = policy
        self.modules = Set<String>()
        self.converter = SourceLocationConverter(fileName: sourceFile.url.path, tree: tree)
        super.init(viewMode: .sourceAccurate)
        self.currentModule = extractModuleName(from: sourceFile.url)
        modules.insert(currentModule)
    }

    var result: ModuleBoundaryValidator.ValidationResult {
        let statistics = ModuleBoundaryValidator.ValidationStatistics(
            totalModules: modules.count,
            totalDependencies: dependencies.count,
            violationsCount: violations.count,
            violationsBySeverity: Dictionary(grouping: violations) { $0.severity }.mapValues { $0.count },
            violationsByType: Dictionary(grouping: violations) { $0.dependencyType }.mapValues { $0.count }
        )

        return ModuleBoundaryValidator.ValidationResult(
            violations: violations,
            modules: modules,
            dependencies: Array(dependencies),
            statistics: statistics
        )
    }

    // MARK: - Import Analysis

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let importedModule = extractImportedModule(from: node)
        modules.insert(importedModule)

        let dependency = ModuleBoundaryValidator.ModuleDependency(
            fromModule: currentModule,
            toModule: importedModule,
            dependencyTypes: [.import]
        )
        dependencies.insert(dependency)

        // Check boundary violation
        if !ModuleBoundaryValidator(policy: policy).isDependencyAllowed(
            from: currentModule,
            to: importedModule,
            type: .import
        ) {
            let violation = ModuleBoundaryValidator.BoundaryViolation(
                fromModule: currentModule,
                toModule: importedModule,
                dependencyType: .import,
                location: makeLocation(from: node.position),
                severity: .error,
                description: "Module '\(currentModule)' imports forbidden module '\(importedModule)'"
            )
            violations.append(violation)
        }

        return .skipChildren
    }

    // MARK: - Type Reference Analysis

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        analyzeTypeDeclaration(node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        analyzeTypeDeclaration(node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        analyzeTypeDeclaration(node.name.text, node: node)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        analyzeTypeDeclaration(node.name.text, node: node)
        return .visitChildren
    }

    // MARK: - Inheritance and Conformance Analysis

    override func visit(_ node: InheritanceClauseSyntax) -> SyntaxVisitorContinueKind {
        for inheritedType in node.inheritedTypes {
            let typeName = inheritedType.type.trimmedDescription
            let moduleName = extractModuleFromType(typeName)

            if !moduleName.isEmpty && moduleName != currentModule {
                let dependency = ModuleBoundaryValidator.ModuleDependency(
                    fromModule: currentModule,
                    toModule: moduleName,
                    dependencyTypes: [.inheritance]
                )
                dependencies.insert(dependency)

                checkDependencyViolation(
                    from: currentModule,
                    to: moduleName,
                    type: .inheritance,
                    location: inheritedType.position,
                    description: "Type inherits from module '\(moduleName)'"
                )
            }
        }

        return .visitChildren
    }

    // MARK: - Extension Analysis

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // In SwiftSyntax 600.0.0, extendedType is not optional
        let extendedType = node.extendedType
        let typeName = extendedType.trimmedDescription
        let moduleName = extractModuleFromType(typeName)

        if !moduleName.isEmpty && moduleName != currentModule {
            let dependency = ModuleBoundaryValidator.ModuleDependency(
                fromModule: currentModule,
                toModule: moduleName,
                dependencyTypes: [.extension]
            )
            dependencies.insert(dependency)

            checkDependencyViolation(
                from: currentModule,
                to: moduleName,
                type: .extension,
                location: node.position,
                description: "Extension extends type from module '\(moduleName)'"
            )
        }

        return .visitChildren
    }

    // MARK: - Helper Methods

    private func analyzeTypeDeclaration(_ typeName: String, node: DeclSyntaxProtocol) {
        // Check if type name suggests external module
        let moduleName = extractModuleFromType(typeName)

        if !moduleName.isEmpty && moduleName != currentModule {
            let dependency = ModuleBoundaryValidator.ModuleDependency(
                fromModule: currentModule,
                toModule: moduleName,
                dependencyTypes: [.typeReference]
            )
            dependencies.insert(dependency)

            checkDependencyViolation(
                from: currentModule,
                to: moduleName,
                type: .typeReference,
                location: node.position,
                description: "Type references module '\(moduleName)'"
            )
        }
    }

    private func checkDependencyViolation(
        from: String,
        to: String,
        type: ModuleBoundaryValidator.DependencyType,
        location: AbsolutePosition,
        description: String
    ) {
        if !ModuleBoundaryValidator(policy: policy).isDependencyAllowed(from: from, to: to, type: type) {
            let violation = ModuleBoundaryValidator.BoundaryViolation(
                fromModule: from,
                toModule: to,
                dependencyType: type,
                location: makeLocation(from: location),
                severity: determineSeverity(type: type),
                description: description
            )
            violations.append(violation)
        }
    }

    private func determineSeverity(type: ModuleBoundaryValidator.DependencyType) -> DiagnosticSeverity {
        switch type {
        case .import:
            return .error
        case .inheritance, .conformance:
            return .warning
        case .extension:
            return .warning
        case .typeReference, .functionCall, .property, .parameter, .returnValue:
            return .info
        }
    }

    private func extractModuleName(from url: URL) -> String {
        // Extract module name from file path
        let pathComponents = url.pathComponents
        if let sourcesIndex = pathComponents.firstIndex(of: "Sources") {
            let nextIndex = sourcesIndex + 1
            if nextIndex < pathComponents.count {
                return pathComponents[nextIndex]
            }
        }
        return "Unknown"
    }

    private func extractImportedModule(from importDecl: ImportDeclSyntax) -> String {
        return importDecl.path.map { $0.trimmedDescription }.joined(separator: ".")
    }

    private func extractModuleFromType(_ typeName: String) -> String {
        // Simple heuristic to extract module name from type
        let components = typeName.components(separatedBy: ".")

        // Common prefixes that suggest module names
        let commonModulePrefixes = ["Foundation", "SwiftUI", "UIKit", "Combine", "CoreData", "Network"]

        if components.count > 1 {
            let potentialModule = components[0]
            if commonModulePrefixes.contains(potentialModule) {
                return potentialModule
            }
        }

        // If we can't determine the module, return empty string
        return ""
    }

    private func makeLocation(from position: AbsolutePosition) -> Location {
        let converted = converter.location(for: position)
        return Location(
            file: sourceFile.url,
            line: converted.line,
            column: converted.column
        )
    }
}
