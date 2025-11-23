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

    /// Analyze a source file with all applicable rules
    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext, configuration: Configuration) async -> [Violation] {
        var allViolations: [Violation] = []

        // Process each rule
        for rule in rules {
            // Check if rule is enabled in configuration
            let ruleConfig = context.configuration.rules.configuration(for: rule.category)
            guard ruleConfig.enabled else { continue }

            // Check if the file should be analyzed
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
    private func registerDefaultRules() {
        // Register the test rule to verify infrastructure
        register(ForceUnwrapRule())

        // TODO: Register more rules in Phase 1
        // register(CircularDependencyRule())
        // register(NonSendableCaptureRule())
        // register(ForceTryRule())
        // register(MutableGlobalStateRule())
        // register(LongFunctionRule())
        // register(GodTypeRule())
        // etc.
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