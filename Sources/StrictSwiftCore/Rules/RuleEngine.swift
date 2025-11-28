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
        case "non_sendable_capture", "unstructured_task", "actor_isolation", "data_race",
             "unowned_async", "mainactor_blocking":
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
        case "escaping_reference", "exclusive_access", "memory_leak", "retain_cycle",
             "combine_retain_cycle", "notification_observer", "weak_delegate":
            return .memory
        case "cyclomatic_complexity", "nesting_depth", "function_length":
            return .complexity
        case "module_boundary", "import_direction", "file_length", "type_count":
            return .architecture
        case "repeated_allocation", "large_struct_copy", "arc_churn", "hot_path_validation":
            return .performance
        case "hardcoded_secrets", "insecure_crypto", "sensitive_logging", "sql_injection_pattern":
            return .security
        case "assertion_coverage", "async_test_timeout", "test_isolation", "flaky_test_pattern":
            return .testing
        default:
            return .architecture
        }
    }

    /// Analyze a source file with all applicable rules (parallel rule execution)
    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext, configuration: Configuration) async -> [Violation] {
        // Filter applicable rules first
        let applicableRules = rules.filter { rule in
            guard configuration.shouldAnalyze(ruleId: rule.id, file: sourceFile.url.path) else { return false }
            let ruleConfig = configuration.configuration(for: rule.id, file: sourceFile.url.path)
            guard ruleConfig.enabled else { return false }
            return rule.shouldAnalyze(sourceFile)
        }
        
        // Run all applicable rules in parallel
        return await withTaskGroup(of: [Violation].self) { group in
            for rule in applicableRules {
                let ruleConfig = configuration.configuration(for: rule.id, file: sourceFile.url.path)
                
                group.addTask {
                    let violations = await rule.analyze(sourceFile, in: context)
                    
                    // Apply configuration severity
                    return violations.map { violation in
                        Violation(
                            ruleId: violation.ruleId,
                            category: violation.category,
                            severity: ruleConfig.severity,
                            message: violation.message,
                            location: violation.location,
                            relatedLocations: violation.relatedLocations,
                            suggestedFixes: violation.suggestedFixes,
                            structuredFixes: violation.structuredFixes,
                            context: violation.context
                        )
                    }
                }
            }
            
            var allViolations: [Violation] = []
            for await violations in group {
                allViolations.append(contentsOf: violations)
            }
            
            // Filter out suppressed violations
            // For cross-file rules, violations may be reported for different files than sourceFile
            // So we need to look up the correct suppression tracker for each violation's file
            return allViolations.filter { violation in
                // First try the current file's tracker (most common case)
                if violation.location.file == sourceFile.url {
                    return !sourceFile.suppressionTracker.isSuppressed(ruleId: violation.ruleId, line: violation.location.line)
                }
                
                // For cross-file violations, find the correct source file from context
                if let targetFile = context.allSourceFiles.first(where: { $0.url == violation.location.file }) {
                    return !targetFile.suppressionTracker.isSuppressed(ruleId: violation.ruleId, line: violation.location.line)
                }
                
                // If we can't find the file, don't suppress (safer)
                return true
            }
        }
    }

    /// Analyze multiple files in parallel with bounded concurrency
    public func analyze(
        _ sourceFiles: [SourceFile],
        in context: AnalysisContext,
        configuration: Configuration
    ) async -> [Violation] {
        let maxConcurrency = configuration.maxJobs
        
        return await withTaskGroup(of: [Violation].self) { group in
            var allViolations: [Violation] = []
            var pendingFiles = sourceFiles[...]
            var runningTasks = 0
            
            // Start initial batch of tasks up to maxConcurrency
            while runningTasks < maxConcurrency, let file = pendingFiles.popFirst() {
                group.addTask {
                    await self.analyze(file, in: context, configuration: configuration)
                }
                runningTasks += 1
            }
            
            // As tasks complete, start new ones to maintain concurrency
            for await violations in group {
                allViolations.append(contentsOf: violations)
                runningTasks -= 1
                
                // Start next task if there are more files
                if let file = pendingFiles.popFirst() {
                    group.addTask {
                        await self.analyze(file, in: context, configuration: configuration)
                    }
                    runningTasks += 1
                }
            }
            
            return allViolations
        }
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

        // Phase 5 Dead Code Detection
        register(DeadCodeRule())

        // Phase 1 Architecture Rules Complete ✅

        // Phase 2 Enhanced Rules using Infrastructure
        // These enhanced rules replace their basic counterparts with more sophisticated analysis
        register(EnhancedLayeredDependenciesRule())  // Replaces LayeredDependenciesRule
        register(EnhancedGodClassRule())  // Replaces GodClassRule
        register(ArchitecturalHealthRule())
        
        // Graph-enhanced rules (opt-in via useEnhancedRules: true)
        register(GraphEnhancedGodClassRule())  // Cross-file coupling analysis
        register(CouplingMetricsRule())  // Afferent/efferent coupling metrics
        register(CircularDependencyGraphRule())  // Graph-based cycle detection
        register(GraphEnhancedNonSendableCaptureRule())  // Sendable conformance checking

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
        register(StringConcatenationLoopRule())
        register(RegexCompilationInLoopRule())

        // Security Rules
        register(HardcodedSecretsRule())
        register(InsecureCryptoRule())
        register(SensitiveLoggingRule())
        register(SQLInjectionPatternRule())
        register(SwallowedErrorRule())
        register(ResourceLeakRule())

        // Testing Rules
        register(AssertionCoverageRule())
        register(AsyncTestTimeoutRule())
        register(TestIsolationRule())
        register(FlakyTestPatternRule())
        
        // Phase 6 Memory Rules (Community Feedback)
        register(CombineRetainCycleRule())
        register(NotificationObserverRule())
        register(WeakDelegateRule())
        
        // Phase 6 Concurrency Rules (Community Feedback)
        register(UnownedAsyncRule())
        register(MainActorBlockingRule())
    }
}