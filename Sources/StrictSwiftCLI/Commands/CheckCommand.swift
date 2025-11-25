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
            maxJobs: finalConfiguration.maxJobs
        )

        // Create analyzer
        let analyzer = Analyzer(configuration: configurationWithBaseline)

        // Analyze files
        let violations = try await analyzer.analyze(paths: paths)

        // Output results
        let reporter: Reporter = format == "json" ? JSONReporter() : HumanReporter()

        // Filter baseline violations for display (unless show-baseline flag is set)
        let violationsToReport = violations

        let report = try reporter.generateReport(violationsToReport)
        print(report, terminator: "")

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