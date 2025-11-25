import ArgumentParser
import Foundation
import StrictSwiftCore

@main
struct SwiftStrict: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A static analysis tool for Swift 6+ with Rust-grade safety guarantees",
        subcommands: [
            CheckCommand.self,
            CICommand.self,
            BaselineCommand.self,
            ExplainCommand.self,
            FixCommand.self
        ],
        defaultSubcommand: CheckCommand.self
    )
}