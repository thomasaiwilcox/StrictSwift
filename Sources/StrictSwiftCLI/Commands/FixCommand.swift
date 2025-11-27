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
    
    @Flag(name: .long, help: "Undo the last fix operation (restore from backup)")
    var undo: Bool = false
    
    @Flag(name: .long, help: "Skip creating backup before applying fixes (not recommended)")
    var noBackup: Bool = false
    
    // Semantic analysis options
    @Option(name: .long, help: "Semantic analysis mode (off|hybrid|full|auto). Default: auto")
    var semantic: String?
    
    @Flag(name: .long, help: "Fail if requested semantic mode is unavailable")
    var semanticStrict: Bool = false
    
    /// Default backup directory
    private static let backupDirName = ".strictswift-backup"

    func run() async throws {
        // Handle undo mode
        if undo {
            try await performUndo()
            return
        }
        
        // Load configuration
        let profileEnum = Profile(rawValue: profile) ?? .criticalCore
        let configURL = config.map { URL(fileURLWithPath: $0) }
        let loadedConfiguration = Configuration.load(from: configURL, profile: profileEnum)
        
        // Parse semantic mode from CLI
        let cliSemanticMode: SemanticMode? = semantic.flatMap { SemanticMode(rawValue: $0.lowercased()) }
        
        // Create configuration with semantic settings
        let configuration = Configuration(
            profile: loadedConfiguration.profile,
            rules: loadedConfiguration.rules,
            baseline: loadedConfiguration.baseline,
            include: loadedConfiguration.include,
            exclude: loadedConfiguration.exclude,
            maxJobs: loadedConfiguration.maxJobs,
            advanced: loadedConfiguration.advanced,
            useEnhancedRules: loadedConfiguration.useEnhancedRules,
            semanticMode: cliSemanticMode ?? loadedConfiguration.semanticMode,
            semanticStrict: semanticStrict ? true : loadedConfiguration.semanticStrict,
            perRuleSemanticModes: loadedConfiguration.perRuleSemanticModes,
            perRuleSemanticStrict: loadedConfiguration.perRuleSemanticStrict
        )

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
            // Create backup before applying fixes (unless disabled)
            if !noBackup {
                try await createBackup(for: allResults)
                if !agent {
                    print("💾 Backup created in \(Self.backupDirName)/ (use --undo to restore)")
                }
            }
            
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
            if !noBackup && !dryRun {
                print("   💡 Run 'swift-strict fix --undo' to restore original files")
            }
        }
    }
    
    // MARK: - Backup & Undo
    
    /// Get the backup directory URL
    private func getBackupDir() -> URL {
        // Find workspace root (look for Package.swift, .git, etc.)
        let currentDir = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: currentDir).appendingPathComponent(Self.backupDirName)
    }
    
    /// Create backup of files before modifying them
    private func createBackup(for results: [FixApplicationResult]) async throws {
        let backupDir = getBackupDir()
        let fm = FileManager.default
        
        // Remove old backup if it exists
        if fm.fileExists(atPath: backupDir.path) {
            try fm.removeItem(at: backupDir)
        }
        
        // Create fresh backup directory
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        // Create manifest file with metadata
        var manifest = BackupManifest(
            timestamp: Date(),
            files: []
        )
        
        // Backup each modified file
        for result in results where result.hasChanges {
            let originalFile = result.file
            
            // Create relative path structure in backup
            let relativePath = originalFile.path.replacingOccurrences(
                of: FileManager.default.currentDirectoryPath + "/",
                with: ""
            )
            
            let backupFile = backupDir
                .appendingPathComponent("files")
                .appendingPathComponent(relativePath)
            
            // Create parent directories
            try fm.createDirectory(
                at: backupFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            // Write original content to backup
            try result.originalContent.write(to: backupFile, atomically: true, encoding: .utf8)
            
            manifest.files.append(BackupFileEntry(
                originalPath: originalFile.path,
                backupPath: backupFile.path,
                relativePath: relativePath
            ))
        }
        
        // Write manifest
        let manifestFile = backupDir.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestFile)
    }
    
    /// Restore files from backup
    private func performUndo() async throws {
        let backupDir = getBackupDir()
        let fm = FileManager.default
        
        // Check if backup exists
        guard fm.fileExists(atPath: backupDir.path) else {
            print("❌ No backup found. Run 'swift-strict fix' first to create a backup.")
            return
        }
        
        // Read manifest
        let manifestFile = backupDir.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestFile.path) else {
            print("❌ Backup manifest not found. Backup may be corrupted.")
            return
        }
        
        let manifestData = try Data(contentsOf: manifestFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(BackupManifest.self, from: manifestData)
        
        // Show what will be restored
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        print("📦 Found backup from \(formatter.string(from: manifest.timestamp))")
        print("   Files to restore: \(manifest.files.count)")
        
        for entry in manifest.files {
            print("   • \(entry.relativePath)")
        }
        
        // Confirm unless --yes
        if !yes {
            print("\n⚠️  This will overwrite \(manifest.files.count) file(s) with backup versions.")
            print("   Continue? (y/n): ", terminator: "")
            
            guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                print("❌ Aborted")
                return
            }
        }
        
        // Restore files
        var restoredCount = 0
        var failedCount = 0
        
        for entry in manifest.files {
            do {
                let backupContent = try String(contentsOfFile: entry.backupPath, encoding: .utf8)
                let originalURL = URL(fileURLWithPath: entry.originalPath)
                try backupContent.write(to: originalURL, atomically: true, encoding: .utf8)
                restoredCount += 1
            } catch {
                print("   ⚠️ Failed to restore \(entry.relativePath): \(error.localizedDescription)")
                failedCount += 1
            }
        }
        
        // Clean up backup after successful restore
        if failedCount == 0 {
            try? fm.removeItem(at: backupDir)
        }
        
        print("\n" + String(repeating: "─", count: 50))
        print("✅ Undo complete!")
        print("   Files restored: \(restoredCount)")
        if failedCount > 0 {
            print("   Failed: \(failedCount)")
            print("   ⚠️ Backup preserved due to failures")
        } else {
            print("   Backup removed")
        }
    }
}

// MARK: - Backup Types

/// Manifest for backup metadata
private struct BackupManifest: Codable {
    let timestamp: Date
    var files: [BackupFileEntry]
}

/// Entry for a backed-up file
private struct BackupFileEntry: Codable {
    let originalPath: String
    let backupPath: String
    let relativePath: String
}
