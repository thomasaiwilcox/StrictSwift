import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that enforces module-level boundaries and architectural constraints
/// SAFETY: @unchecked Sendable is safe because moduleValidator is created in init()
/// with an immutable policy and only performs read-only analysis.
public final class ModuleBoundaryRule: Rule, @unchecked Sendable {
    public var id: String { "module_boundary" }
    public var name: String { "Module Boundary" }
    public var description: String { "Enforces module-level boundaries and architectural layering constraints" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .error }
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
        let resolvedPolicyType = architecturePattern.isEmpty ? defaultPolicyType : architecturePattern

        let enforceLayering = ruleConfig.parameter("enforceLayering", defaultValue: true)
        let allowInternalDependencies = ruleConfig.parameter("allowInternalDependencies", defaultValue: !enforceLayering)

        let fallbackMaxDependencies = ruleConfig.parameter("maxDependencyDepth", defaultValue: 10)
        let maxModuleDependencies = ruleConfig.parameter("maxModuleDependencies", defaultValue: fallbackMaxDependencies)
        let detectCircularDependencies = ruleConfig.parameter("detectCircularDependencies", defaultValue: true)
        let forbiddenModules = ruleConfig.parameter("forbiddenModules", defaultValue: [String]())

        // Create validator with appropriate policy
        let policy = createPolicy(type: resolvedPolicyType, ruleConfig: ruleConfig)
        let validator = ModuleBoundaryValidator(policy: policy)

        // Validate file boundaries
        let validationResult = validator.validate(sourceFile)

        // Convert validation violations to rule violations
        violations.append(contentsOf: convertValidationViolations(
            validationResult.violations,
            ruleConfig: ruleConfig,
            sourceFile: sourceFile
        ))

        violations.append(contentsOf: analyzeForbiddenImports(
            sourceFile: sourceFile,
            forbiddenModules: forbiddenModules
        ))

