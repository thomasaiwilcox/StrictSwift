import ArgumentParser
import StrictSwiftCore

@main
struct SwiftStrict: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A static analysis tool for Swift 6+ with Rust-grade safety guarantees",
        subcommands: [
            CheckCommand.self,
            CICommand.self,
            BaselineCommand.self,
            ExplainCommand.self
        ],
        defaultSubcommand: CheckCommand.self
    )
}