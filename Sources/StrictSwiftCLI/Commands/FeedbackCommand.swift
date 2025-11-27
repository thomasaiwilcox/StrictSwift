import ArgumentParser
import Foundation
import StrictSwiftCore

/// Record feedback on violations to improve future analysis
struct FeedbackCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "feedback",
        abstract: "Record feedback on violations to improve future analysis",
        discussion: """
        Use this command to record whether a violation was useful or not.
        This feedback is used to improve the accuracy of future analyses
        by learning from agent and user corrections.
        
        Examples:
          swift-strict feedback abc123 used
          swift-strict feedback abc123 unused --note "false positive - intentional design"
          swift-strict feedback --stats
        """
    )
    
    @Argument(help: "The violation ID to provide feedback on")
    var violationId: String?
    
    @Argument(help: "Feedback type: used, unused, fix-applied, or fix-rejected")
    var feedbackType: String?
    
    @Option(name: .long, help: "Optional note explaining the feedback")
    var note: String?
    
    @Option(name: .long, help: "Source of the feedback (user, agent, ci)")
    var source: String = "user"
    
    @Flag(name: .long, help: "Show feedback statistics")
    var stats: Bool = false
    
    @Flag(name: .long, help: "List recent feedback entries")
    var list: Bool = false
    
    @Option(name: .long, help: "Number of entries to show when listing")
    var limit: Int = 20
    
    @Option(name: .long, help: "Filter by rule ID")
    var rule: String?
    
    @Flag(name: .long, help: "Clear all feedback data")
    var clear: Bool = false
    
    @Option(name: .long, help: "Prune feedback older than N days")
    var pruneOlderThan: Int?
    
    func run() async throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let corrections = LearnedCorrections(projectRoot: projectRoot)
        
        // Load existing corrections
        try await corrections.load()
        
        // Handle different modes
        if clear {
            try await handleClear(corrections)
            return
        }
        
        if let days = pruneOlderThan {
            try await handlePrune(corrections, olderThan: days)
            return
        }
        
        if stats {
            await handleStats(corrections)
            return
        }
        
        if list {
            await handleList(corrections)
            return
        }
        
        // Record feedback mode - requires violationId and feedbackType
        guard let violationId = violationId else {
            print("❌ Error: violation ID required. Use --help for usage.")
            throw ExitCode.failure
        }
        
        guard let feedbackTypeStr = feedbackType else {
            print("❌ Error: feedback type required (used, unused, fix-applied, fix-rejected)")
            throw ExitCode.failure
        }
        
        guard let feedback = parseFeedbackType(feedbackTypeStr) else {
            print("❌ Error: Invalid feedback type '\(feedbackTypeStr)'")
            print("   Valid types: used, unused, fix-applied, fix-rejected")
            throw ExitCode.failure
        }
        
        try await recordFeedback(
            corrections: corrections,
            violationId: violationId,
            feedback: feedback
        )
    }
    
    // MARK: - Handlers
    
    private func handleClear(_ corrections: LearnedCorrections) async throws {
        print("⚠️  This will clear all feedback data.")
        print("   Continue? (y/n): ", terminator: "")
        
        guard let response = readLine()?.lowercased(), 
              response == "y" || response == "yes" else {
            print("❌ Aborted")
            return
        }
        
        await corrections.clear()
        try await corrections.save()
        print("✅ All feedback data cleared")
    }
    
    private func handlePrune(_ corrections: LearnedCorrections, olderThan days: Int) async throws {
        let summaryBefore = await corrections.summary()
        await corrections.pruneOldCorrections(olderThan: days)
        try await corrections.save()
        let summaryAfter = await corrections.summary()
        
        let removed = summaryBefore.totalCorrections - summaryAfter.totalCorrections
        print("✅ Pruned \(removed) feedback entries older than \(days) days")
        print("   Remaining: \(summaryAfter.totalCorrections) entries")
    }
    
    private func handleStats(_ corrections: LearnedCorrections) async {
        let summary = await corrections.summary()
        let ruleStats = await corrections.ruleStatistics()
        
        print("📊 Feedback Statistics")
        print(String(repeating: "─", count: 50))
        print("Total feedback entries: \(summary.totalCorrections)")
        print("")
        print("Feedback breakdown:")
        print("  ✅ Used (true positives):      \(summary.usedCount)")
        print("  ❌ Unused (false positives):   \(summary.unusedCount)")
        print("  🔧 Fix applied:                \(summary.fixAppliedCount)")
        print("  ↩️  Fix rejected:               \(summary.fixRejectedCount)")
        print("")
        print("Overall accuracy: \(String(format: "%.1f%%", summary.overallAccuracy * 100))")
        print("Rules with feedback: \(summary.rulesWithFeedback)")
        
        if !ruleStats.isEmpty {
            print("")
            print("Per-rule statistics:")
            print(String(repeating: "─", count: 50))
            
            // Sort by total feedback descending
            let sorted = ruleStats.sorted { $0.value.totalFeedback > $1.value.totalFeedback }
            
            for (ruleId, stats) in sorted.prefix(10) {
                let accuracy = String(format: "%.0f%%", stats.accuracy * 100)
                let adjustment = String(format: "%.2f", stats.confidenceAdjustment)
                print("  \(ruleId):")
                print("    Feedback: \(stats.totalFeedback) (+\(stats.positiveCount) / -\(stats.negativeCount))")
                print("    Accuracy: \(accuracy), Confidence: \(adjustment)")
            }
            
            if ruleStats.count > 10 {
                print("  ... and \(ruleStats.count - 10) more rules")
            }
        }
    }
    
    private func handleList(_ corrections: LearnedCorrections) async {
        var entries = await corrections.allCorrections()
        
        // Filter by rule if specified
        if let ruleFilter = rule {
            entries = entries.filter { $0.ruleId == ruleFilter }
        }
        
        // Sort by timestamp descending (most recent first)
        entries.sort { $0.timestamp > $1.timestamp }
        
        // Limit results
        let limited = Array(entries.prefix(limit))
        
        if limited.isEmpty {
            print("No feedback entries found")
            if rule != nil {
                print("(filtered by rule: \(rule!))")
            }
            return
        }
        
        print("📝 Recent Feedback Entries")
        if let ruleFilter = rule {
            print("   (filtered by rule: \(ruleFilter))")
        }
        print(String(repeating: "─", count: 60))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        for entry in limited {
            let icon = feedbackIcon(entry.feedback)
            let date = dateFormatter.string(from: entry.timestamp)
            let fileName = URL(fileURLWithPath: entry.filePath).lastPathComponent
            
            print("\(icon) \(entry.violationId.prefix(8))... | \(entry.ruleId)")
            print("   📄 \(fileName):\(entry.line) | \(date) | \(entry.source)")
            if let note = entry.note {
                print("   💬 \(note)")
            }
            print("")
        }
        
        if entries.count > limit {
            print("... and \(entries.count - limit) more entries (use --limit to see more)")
        }
    }
    
    private func recordFeedback(
        corrections: LearnedCorrections,
        violationId: String,
        feedback: LearnedCorrections.FeedbackType
    ) async throws {
        // Look up violation from cache to get full context
        let cached = await ViolationCache.shared.lookup(violationId)
        
        let ruleId: String
        let filePath: String
        let line: Int
        
        if let cached = cached {
            ruleId = cached.ruleId
            filePath = cached.filePath
            line = cached.line
        } else {
            // Warn user but still record with placeholder values
            print("⚠️  Violation not found in cache. Run 'swift-strict check' first.")
            print("   Recording with limited context...")
            ruleId = "unknown"
            filePath = "unknown"
            line = 0
        }
        
        let entry = await corrections.recordFeedback(
            violationId: violationId,
            ruleId: ruleId,
            filePath: filePath,
            line: line,
            feedback: feedback,
            note: note,
            source: source,
            contextHash: nil
        )
        
        try await corrections.save()
        
        let icon = feedbackIcon(feedback)
        print("\(icon) Recorded feedback: \(feedbackDescription(feedback))")
        print("   Violation: \(violationId)")
        if cached != nil {
            print("   Rule: \(ruleId)")
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            print("   Location: \(fileName):\(line)")
        }
        if let note = note {
            print("   Note: \(note)")
        }
        print("   Entry ID: \(entry.id)")
    }
    
    // MARK: - Helpers
    
    private func parseFeedbackType(_ str: String) -> LearnedCorrections.FeedbackType? {
        switch str.lowercased() {
        case "used", "true-positive", "tp":
            return .used
        case "unused", "false-positive", "fp":
            return .unused
        case "fix-applied", "fixed", "applied":
            return .fixApplied
        case "fix-rejected", "rejected":
            return .fixRejected
        default:
            return nil
        }
    }
    
    private func feedbackIcon(_ feedback: LearnedCorrections.FeedbackType) -> String {
        switch feedback {
        case .used: return "✅"
        case .unused: return "❌"
        case .fixApplied: return "🔧"
        case .fixRejected: return "↩️"
        }
    }
    
    private func feedbackDescription(_ feedback: LearnedCorrections.FeedbackType) -> String {
        switch feedback {
        case .used: return "used (true positive)"
        case .unused: return "unused (false positive)"
        case .fixApplied: return "fix applied"
        case .fixRejected: return "fix rejected"
        }
    }
}
