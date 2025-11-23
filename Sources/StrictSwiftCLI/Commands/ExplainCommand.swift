import ArgumentParser
import Foundation

/// Get detailed information about a rule
struct ExplainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get detailed information about a rule"
    )

    @Argument(help: "The rule ID to explain")
    var ruleId: String

    func run() async throws {
        print("Explaining rule: \(ruleId)")
    }
}