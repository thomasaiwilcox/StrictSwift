import Foundation

/// Defines an architectural layer with its properties and constraints
public struct Layer: Hashable, Sendable {
    public let name: String
    public let pattern: String  // Regex pattern to identify files/types in this layer
    public let level: Int       // Hierarchical level (lower = closer to hardware/system)
    public let allowedDependencies: Set<String>  // Names of layers this can depend on

    public init(name: String, pattern: String, level: Int, allowedDependencies: Set<String> = []) {
        self.name = name
        self.pattern = pattern
        self.level = level
        self.allowedDependencies = allowedDependencies
    }
}

/// Defines an architectural layering policy
public struct ArchitecturePolicy: Sendable {
    public let name: String
    public let layers: [Layer]
    public let allowSameLevelDependencies: Bool
    public let allowLowerLevelDependencies: Bool

    public init(
        name: String,
        layers: [Layer],
        allowSameLevelDependencies: Bool = true,
        allowLowerLevelDependencies: Bool = true
    ) {
        self.name = name
        self.layers = layers
        self.allowSameLevelDependencies = allowSameLevelDependencies
        self.allowLowerLevelDependencies = allowLowerLevelDependencies
    }
}

/// Result of layer validation
public struct LayerViolation: Sendable {
    public let fromLayer: String
    public let toLayer: String
    public let dependencyType: DependencyType
    public let rule: String
    public let severity: DiagnosticSeverity

    public init(fromLayer: String, toLayer: String, dependencyType: DependencyType, rule: String, severity: DiagnosticSeverity) {
        self.fromLayer = fromLayer
        self.toLayer = toLayer
        self.dependencyType = dependencyType
        self.rule = rule
        self.severity = severity
    }
}

/// Validates architectural layering based on dependency graph
public final class LayerValidator: @unchecked Sendable {
    private let policy: ArchitecturePolicy

    public init(policy: ArchitecturePolicy) {
        self.policy = policy
    }

    /// Validate a dependency graph against the layering policy
    public func validate(_ graph: DependencyGraph) -> [LayerViolation] {
        var violations: [LayerViolation] = []

        // Create a mapping of file names to their layers
        let fileLayerMap = createFileLayerMapping(graph: graph)
        let typeLayerMap = createTypeLayerMapping(graph: graph)

        // Validate all dependencies
        for dependency in graph.allDependencies {
            if let violation = validateDependency(
                dependency: dependency,
                fileLayerMap: fileLayerMap,
                typeLayerMap: typeLayerMap
            ) {
                violations.append(violation)
            }
        }

        return violations
    }

    /// Get the layer for a specific file or type
    public func getLayer(for item: String, isFile: Bool = false) -> Layer? {
        for layer in policy.layers {
            if isFile {
                // Check file name patterns
                let regex = try? NSRegularExpression(pattern: layer.pattern)
                let range = NSRange(location: 0, length: item.utf16.count)
                if regex?.firstMatch(in: item, range: range) != nil {
                    return layer
                }
            } else {
                // Check type name patterns
                let regex = try? NSRegularExpression(pattern: layer.pattern)
                let range = NSRange(location: 0, length: item.utf16.count)
                if regex?.firstMatch(in: item, range: range) != nil {
                    return layer
                }
            }
        }
        return nil
    }

    // MARK: - Private Methods

    private func createFileLayerMapping(graph: DependencyGraph) -> [String: Layer] {
        var mapping: [String: Layer] = [:]

        for node in graph.allNodes {
            if node.type == .file, let layer = getLayer(for: node.name, isFile: true) {
                mapping[node.name] = layer
            }
        }

        return mapping
    }

    private func createTypeLayerMapping(graph: DependencyGraph) -> [String: Layer] {
        var mapping: [String: Layer] = [:]

        for node in graph.allNodes {
            if node.type == .class || node.type == .struct || node.type == .protocol, let layer = getLayer(for: node.name) {
                mapping[node.name] = layer
            }
        }

        return mapping
    }

    private func validateDependency(
        dependency: Dependency,
        fileLayerMap: [String: Layer],
        typeLayerMap: [String: Layer]
    ) -> LayerViolation? {
        // Determine the source and target layers
        let fromLayer = fileLayerMap[dependency.from] ?? typeLayerMap[dependency.from]
        let toLayer = fileLayerMap[dependency.to] ?? typeLayerMap[dependency.to]

        guard let sourceLayer = fromLayer, let targetLayer = toLayer else {
            // If either side doesn't belong to a layer, skip validation
            return nil
        }

        // Skip if source and target are in the same layer
        if sourceLayer.name == targetLayer.name {
            return nil
        }

        // Check if dependency is allowed
        if isDependencyAllowed(from: sourceLayer, to: targetLayer, type: dependency.type) {
            return nil
        }

        // Create violation
        let rule = "\(sourceLayer.name) -> \(targetLayer.name) dependency not allowed"
        let severity = determineSeverity(dependency: dependency, fromLayer: sourceLayer, toLayer: targetLayer)

        return LayerViolation(
            fromLayer: sourceLayer.name,
            toLayer: targetLayer.name,
            dependencyType: dependency.type,
            rule: rule,
            severity: severity
        )
    }

