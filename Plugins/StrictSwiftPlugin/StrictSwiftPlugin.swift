import PackagePlugin
import Foundation

/// StrictSwift build tool plugin for SwiftPM
/// This plugin runs StrictSwift analysis during the build process
@main
struct StrictSwiftPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // Only process Swift source targets
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }
        
        // Get the path to the swift-strict executable
        let strictSwiftTool = try context.tool(named: "swift-strict")
        
        // Find all Swift files in the target
        let swiftFiles = sourceTarget.sourceFiles(withSuffix: "swift").map(\.url)
        
        guard !swiftFiles.isEmpty else {
            return []
        }
        
        // Look for configuration file
        let configPath = findConfigurationFile(in: context.package.directoryURL)
        
        // Create output directory for reports
        let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("strictswift-reports")
        let reportPath = outputDir.appendingPathComponent("\(target.name)-report.json")
        
        // Build the command arguments
        var arguments: [String] = ["check"]
        
        // Add configuration file if found
        if let config = configPath {
            arguments.append("--config")
            arguments.append(config.path)
        }
        
        // Add output format
        arguments.append("--format")
        arguments.append("json")
        
        // Add output file
        arguments.append("--output")
        arguments.append(reportPath.path)
        
        // Add all Swift source files for analysis
        for file in swiftFiles {
            arguments.append(file.path)
        }
        
        // Create a prebuild command that runs analysis
        // Using prebuildCommand so it runs before compilation and can emit diagnostics
        return [
            .prebuildCommand(
                displayName: "StrictSwift: Analyzing \(target.name)",
                executable: strictSwiftTool.url,
                arguments: arguments,
                outputFilesDirectory: outputDir
            )
        ]
    }
    
    /// Find configuration file in the package directory
    private func findConfigurationFile(in directory: URL) -> URL? {
        let configNames = [
            ".strictswift.yml",
            ".strictswift.yaml",
            "strictswift.yml",
            "strictswift.yaml",
            ".strictswift/config.yml",
            ".strictswift/config.yaml"
        ]
        
        for name in configNames {
            let configURL = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: configURL.path) {
                return configURL
            }
        }
        
        return nil
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension StrictSwiftPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        // Get the path to the swift-strict executable
        let strictSwiftTool = try context.tool(named: "swift-strict")
        
        // Find Swift files in the target
        let swiftFiles = target.inputFiles.filter { $0.type == .source && $0.url.pathExtension == "swift" }
        
        guard !swiftFiles.isEmpty else {
            return []
        }
        
        // Look for configuration file
        let configPath = findConfigurationFile(in: context.xcodeProject.directoryURL)
        
        // Create output directory for reports
        let outputDir = context.pluginWorkDirectoryURL.appendingPathComponent("strictswift-reports")
        let reportPath = outputDir.appendingPathComponent("\(target.displayName)-report.json")
        
        // Build the command arguments
        var arguments: [String] = ["check"]
        
        // Add configuration file if found
        if let config = configPath {
            arguments.append("--config")
            arguments.append(config.path)
        }
        
        // Add output format
        arguments.append("--format")
        arguments.append("json")
        
        // Add output file
        arguments.append("--output")
        arguments.append(reportPath.path)
        
        // Add all Swift files
        for file in swiftFiles {
            arguments.append(file.url.path)
        }
        
        return [
            .prebuildCommand(
                displayName: "StrictSwift: Analyzing \(target.displayName)",
                executable: strictSwiftTool.url,
                arguments: arguments,
                outputFilesDirectory: outputDir
            )
        ]
    }
}
#endif
