import Foundation

/// Engine that executes analysis rules
public actor RuleEngine: Sendable {
    /// All registered rules
    private var rules: [Rule] = []
    /// Rules indexed by category
    private var rulesByCategory: [RuleCategory: [Rule]] = [:]

    /// Initialize with default rules
    public init() async {
        await registerDefaultRules()
    }

    /// Register a new rule
    public func register(_ rule: Rule) {
        rules.append(rule)
        rulesByCategory[rule.category, default: []].append(rule)
    }

    /// Register multiple rules
    public func register(_ rules: [Rule]) {
        for rule in rules {
            register(rule)
        }
    }

    /// Get all rules for a category
    public func rules(for category: RuleCategory) -> [Rule] {
        return rulesByCategory[category] ?? []
    }

    /// Get rule by ID
    public func rule(with id: String) -> Rule? {
        return rules.first { $0.id == id }
    }

    /// Get category for a rule ID
    public static func ruleCategory(for ruleId: String) -> RuleCategory {
        switch ruleId {
        case "force_unwrap", "force_try", "fatal_error", "mutable_static":
            return .safety
        case "non_sendable_capture", "unstructured_task", "actor_isolation", "data_race":
            return .concurrency
        case "layered_dependencies", "circular_dependency", "god_class", "global_state":
            return .architecture
        case "print_in_production":
            return .safety
        case "complexity_analysis":
            return .complexity
        case "enhanced_layered_dependencies":
            return .architecture
        case "enhanced_god_class":
            return .architecture
        case "architectural_health":
            return .architecture
        case "escaping_reference", "exclusive_access", "memory_leak", "retain_cycle":
            return .memory
        case "cyclomatic_complexity", "nesting_depth", "function_length":
            return .complexity
        case "module_boundary", "import_direction", "file_length", "type_count":
            return .architecture
        case "repeated_allocation", "large_struct_copy", "arc_churn", "hot_path_validation":
            return .performance
        default:
            return .architecture
        }
    }

    /// Analyze a source file with all applicable rules
    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext, configuration: Configuration) async -> [Violation] {
        var allViolations: [Violation] = []

        // Process each rule
        for rule in rules {
            // Check if rule should analyze this file using advanced configuration
            guard configuration.shouldAnalyze(ruleId: rule.id, file: sourceFile.url.path) else { continue }

            // Get rule-specific configuration
            let ruleConfig = configuration.configuration(for: rule.id, file: sourceFile.url.path)
            guard ruleConfig.enabled else { continue }

            // Check if the file should be analyzed by the rule itself
            guard rule.shouldAnalyze(sourceFile) else { continue }

            // Run the rule
            let violations = await rule.analyze(sourceFile, in: context)

            // Apply configuration severity
            let configuredViolations = violations.map { violation -> Violation in
                Violation(
                    ruleId: violation.ruleId,
                    category: violation.category,
                    severity: ruleConfig.severity,
                    message: violation.message,
                    location: violation.location,
                    relatedLocations: violation.relatedLocations,
                    suggestedFixes: violation.suggestedFixes,
                    context: violation.context
                )
            }

            allViolations.append(contentsOf: configuredViolations)
        }

        return allViolations
    }

    /// Analyze multiple files in parallel
    public func analyze(
        _ sourceFiles: [SourceFile],
        in context: AnalysisContext,
        configuration: Configuration
    ) async -> [Violation] {
        // Limit parallelism based on configuration
        let maxJobs = configuration.maxJobs
        let chunks = sourceFiles.chunked(into: maxJobs)

        var allViolations: [Violation] = []

        for chunk in chunks {
            await withTaskGroup(of: [Violation].self) { group in
                for sourceFile in chunk {
                    group.addTask {
                        await self.analyze(sourceFile, in: context, configuration: configuration)
                    }
                }

                for await violations in group {
                    allViolations.append(contentsOf: violations)
                }
            }
        }

        return allViolations
    }
}

/// Default rule registration
extension RuleEngine {
    private func registerDefaultRules() async {
        // Register the test rule to verify infrastructure
        register(ForceUnwrapRule())

        // Phase 1 Safety Rules
        register(ForceTryRule())
        register(FatalErrorRule())
        register(PrintInProductionRule())
        register(MutableStaticRule())

        // Phase 1 Concurrency Rules
        register(NonSendableCaptureRule())
        register(UnstructuredTaskRule())
        register(ActorIsolationRule())
        register(DataRaceRule())

        // Phase 1 Architecture Rules
        // Note: Using Enhanced versions which supersede the basic implementations
        // register(LayeredDependenciesRule())  // Superseded by EnhancedLayeredDependenciesRule
        register(CircularDependencyRule())
        // register(GodClassRule())  // Superseded by EnhancedGodClassRule
        register(GlobalStateRule())

        // Phase 1 Architecture Rules Complete ✅

        // Phase 2 Enhanced Rules using Infrastructure
        // These enhanced rules replace their basic counterparts with more sophisticated analysis
        register(EnhancedLayeredDependenciesRule())  // Replaces LayeredDependenciesRule
        register(EnhancedGodClassRule())  // Replaces GodClassRule
        register(ArchitecturalHealthRule())

        // Phase 3 Memory & Ownership Rules
        register(EscapingReferenceRule())
        register(ExclusiveAccessRule())

        // Phase 3 Complexity Rules
        register(CyclomaticComplexityRule())
        register(NestingDepthRule())
        register(FunctionLengthRule())

        // Phase 3 Enhanced Architecture Rules
        register(ModuleBoundaryRule())
        register(ImportDirectionRule())

        // Phase 3 Performance Rules
        register(RepeatedAllocationRule())
        register(LargeStructCopyRule())
        register(ARCChurnRule())
        register(HotPathValidationRule())
    }
}

/// Helper for chunking arrays
private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}