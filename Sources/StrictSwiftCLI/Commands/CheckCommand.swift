import ArgumentParser
import Foundation
import StrictSwiftCore

/// Analyze Swift source files for safety violations
struct CheckCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Analyze Swift source files for safety violations"
    )

    @Argument(help: "The directory or files to analyze")
    var paths: [String] = ["Sources/"]

    @Option(name: .long, help: "Configuration profile to use")
    var profile: String = "critical-core"

    @Option(name: .long, help: "Path to configuration file")
    var config: String?

    @Option(name: .long, help: "Output format (human|json|agent)")
    var format: String = "human"

    @Option(name: .long, help: "Path to baseline file")
    var baseline: String?

    @Option(name: .long, help: "Fail on errors")
    var failOnError: Bool = true
    
    @Flag(name: .long, help: "Disable incremental analysis caching (caching is enabled by default)")
    var noCache: Bool = false
    
    @Flag(name: .long, help: "Clear the analysis cache before running")
    var clearCache: Bool = false
    
    @Flag(name: .long, help: "Show cache statistics after analysis")
    var cacheStats: Bool = false
    
    // Agent mode options
    @Option(name: .long, help: "Number of source context lines to include (agent format only)")
    var contextLines: Int = 0
    
    @Option(name: .long, help: "Minimum severity to report (error|warning|info|hint)")
    var minSeverity: String?
    
    // Semantic analysis options
    @Option(name: .long, help: "Semantic analysis mode (off|hybrid|full|auto). Default: auto")
    var semantic: String?
    
    @Flag(name: .long, help: "Fail if requested semantic mode is unavailable")
    var semanticStrict: Bool = false
    
    // Learning options
    @Flag(name: .long, help: "Enable learning system to improve accuracy based on feedback")
    var learning: Bool = false
    
    @Flag(name: .long, help: "Disable violation cache (.strictswift-last-run.json). Use for privacy or to avoid storing file paths/messages.")
    var noViolationCache: Bool = false
    
    // Debug options
    @Flag(name: .long, help: "Enable verbose logging including SourceKit debug info")
    var verbose: Bool = false

    func run() async throws {
        // Enable verbose logging if requested
        if verbose {
            StrictSwiftLogger.enableVerbose()
        }
        // Load configuration
        let profileEnum = Profile(rawValue: profile) ?? .criticalCore
        
        // Use explicit config path if provided, otherwise auto-discover from workspace
        let configURL: URL?
        if let configPath = config {
            configURL = URL(fileURLWithPath: configPath)
        } else {
            // Auto-discover config from current directory (project root)
            let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            configURL = Configuration.discover(in: currentDir)
            if let url = configURL {
                StrictSwiftLogger.info("Using configuration from \(url.path)")
            }
        }
        let baselineURL = baseline.map { URL(fileURLWithPath: $0) }

        // Apply any config file overrides and include baseline
        let finalConfiguration = Configuration.load(from: configURL, profile: profileEnum)

        // Load baseline from CLI flag if provided, otherwise use baseline from config file
        var baselineConfig: BaselineConfiguration?
        if let baselineURL = baselineURL,
           FileManager.default.fileExists(atPath: baselineURL.path) {
            // CLI flag overrides config file baseline
            baselineConfig = try BaselineConfiguration.load(from: baselineURL)
        } else if finalConfiguration.baseline != nil {
            // Use baseline from config file if no CLI flag provided
            baselineConfig = finalConfiguration.baseline
        }

        // Parse semantic mode from CLI
        let cliSemanticMode: SemanticMode? = semantic.flatMap { SemanticMode(rawValue: $0.lowercased()) }
        
        // Create final configuration with proper baseline handling
        let configurationWithBaseline = Configuration(
            profile: finalConfiguration.profile,
            rules: finalConfiguration.rules,
            baseline: baselineConfig,
            include: finalConfiguration.include,
            exclude: finalConfiguration.exclude,
            maxJobs: finalConfiguration.maxJobs,
            advanced: finalConfiguration.advanced,
            useEnhancedRules: finalConfiguration.useEnhancedRules,
            semanticMode: cliSemanticMode ?? finalConfiguration.semanticMode,
            semanticStrict: semanticStrict ? true : finalConfiguration.semanticStrict,
            perRuleSemanticModes: finalConfiguration.perRuleSemanticModes,
            perRuleSemanticStrict: finalConfiguration.perRuleSemanticStrict
        )

        // Set up caching (enabled by default, disable with --no-cache)
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var analysisCache: AnalysisCache?
        
        if !noCache {
            analysisCache = AnalysisCache(
                projectRoot: projectRoot,
                configuration: configurationWithBaseline,
                enabled: true
            )
            
            if clearCache {
                try await analysisCache?.clear()
                print("🗑️  Cache cleared")
            }
        }

        // Analyze files using either AnalysisRunner (learning mode) or Analyzer (standard)
        let violations: [Violation]
        var cacheHitRate: Double = 0.0
        var cachedFileCount: Int = 0
        var analyzedFileCount: Int = 0
        var learningStats: LearningStatisticsSummary?
        var suppressedCount: Int = 0
        
        if learning {
            // Use AnalysisRunner for learning integration
            let runner = AnalysisRunner(
                configuration: configurationWithBaseline,
                cache: analysisCache,
                learning: LearningSystem(projectRoot: projectRoot)
            )
            let result = try await runner.analyze(paths: paths)
            violations = result.violations
            learningStats = result.learningStats
            suppressedCount = result.suppressedCount
            if let cacheResult = result.cacheStats {
                cacheHitRate = cacheResult.hitRate
                cachedFileCount = cacheResult.cachedFiles
                analyzedFileCount = cacheResult.analyzedFiles
            }
            // Note: AnalysisRunner stores to ViolationCache internally; clear if disabled
            if noViolationCache {
                await ViolationCache.shared.clear()
            }
        } else {
            // Standard analysis without learning
            let analyzer = Analyzer(configuration: configurationWithBaseline, cache: analysisCache)
            
            if !noCache {
                let result = try await analyzer.analyzeIncremental(paths: paths)
                violations = result.violations
                cacheHitRate = result.cacheHitRate
                cachedFileCount = result.cachedFileCount
                analyzedFileCount = result.analyzedFileCount
            } else {
                violations = try await analyzer.analyze(paths: paths)
            }
            
            // Cache violations for feedback lookup even without learning mode
            if !noViolationCache {
                await ViolationCache.shared.storeViolations(violations)
            }
        }

        // Parse minimum severity filter
        let severityFilter: DiagnosticSeverity? = {
            guard let sev = minSeverity?.lowercased() else { return nil }
            switch sev {
            case "error": return .error
            case "warning": return .warning
            case "info": return .info
            case "hint": return .hint
            default: return nil
            }
        }()

        // Output results based on format
        let reporter: Reporter
        switch format.lowercased() {
        case "json":
            reporter = JSONReporter()
        case "agent":
            let options = AgentReporterOptions(
                contextLines: contextLines,
                includeFixes: true,
                minSeverity: severityFilter
            )
            reporter = AgentReporter(options: options)
        default:
            reporter = HumanReporter()
        }

        // Filter baseline violations for display (unless show-baseline flag is set)
        var violationsToReport = violations
        
        // Apply severity filter for non-agent formats (agent format handles internally)
        if format.lowercased() != "agent", let minSev = severityFilter {
            violationsToReport = violations.filter { severityRank($0.severity) >= severityRank(minSev) }
        }

        let report = try reporter.generateReport(violationsToReport)
        print(report, terminator: "")
        
        // Show cache statistics if requested (skip for agent format)
        if !noCache && cacheStats && format.lowercased() != "agent" {
            print("\n📊 Cache Statistics:")
            print("   Cache hit rate: \(String(format: "%.1f", cacheHitRate * 100))%")
            print("   Cached files: \(cachedFileCount)")
            print("   Analyzed files: \(analyzedFileCount)")
        }
        
        // Show learning statistics if in learning mode (skip for agent format)
        if learning && format.lowercased() != "agent" {
            print("\n📚 Learning Statistics:")
            if suppressedCount > 0 {
                print("   Suppressed based on feedback: \(suppressedCount)")
            }
            if let stats = learningStats {
                print("   Rules with feedback: \(stats.rulesWithFeedback)")
                print("   Overall accuracy: \(String(format: "%.1f%%", stats.overallAccuracy * 100))")
            }
        }

        // Exit with error code if configured to do so
        let errors = violationsToReport.filter { $0.severity == .error }
        if failOnError && !errors.isEmpty {
            // Agent format: exit silently, JSON already contains the info
            if format.lowercased() != "agent" {
                print("\n❌ Analysis failed with \(errors.count) error(s)")
            }
            throw ExitCode.failure
        }

        // Human-friendly summary (skip for agent/json formats)
        if format.lowercased() == "human" {
            if violationsToReport.isEmpty {
                print("\n✅ No violations found!")
            } else {
                let warnings = violationsToReport.filter { $0.severity == .warning }
                print("\n⚠️ Found \(violationsToReport.count) violation(s) (\(errors.count) error(s), \(warnings.count) warning(s))")
            }
        }
    }
    
    /// Severity ranking for filtering
    private func severityRank(_ severity: DiagnosticSeverity) -> Int {
        switch severity {
        case .error: return 4
        case .warning: return 3
        case .info: return 2
        case .hint: return 1
        }
    }
}