    private func isDependencyAllowed(from: Layer, to: Layer, type: DependencyType) -> Bool {
        // Check explicit allowed dependencies
        if from.allowedDependencies.contains(to.name) {
            return true
        }

        // Allow dependencies to lower levels (if enabled)
        // Lower level = more fundamental (lower number), so higher-to-lower means from.level > to.level
        if policy.allowLowerLevelDependencies && from.level > to.level {
            return true
        }

        // Allow dependencies to same level (if enabled)
        if policy.allowSameLevelDependencies && from.level == to.level {
            return true
        }

        // Special rules for specific dependency types
        switch type {
        case .protocolConformance:
            // Protocol conformance is generally more permissive
            return true

        case .extension:
            // Extensions are usually allowed
            return true

        case .importModule:
            // Module imports have special handling - allow imports from higher to lower levels
            return from.level >= to.level

        default:
            return false
        }
    }

    private func determineSeverity(dependency: Dependency, fromLayer: Layer, toLayer: Layer) -> DiagnosticSeverity {
        let levelDifference = abs(fromLayer.level - toLayer.level)

        // Higher severity for more severe violations
        if levelDifference > 2 {
            return .error
        } else if levelDifference > 1 {
            return .warning
        } else {
            return .info
        }
    }
}

// MARK: - Predefined Architecture Policies

extension LayerValidator {
    /// Create a classic Clean Architecture policy
    public static func cleanArchitecturePolicy() -> ArchitecturePolicy {
        let layers = [
            Layer(
                name: "Entities",
                pattern: ".*(Entity|Model).*",
                level: 1,
                allowedDependencies: []
            ),
            Layer(
                name: "UseCases",
                pattern: ".*(UseCase|Interactor).*",
                level: 2,
                allowedDependencies: ["Entities"]
            ),
            Layer(
                name: "InterfaceAdapters",
                pattern: ".*(Presenter|Controller|ViewModel|Adapter).*",
                level: 3,
                allowedDependencies: ["Entities", "UseCases"]
            ),
            Layer(
                name: "FrameworksAndDrivers",
                pattern: ".*(UI|Database|Network|API|External).*",
                level: 4,
                allowedDependencies: []
            )
        ]

        return ArchitecturePolicy(
            name: "Clean Architecture",
            layers: layers,
            allowSameLevelDependencies: false,
            allowLowerLevelDependencies: true
        )
    }

    /// Create a traditional layered architecture policy
    public static func layeredArchitecturePolicy() -> ArchitecturePolicy {
        let layers = [
            Layer(
                name: "Presentation",
                pattern: ".*(View|ViewController|Presenter|ViewModel).*",
                level: 1,
                allowedDependencies: ["Application", "Domain"]
            ),
            Layer(
                name: "Application",
                pattern: ".*(Service|Manager|UseCase|Application).*",
                level: 2,
                allowedDependencies: ["Domain", "Infrastructure"]
            ),
            Layer(
                name: "Domain",
                pattern: ".*(Entity|Domain|Repository|Model).*",
                level: 3,
                allowedDependencies: []
            ),
            Layer(
                name: "Infrastructure",
                pattern: ".*(Database|Network|External|Infrastructure).*",
                level: 4,
                allowedDependencies: []
            )
        ]

        return ArchitecturePolicy(
            name: "Layered Architecture",
            layers: layers,
            allowSameLevelDependencies: true,
            allowLowerLevelDependencies: true
        )
    }

    /// Create a modular architecture policy
    public static func modularArchitecturePolicy(modules: [String]) -> ArchitecturePolicy {
        let layers = modules.map { moduleName in
            Layer(
                name: moduleName,
                pattern: "\(moduleName).*",
                level: 1,
                allowedDependencies: Set(modules)
            )
        }

        return ArchitecturePolicy(
            name: "Modular Architecture",
            layers: layers,
            allowSameLevelDependencies: true,
            allowLowerLevelDependencies: true
        )
    }

    /// Create a simple three-tier architecture policy
    public static func threeTierArchitecturePolicy() -> ArchitecturePolicy {
        let layers = [
            Layer(
                name: "UI",
                pattern: ".*(View|Controller|UI).*",
                level: 1,
                allowedDependencies: ["Business"]
            ),
            Layer(
                name: "Business",
                pattern: ".*(Service|Business|Logic).*",
                level: 2,
                allowedDependencies: ["Data"]
            ),
            Layer(
                name: "Data",
                pattern: ".*(Data|Database|Repository).*",
                level: 3,
                allowedDependencies: []
            )
        ]

        return ArchitecturePolicy(
            name: "Three-Tier Architecture",
            layers: layers,
            allowSameLevelDependencies: false,
            allowLowerLevelDependencies: true
        )
    }
}