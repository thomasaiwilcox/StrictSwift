import ArgumentParser
import Foundation
import StrictSwiftCore

/// Manage baseline files for known violations
struct BaselineCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage baseline files for known violations"
    )

    @Argument(help: "The directory or files to analyze")
    var paths: [String] = ["Sources/"]

    @Option(name: .long, help: "Configuration profile to use")
    var profile: String = "critical-core"

    @Option(name: .long, help: "Output file for baseline")
    var output: String = ".strictswift-baseline.json"

    @Option(name: .long, help: "Expiry date for baseline (YYYY-MM-DD)")
    var expires: String?

    @Option(name: .long, help: "Configuration file")
    var config: String?

    @Flag(name: .long, help: "Update existing baseline")
    var update: Bool = false

    func run() async throws {
        // Load configuration
        let profileEnum = Profile(rawValue: profile) ?? .criticalCore
        let configURL = config != nil ? URL(fileURLWithPath: config!) : nil
        let configuration = Configuration.load(from: configURL, profile: profileEnum)

        // Parse expiry date
        var expiryDate: Date?
        if let expires = expires {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            expiryDate = formatter.date(from: expires)
            if expiryDate == nil {
                print("Error: Invalid expiry date format. Use YYYY-MM-DD")
                throw ExitCode.failure
            }
        }

        // Create analyzer
        let analyzer = Analyzer(configuration: configuration)

        // Analyze files
        let violations = try await analyzer.analyze(paths: paths)

        if violations.isEmpty {
            print("✅ No violations found. No baseline needed.")
            return
        }

        // Create or update baseline
        let outputFile = URL(fileURLWithPath: output)
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        var baseline: BaselineConfiguration
        let newFingerprints = violations.map { ViolationFingerprint(violation: $0, projectRoot: projectRoot) }

        if update && FileManager.default.fileExists(atPath: output) {
            // Load existing baseline and merge with new violations
            let existingBaseline = try BaselineConfiguration.load(from: outputFile)

            // Create merged baseline:
            // - Keep existing violations that are still present (not fixed)
            // - Add new violations that weren't in the baseline before
            // - Remove violations that are fixed (not present in current analysis)
            // - Update expiry if provided
            let existingFingerprints = Set(existingBaseline.violations)
            let newFingerprintSet = Set(newFingerprints)

            // Create deterministic merged baseline using Set operations to avoid ordering issues
            let mergedFingerprintSet: Set<ViolationFingerprint> =
                Set(existingBaseline.violations).intersection(newFingerprintSet)  // Keep violations that are still failing
                .union(newFingerprintSet.subtracting(existingBaseline.violations))  // Add only genuinely new violations

            // Convert back to sorted array for deterministic JSON output
            let sortedViolations = Array(mergedFingerprintSet).sorted()

            baseline = BaselineConfiguration(
                version: existingBaseline.version,
                created: existingBaseline.created,
                expires: expiryDate ?? existingBaseline.expires,
                violations: sortedViolations
            )
        } else {
            // Create new baseline
            // Use Set then sort to ensure deterministic ordering regardless of analysis order
            let sortedViolations = Set(newFingerprints).sorted()

            baseline = BaselineConfiguration(
                created: Date(),
                expires: expiryDate,
                violations: sortedViolations
            )
        }

        // Save baseline
        try baseline.save(to: outputFile)

        print("✅ Baseline created with \(baseline.violations.count) violations")
        print("   Saved to: \(output)")
        if expiryDate != nil {
            print("   Expires: \(expires!)")
        }

        // Show summary
        let violationsByRule = Dictionary(grouping: baseline.violations) { $0.ruleId }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }

        print("\n📊 Summary:")
        for (ruleId, count) in violationsByRule.prefix(10) {
            print("   \(ruleId): \(count)")
        }
    }
}