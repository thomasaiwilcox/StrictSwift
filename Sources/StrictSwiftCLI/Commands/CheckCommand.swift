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

    @Option(name: .long, help: "Output format (human|json|agent|sarif|xcode)")
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
    
    // Git-aware incremental analysis
    @Flag(name: .long, help: "Only analyze files changed in git (relative to --base)")
    var onlyChanged: Bool = false
    
    @Option(name: .long, help: "Base git ref for --only-changed (default: origin/main)")
    var base: String = "origin/main"

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
        
        // Filter to only changed files if requested
        // Track any analysis warnings for structured output
        var analysisWarnings: [String] = []
        var effectivePaths = paths
        if onlyChanged {
            switch try getChangedSwiftFiles(base: base) {
            case .success(let changedFiles):
                if changedFiles.isEmpty {
                    // No changed files - output valid empty result in requested format
                    let emptyViolations: [Violation] = []
                    let emptyReport: String
                    switch format.lowercased() {
                    case "json":
                        emptyReport = try JSONReporter().generateReport(emptyViolations)
                    case "agent":
                        let options = AgentReporterOptions(contextLines: contextLines, includeFixes: true, minSeverity: nil)
                        emptyReport = try AgentReporter(options: options).generateReport(emptyViolations)
                    case "sarif":
                        emptyReport = try SARIFReporter().generateReport(emptyViolations)
                    case "xcode":
                        // Xcode format: output a newline so the build system knows the tool completed
                        // Empty stdout can cause "Broken pipe" errors
                        emptyReport = "\n"
                    default:
                        print("✅ No Swift files changed since \(base)")
                        return
                    }
                    print(emptyReport, terminator: "")
                    return
                }
                effectivePaths = changedFiles
                if format.lowercased() == "human" {
                    print("📝 Analyzing \(changedFiles.count) changed file(s) since \(base)")
                }
            case .failure(let error):
                // Git diff failed - fall back to analyzing all requested paths
                let warningMessage = "--only-changed ignored: \(error). Analyzing all paths."
                // Always print warning to stderr so it's visible in CI logs regardless of output format
                FileHandle.standardError.write("warning: \(warningMessage)\n".data(using: .utf8)!)
                // Track warning for structured output (JSON/SARIF/agent formats)
                analysisWarnings.append(warningMessage)
                // effectivePaths remains unchanged (all requested paths)
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
            let result = try await runner.analyze(paths: effectivePaths)
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
                let result = try await analyzer.analyzeIncremental(paths: effectivePaths)
                violations = result.violations
                cacheHitRate = result.cacheHitRate
                cachedFileCount = result.cachedFileCount
                analyzedFileCount = result.analyzedFileCount
            } else {
                violations = try await analyzer.analyze(paths: effectivePaths)
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
        case "sarif":
            reporter = SARIFReporter()
        case "xcode":
            reporter = XcodeReporter()
        default:
            reporter = HumanReporter()
        }

        // Filter baseline violations for display (unless show-baseline flag is set)
        var violationsToReport = violations
        
        // Apply severity filter for non-agent formats (agent format handles internally)
        if format.lowercased() != "agent", let minSev = severityFilter {
            violationsToReport = violations.filter { severityRank($0.severity) >= severityRank(minSev) }
        }

        // Generate report - pass analysis warnings to formats that support it
        let report: String
        switch format.lowercased() {
        case "json":
            report = try JSONReporter().generateReport(violationsToReport, metadata: nil, analysisWarnings: analysisWarnings)
        case "sarif":
            report = try SARIFReporter().generateReport(violationsToReport, metadata: nil, analysisWarnings: analysisWarnings)
        default:
            report = try reporter.generateReport(violationsToReport)
        }
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
    
    /// Error type for git operations
    enum GitError: Error, CustomStringConvertible {
        case notAGitRepository
        case baseRefNotFound(String)
        case commandFailed(Int32, String)
        
        var description: String {
            switch self {
            case .notAGitRepository:
                return "not a git repository"
            case .baseRefNotFound(let ref):
                return "base ref '\(ref)' not found - try 'git fetch origin \(ref)'"
            case .commandFailed(let code, let message):
                return "git failed with exit code \(code): \(message)"
            }
        }
    }
    
    /// Result type for git operations that can fail gracefully
    enum GitResult<T> {
        case success(T)
        case failure(GitError)
    }
    
    /// Get Swift files that have changed since the base git ref
    private func getChangedSwiftFiles(base: String) throws -> GitResult<[String]> {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--name-only", "--diff-filter=ACMR", base]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""
            
            // Provide specific error messages for common failure cases
            if stderrOutput.contains("not a git repository") {
                return .failure(.notAGitRepository)
            } else if stderrOutput.contains("unknown revision") || stderrOutput.contains("bad revision") {
                return .failure(.baseRefNotFound(base))
            } else {
                return .failure(.commandFailed(process.terminationStatus, stderrOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return .success([])
        }
        
        let files = output
            .split(separator: "\n")
            .map { String($0) }
            .filter { $0.hasSuffix(".swift") }
        
        return .success(files)
    }
}