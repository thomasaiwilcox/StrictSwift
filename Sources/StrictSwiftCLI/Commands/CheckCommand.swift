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

    @Option(name: .long, help: "Output format (human|json)")
    var format: String = "human"

    @Option(name: .long, help: "Path to baseline file")
    var baseline: String?

    @Option(name: .long, help: "Fail on errors")
    var failOnError: Bool = true
    
    @Flag(name: .long, help: "Enable incremental analysis with caching")
    var cache: Bool = false
    
    @Flag(name: .long, help: "Clear the analysis cache before running")
    var clearCache: Bool = false
    
    @Flag(name: .long, help: "Show cache statistics after analysis")
    var cacheStats: Bool = false

    func run() async throws {
        // Load configuration
        let profileEnum = Profile(rawValue: profile) ?? .criticalCore
        let configURL = config.map { URL(fileURLWithPath: $0) }
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

        // Create final configuration with proper baseline handling
        let configurationWithBaseline = Configuration(
            profile: finalConfiguration.profile,
            rules: finalConfiguration.rules,
            baseline: baselineConfig,
            include: finalConfiguration.include,
            exclude: finalConfiguration.exclude,
            maxJobs: finalConfiguration.maxJobs,
            advanced: finalConfiguration.advanced
        )

        // Set up caching if enabled
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var analysisCache: AnalysisCache?
        
        if cache {
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

        // Create analyzer with optional cache
        let analyzer = Analyzer(configuration: configurationWithBaseline, cache: analysisCache)

        // Analyze files (incremental if cache enabled)
        let violations: [Violation]
        var cacheHitRate: Double = 0.0
        var cachedFileCount: Int = 0
        var analyzedFileCount: Int = 0
        
        if cache {
            let result = try await analyzer.analyzeIncremental(paths: paths)
            violations = result.violations
            cacheHitRate = result.cacheHitRate
            cachedFileCount = result.cachedFileCount
            analyzedFileCount = result.analyzedFileCount
        } else {
            violations = try await analyzer.analyze(paths: paths)
        }

        // Output results
        let reporter: Reporter = format == "json" ? JSONReporter() : HumanReporter()

        // Filter baseline violations for display (unless show-baseline flag is set)
        let violationsToReport = violations

        let report = try reporter.generateReport(violationsToReport)
        print(report, terminator: "")
        
        // Show cache statistics if requested
        if cache && cacheStats {
            print("\n📊 Cache Statistics:")
            print("   Cache hit rate: \(String(format: "%.1f", cacheHitRate * 100))%")
            print("   Cached files: \(cachedFileCount)")
            print("   Analyzed files: \(analyzedFileCount)")
        }

        // Exit with error code if configured to do so
        let errors = violationsToReport.filter { $0.severity == .error }
        if failOnError && !errors.isEmpty {
            print("\n❌ Analysis failed with \(errors.count) error(s)")
            throw ExitCode.failure
        }

        if violationsToReport.isEmpty {
            print("\n✅ No violations found!")
        } else {
            let warnings = violationsToReport.filter { $0.severity == .warning }
            print("\n⚠️ Found \(violationsToReport.count) violation(s) (\(errors.count) error(s), \(warnings.count) warning(s))")
        }
    }
}