        // Add additional architectural checks
        violations.append(contentsOf: analyzeArchitecturalViolations(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            validationResult: validationResult,
            allowInternalDependencies: allowInternalDependencies,
            maxModuleDependencies: maxModuleDependencies,
            detectCircularDependencies: detectCircularDependencies
        ))

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }

    // MARK: - Helper Methods

    private func createPolicy(type: String, ruleConfig: RuleSpecificConfiguration) -> ModuleBoundaryValidator.Policy {
        switch type {
        case "clean_architecture":
            return ModuleBoundaryValidator.cleanArchitecturePolicy()
        case "mvc":
            return ModuleBoundaryValidator.mvcPolicy()
        case "mvvm":
            return createMVVMPolicy(ruleConfig: ruleConfig)
        case "custom":
            return createCustomPolicy(ruleConfig: ruleConfig)
        default:
            return ModuleBoundaryValidator.cleanArchitecturePolicy()
        }
    }

    private func createMVVMPolicy(ruleConfig: RuleSpecificConfiguration) -> ModuleBoundaryValidator.Policy {
        let modelModules = ruleConfig.parameter("mvvmModelModules", defaultValue: ["Model", "Entities"])
        let viewModules = ruleConfig.parameter("mvvmViewModules", defaultValue: ["View", "Views"])
        let viewModelModules = ruleConfig.parameter("mvvmViewModelModules", defaultValue: ["ViewModel", "ViewModels"])

        return ModuleBoundaryValidator.Policy(
            allowedDependencies: [
                ModuleBoundaryValidator.ModuleDependency(fromModule: "view", toModule: "viewModel"),
                ModuleBoundaryValidator.ModuleDependency(fromModule: "viewModel", toModule: "model")
            ],
            forbiddenDependencies: [
                ModuleBoundaryValidator.ModuleDependency(fromModule: "model", toModule: "viewModel"),
                ModuleBoundaryValidator.ModuleDependency(fromModule: "viewModel", toModule: "view"),
                ModuleBoundaryValidator.ModuleDependency(fromModule: "view", toModule: "model")
            ],
            moduleHierarchy: [],
            internalModules: Set(modelModules + viewModules + viewModelModules)
        )
    }

    private func createCustomPolicy(ruleConfig: RuleSpecificConfiguration) -> ModuleBoundaryValidator.Policy {
        // Extract custom policy from configuration
        // For now, use empty arrays as defaults since complex configuration parsing needs more work
        let allowedDeps: [[String: Any]] = []
        let forbiddenDeps: [[String: Any]] = []

        var allowedDependencies: [ModuleBoundaryValidator.ModuleDependency] = []
        var forbiddenDependencies: [ModuleBoundaryValidator.ModuleDependency] = []

        for dep in allowedDeps {
            if let from = dep["from"] as? String, let to = dep["to"] as? String {
                allowedDependencies.append(ModuleBoundaryValidator.ModuleDependency(fromModule: from, toModule: to))
            }
        }

        for dep in forbiddenDeps {
            if let from = dep["from"] as? String, let to = dep["to"] as? String {
                forbiddenDependencies.append(ModuleBoundaryValidator.ModuleDependency(fromModule: from, toModule: to))
            }
        }

        return ModuleBoundaryValidator.Policy(
            allowedDependencies: allowedDependencies,
            forbiddenDependencies: forbiddenDependencies,
            moduleHierarchy: [],
            internalModules: []
        )
    }

    private func convertValidationViolations(
        _ violations: [ModuleBoundaryValidator.BoundaryViolation],
        ruleConfig: RuleSpecificConfiguration,
        sourceFile: SourceFile
    ) -> [Violation] {
        return violations.map { violation in
            ViolationBuilder(
                ruleId: id,
                category: .architecture,
                location: Location(
                    file: sourceFile.url,
                    line: violation.location.line,
                    column: violation.location.column
                )
            )
            .message(violation.description)
            .suggestFix(suggestFix(for: violation.dependencyType))
            .severity(overrideSeverity(violation.severity, with: ruleConfig.severity))
            .build()
        }
    }

    private func analyzeArchitecturalViolations(
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration,
        validationResult: ModuleBoundaryValidator.ValidationResult,
        allowInternalDependencies: Bool,
        maxModuleDependencies: Int,
        detectCircularDependencies: Bool
    ) -> [Violation] {
        var violations: [Violation] = []

        // Check for circular dependencies between modules
        if detectCircularDependencies {
            violations.append(contentsOf: checkCircularDependencies(validationResult: validationResult, sourceFile: sourceFile))
        }

        // Check for excessive module dependencies
        if validationResult.dependencies.count > maxModuleDependencies {
            let location = sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
            let violation = ViolationBuilder(
                ruleId: id,
                category: .architecture,
                location: location
            )
            .message("Module has \(validationResult.dependencies.count) dependencies (threshold: \(maxModuleDependencies))")
            .suggestFix("Reduce module coupling and consider reorganizing code")
            .severity(.warning)
            .build()

            violations.append(violation)
        }

        // Check for internal module violations
        if !allowInternalDependencies {
            violations.append(contentsOf: checkInternalDependencies(validationResult: validationResult, sourceFile: sourceFile))
        }

        return violations
    }

    private func analyzeForbiddenImports(
        sourceFile: SourceFile,
        forbiddenModules: [String]
    ) -> [Violation] {
        guard !forbiddenModules.isEmpty else { return [] }

        return sourceFile.imports.compactMap { importDecl in
            guard forbiddenModules.contains(importDecl.moduleName) else { return nil }

            return ViolationBuilder(
                ruleId: id,
                category: .architecture,
                location: importDecl.location
            )
            .message("Import of '\(importDecl.moduleName)' is forbidden by architectural policy")
            .suggestFix("Remove the import or provide an abstraction between modules")
            .severity(.error)
            .build()
        }
    }

    private func checkCircularDependencies(
        validationResult: ModuleBoundaryValidator.ValidationResult,
        sourceFile: SourceFile
    ) -> [Violation] {
        var violations: [Violation] = []

        // Build dependency graph for circular detection
        var dependencyMap: [String: Set<String>] = [:]

        for dep in validationResult.dependencies {
            dependencyMap[dep.fromModule, default: []].insert(dep.toModule)
        }

        // Simple circular dependency detection
        for (fromModule, toModules) in dependencyMap {
            for toModule in toModules {
                if dependencyMap[toModule]?.contains(fromModule) == true {
                    let location = sourceFile.location(for: AbsolutePosition(utf8Offset: 0))
                    let violation = ViolationBuilder(
                        ruleId: id,
                        category: .architecture,
                        location: location
                    )
                    .message("Circular dependency detected between modules: '\(fromModule)' and '\(toModule)'")
                    .suggestFix("Introduce abstraction layer or restructure dependencies")
                    .severity(.error)
                    .build()

                    violations.append(violation)
                }
            }
        }

        return violations
    }

    private func checkInternalDependencies(
        validationResult: ModuleBoundaryValidator.ValidationResult,
        sourceFile: SourceFile
    ) -> [Violation] {
        // Note: The previous implementation checked if function call text contained
        // "private" or "internal" as substrings, which produced false positives on:
        // - Enum cases like `.internalError`
        // - String literals containing "private" (e.g., "PRIVATE KEY" patterns)
        // - OSLog privacy annotations like `.private`
        //
        // Swift's compiler already enforces access control, so static analysis
        // cannot detect actual internal/private API access violations.
        // This check is disabled until a proper implementation is available.
        return []
    }

    private func suggestFix(for dependencyType: ModuleBoundaryValidator.DependencyType) -> String {
        switch dependencyType {
        case .import:
            return "Remove forbidden import or restructure module dependencies"
        case .inheritance:
            return "Use protocol-based design or dependency injection"
        case .conformance:
            return "Move protocol conformance to appropriate layer"
        case .extension:
            return "Avoid extending external module types or use appropriate architectural patterns"
        case .typeReference:
            return "Use interfaces or abstractions to decouple modules"
        case .functionCall:
            return "Use dependency injection or service locator pattern"
        case .property:
            return "Abstract property access through protocols"
        case .parameter:
            return "Use protocol types instead of concrete implementations"
        case .returnValue:
            return "Return interface types instead of concrete implementations"
        }
    }

    private func overrideSeverity(_ original: DiagnosticSeverity, with configured: DiagnosticSeverity) -> DiagnosticSeverity {
        switch (original, configured) {
        case (.error, _), (_, .error):
            return .error
        case (.warning, _), (_, .warning):
            return .warning
        default:
            return .info
        }
    }

    private func extractModuleName(from url: URL) -> String {
        let pathComponents = url.pathComponents
        if let sourcesIndex = pathComponents.firstIndex(of: "Sources") {
            let nextIndex = sourcesIndex + 1
            if nextIndex < pathComponents.count {
                return pathComponents[nextIndex]
            }
        }
        return "Unknown"
    }
}

