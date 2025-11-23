import ArgumentParser
import Foundation
import StrictSwiftCore

/// Run analysis in CI mode with deterministic output
struct CICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run analysis in CI mode with deterministic output"
    )

    @Argument(help: "The directory or files to analyze")
    var paths: [String] = ["Sources/"]

    @Option(name: .long, help: "Output format (json|json-detailed)")
    var format: String = "json"

    @Option(name: .long, help: "Fail build on errors")
    var failOnError: Bool = true

    @Option(name: .long, help: "Configuration profile to use")
    var profile: String = "critical-core"

    @Option(name: .long, help: "Path to configuration file")
    var config: String?

    @Option(name: .long, help: "Path to baseline file")
    var baseline: String?

    func run() async throws {
        // Load configuration
        let profileEnum = Profile(rawValue: profile) ?? .criticalCore
        let configURL = config != nil ? URL(fileURLWithPath: config!) : nil
        let baselineURL = baseline != nil ? URL(fileURLWithPath: baseline!) : nil

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

        // Use JSON reporter for CI (deterministic output)
        // Honor the format flag: json for compact output, json-detailed for pretty-printed
        let usePrettyPrint = (format == "json-detailed")
        let reporter: Reporter = JSONReporter(pretty: usePrettyPrint)

        // Output results
        let report = try reporter.generateReport(violations)
        print(report, terminator: "")

        // Exit with error code if configured to do so
        let errors = violations.filter { $0.severity == .error }
        if failOnError && !errors.isEmpty {
            throw ExitCode.failure
        }
    }
}