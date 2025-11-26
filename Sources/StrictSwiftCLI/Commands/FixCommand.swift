import ArgumentParser
import Foundation
import StrictSwiftCore

/// Apply automatic fixes to Swift source files
struct FixCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fix",
        abstract: "Apply automatic fixes to Swift source files"
    )

    @Argument(help: "The directory or files to fix")
    var paths: [String] = ["Sources/"]

    @Option(name: .long, help: "Configuration profile to use")
    var profile: String = "critical-core"

    @Option(name: .long, help: "Path to configuration file")
    var config: String?

    @Option(name: .long, help: "Only fix specific rules (comma-separated)")
    var rules: String?
    
    @Option(name: .long, help: "Minimum confidence level (safe, suggested, experimental)")
    var confidence: String = "suggested"

    @Flag(name: .long, help: "Preview fixes without applying them")
    var dryRun: Bool = false
    
    @Flag(name: .long, help: "Show diff of changes")
    var diff: Bool = false
    
    @Flag(name: .long, help: "Only apply safe fixes (equivalent to --confidence safe)")
    var safeOnly: Bool = false
    
    @Flag(name: .long, help: "Apply fixes without confirmation")
    var yes: Bool = false
    
    @Flag(name: .long, help: "Output in agent-friendly JSON format with structured diff")
    var agent: Bool = false

    func run() async throws {
        // Load configuration
        let profileEnum = Profile(rawValue: profile) ?? .criticalCore
        let configURL = config.map { URL(fileURLWithPath: $0) }
        let configuration = Configuration.load(from: configURL, profile: profileEnum)

        // Create analyzer
        let analyzer = Analyzer(configuration: configuration)

        // Analyze files to find violations (silent in agent mode)
        if !agent {
            print("🔍 Analyzing files for fixable violations...")
        }
        let violations = try await analyzer.analyze(paths: paths)
        
        // Filter to only violations with structured fixes
        var fixableViolations = violations.filter { $0.hasAutoFix }
        
        // Filter by specific rules if requested
        if let rulesFilter = rules {
            let allowedRules = Set(rulesFilter.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
            fixableViolations = fixableViolations.filter { allowedRules.contains($0.ruleId) }
        }
        
        if fixableViolations.isEmpty {
            if agent {
                // Output empty agent result
                let reporter = AgentFixReporter()
                let report = try reporter.generateReport([])
                print(report)
            } else {
                print("✅ No fixable violations found!")
            }
            return
        }
        
        // Determine confidence level
        let minConfidence: FixConfidence
        if safeOnly {
            minConfidence = .safe
        } else {
            switch confidence.lowercased() {
            case "safe": minConfidence = .safe
            case "suggested": minConfidence = .suggested
            case "experimental": minConfidence = .experimental
            default: minConfidence = .suggested
            }
        }
        
        // Group violations by file
        var violationsByFile: [URL: [Violation]] = [:]
        for violation in fixableViolations {
            let fileURL = violation.location.file
            violationsByFile[fileURL, default: []].append(violation)
        }
        
        // Count available fixes
        let totalFixes = fixableViolations.reduce(0) { count, violation in
            count + violation.structuredFixes.filter { $0.confidence >= minConfidence }.count
        }
        
        if !agent {
            print("📝 Found \(totalFixes) fixable issue(s) across \(violationsByFile.count) file(s)")
            print("   Confidence level: \(minConfidence.rawValue)")
        }
        
        if totalFixes == 0 {
            if agent {
                let reporter = AgentFixReporter()
                let report = try reporter.generateReport([])
                print(report)
            } else {
                print("✅ No fixes match the confidence level!")
            }
            return
        }
        
        // Show summary of fixes (human mode only)
        if !agent {
            print("\nFixes to apply:")
            for (file, fileViolations) in violationsByFile.sorted(by: { $0.key.path < $1.key.path }) {
                let fixes = fileViolations.flatMap { $0.structuredFixes.filter { $0.confidence >= minConfidence } }
                if !fixes.isEmpty {
                    print("  📄 \(file.lastPathComponent): \(fixes.count) fix(es)")
                    for fix in fixes.prefix(5) {
                        print("     • \(fix.title) [\(fix.kind.rawValue)]")
                    }
                    if fixes.count > 5 {
                        print("     ... and \(fixes.count - 5) more")
                    }
                }
            }
        }
        
        // Confirm unless --yes, --dry-run, or --agent
        if !dryRun && !yes && !agent {
            print("\n⚠️  This will modify \(violationsByFile.count) file(s).")
            print("   Run with --dry-run to preview changes, or --yes to skip confirmation.")
            print("   Continue? (y/n): ", terminator: "")
            
            guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                print("❌ Aborted")
                return
            }
        }
        
        // Create fix applier
        let options = FixApplier.Options(
            minimumConfidence: minConfidence,
            validateSyntax: false,
            formatAfterFix: false
        )
        let applier = FixApplier(options: options)
        
        // Apply fixes
        var allResults: [FixApplicationResult] = []
        
        for (fileURL, fileViolations) in violationsByFile {
            let result = try await applier.applyFixes(from: fileViolations, to: fileURL)
            allResults.append(result)
            
            if result.hasChanges && !agent {
                if diff || dryRun {
                    print("\n--- \(fileURL.lastPathComponent) ---")
                    print(result.generateDiff())
                }
            }
        }
        
        // Write changes unless dry run
        if !dryRun {
            try await applier.writeResults(allResults)
        }
        
        // Output results
        if agent {
            // Agent mode: JSON output
            let reporter = AgentFixReporter()
            let report = try reporter.generateReport(allResults)
            print(report)
        } else {
            // Human mode: summary
            let summary = FixSummary(results: allResults)
            print("\n" + String(repeating: "─", count: 50))
            if dryRun {
                print("🔍 Dry run complete (no files modified)")
            } else {
                print("✅ Fix complete!")
            }
            print("   Files modified: \(summary.modifiedFiles)/\(summary.totalFiles)")
            print("   Fixes applied: \(summary.totalApplied)")
            if summary.totalSkipped > 0 {
                print("   Fixes skipped: \(summary.totalSkipped)")
            }
        }
    }
}