/// Extension to support architectural pattern configuration
extension ModuleBoundaryRule {
    /// Create configuration for different architectural patterns
    public static func configuration(for pattern: ArchitecturalPattern) -> RuleSpecificConfiguration {
        switch pattern {
        case .cleanArchitecture:
            return RuleSpecificConfiguration(
                ruleId: "module_boundary",
                enabled: true,
                severity: .error,
                parameters: [
                    "policyType": .stringValue("clean_architecture"),
                    "allowInternalDependencies": .booleanValue(false),
                    "maxModuleDependencies": .integerValue(8)
                ]
            )

        case .mvc:
            return RuleSpecificConfiguration(
                ruleId: "module_boundary",
                enabled: true,
                severity: .warning,
                parameters: [
                    "policyType": .stringValue("mvc"),
                    "allowInternalDependencies": .booleanValue(true),
                    "maxModuleDependencies": .integerValue(12)
                ]
            )

        case .mvvm:
            return RuleSpecificConfiguration(
                ruleId: "module_boundary",
                enabled: true,
                severity: .warning,
                parameters: [
                    "policyType": .stringValue("mvvm"),
                    "allowInternalDependencies": .booleanValue(true),
                    "maxModuleDependencies": .integerValue(10),
                    "mvvmModelModules": .stringArrayValue(["Model", "Entities"]),
                    "mvvmViewModules": .stringArrayValue(["View", "Views"]),
                    "mvvmViewModelModules": .stringArrayValue(["ViewModel", "ViewModels"])
                ]
            )
        }
    }
}

/// Architectural patterns supported by module boundary validation
public enum ModuleArchitecturalPattern: String, CaseIterable {
    case cleanArchitecture = "clean_architecture"
    case mvc = "mvc"
    case mvvm = "mvvm"
    case custom = "custom"

    public var description: String {
        switch self {
        case .cleanArchitecture:
            return "Clean Architecture with strict layer separation"
        case .mvc:
            return "Model-View-Controller pattern"
        case .mvvm:
            return "Model-View-ViewModel pattern"
        case .custom:
            return "Custom architectural policy"
        }
    }
}
