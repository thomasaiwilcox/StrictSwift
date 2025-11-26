import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Semantic Analysis Mode

/// The semantic analysis mode for type resolution
public enum SemanticMode: String, Codable, Sendable, CaseIterable {
    /// No semantic analysis - pure syntactic analysis only (fastest)
    case off
    
    /// Hybrid mode - syntactic analysis with semantic queries for ambiguous cases
    /// Balances speed and accuracy
    case hybrid
    
    /// Full semantic mode - query SourceKit for all type information
    /// Most accurate but slowest, requires buildable project
    case full
    
    /// Auto-detect best available mode based on environment
    case auto
    
    public var displayName: String {
        switch self {
        case .off: return "Off (Syntactic Only)"
        case .hybrid: return "Hybrid"
        case .full: return "Full Semantic"
        case .auto: return "Auto"
        }
    }
    
    /// Whether this mode requires SourceKit
    public var requiresSourceKit: Bool {
        switch self {
        case .off, .auto: return false
        case .hybrid, .full: return true
        }
    }
    
    /// Whether this mode requires a built project
    public var requiresBuildArtifacts: Bool {
        switch self {
        case .off, .auto, .hybrid: return false
        case .full: return true
        }
    }
}

// MARK: - Semantic Capabilities

/// Detected capabilities for semantic analysis in the current environment
public struct SemanticCapabilities: Sendable {
    /// Whether sourcekitd is available and can be loaded
    public let sourceKitAvailable: Bool
    
    /// Path to sourcekitd if available
    public let sourceKitPath: String?
    
    /// Whether build artifacts exist (.build/ directory)
    public let buildArtifactsExist: Bool
    
    /// Whether this is a Swift package (Package.swift exists)
    public let isSwiftPackage: Bool
    
    /// Swift version if detectable
    public let swiftVersion: String?
    
    /// Any detection errors or warnings
    public let warnings: [String]
    
    public init(
        sourceKitAvailable: Bool,
        sourceKitPath: String? = nil,
        buildArtifactsExist: Bool,
        isSwiftPackage: Bool,
        swiftVersion: String? = nil,
        warnings: [String] = []
    ) {
        self.sourceKitAvailable = sourceKitAvailable
        self.sourceKitPath = sourceKitPath
        self.buildArtifactsExist = buildArtifactsExist
        self.isSwiftPackage = isSwiftPackage
        self.swiftVersion = swiftVersion
        self.warnings = warnings
    }
    
    /// The best available semantic mode based on detected capabilities
    /// 
    /// Note: We default to hybrid even when build artifacts exist because
    /// full mode queries SourceKit for every reference, which is slow.
    /// Hybrid only queries for ambiguous references, providing a good
    /// balance of accuracy vs. speed. Users can explicitly request full
    /// mode with --semantic full if they want comprehensive analysis.
    public var bestAvailableMode: SemanticMode {
        if sourceKitAvailable {
            // Default to hybrid for better performance
            // Full mode is available but slow (queries every reference)
            return .hybrid
        } else {
            return .off
        }
    }
    
    /// The maximum available mode (for capability checking)
    public var maxAvailableMode: SemanticMode {
        if sourceKitAvailable && buildArtifactsExist {
            return .full
        } else if sourceKitAvailable {
            return .hybrid
        } else {
            return .off
        }
    }
    
    /// Degrade a requested mode to what's actually available
    /// Returns the degraded mode and a reason if degradation occurred
    public func degrade(_ requested: SemanticMode) -> (mode: SemanticMode, reason: String?) {
        switch requested {
        case .off:
            return (.off, nil)
            
        case .auto:
            return (bestAvailableMode, nil)
            
        case .hybrid:
            if sourceKitAvailable {
                return (.hybrid, nil)
            } else {
                return (.off, "SourceKit not available. Install Xcode or Swift toolchain for semantic analysis.")
            }
            
        case .full:
            if !sourceKitAvailable {
                return (.off, "SourceKit not available. Install Xcode or Swift toolchain for semantic analysis.")
            } else if !buildArtifactsExist {
                return (.hybrid, "No build artifacts found. Run 'swift build' first for full semantic analysis.")
            } else {
                return (.full, nil)
            }
        }
    }
    
    /// Check if the requested mode can be satisfied without degradation
    public func canSatisfy(_ requested: SemanticMode) -> Bool {
        let (degraded, _) = degrade(requested)
        return degraded == requested || requested == .auto
    }
}

// MARK: - Capability Detection

/// Detects semantic analysis capabilities in the current environment
public struct SemanticCapabilityDetector: Sendable {
    private let projectRoot: URL
    
    public init(projectRoot: URL) {
        self.projectRoot = projectRoot
    }
    
    /// Detect all capabilities
    public func detect() -> SemanticCapabilities {
        var warnings: [String] = []
        
        // Detect SourceKit
        let (sourceKitAvailable, sourceKitPath) = detectSourceKit()
        if !sourceKitAvailable {
            warnings.append("SourceKit not found. Semantic analysis will be limited.")
        }
        
        // Detect build artifacts
        let buildArtifactsExist = detectBuildArtifacts()
        
        // Detect if this is a Swift package
        let isSwiftPackage = detectSwiftPackage()
        
        // Detect Swift version
        let swiftVersion = detectSwiftVersion()
        
        return SemanticCapabilities(
            sourceKitAvailable: sourceKitAvailable,
            sourceKitPath: sourceKitPath,
            buildArtifactsExist: buildArtifactsExist,
            isSwiftPackage: isSwiftPackage,
            swiftVersion: swiftVersion,
            warnings: warnings
        )
    }
    
    // MARK: - Private Detection Methods
    
    private func detectSourceKit() -> (available: Bool, path: String?) {
        // Use dlopen to actually verify SourceKit can be loaded.
        // This is the definitive test - if dlopen succeeds, we can use SourceKit.
        
        let searchPaths = getSourceKitSearchPaths()
        
        for path in searchPaths {
            // Try to actually open the library
            if let handle = dlopen(path, RTLD_LAZY) {
                dlclose(handle)
                return (true, path)
            }
        }
        
        return (false, nil)
    }
    
    private func getSourceKitSearchPaths() -> [String] {
        var paths: [String] = []
        
        #if os(macOS)
        // Check TOOLCHAINS environment variable first
        if let toolchain = ProcessInfo.processInfo.environment["TOOLCHAINS"] {
            paths.append("/Library/Developer/Toolchains/\(toolchain).xctoolchain/usr/lib/sourcekitd.framework/sourcekitd")
        }
        
        // Xcode default locations
        paths.append(contentsOf: [
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/sourcekitd",
            "/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/sourcekitd"
        ])
        
        // Developer directory from xcode-select
        if let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
            paths.append("\(developerDir)/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/sourcekitd")
        }
        
        #elseif os(Linux)
        // Swift toolchain on Linux
        paths.append(contentsOf: [
            "/usr/lib/libsourcekitdInProc.so",
            "/usr/local/lib/libsourcekitdInProc.so"
        ])
        
        // swiftenv paths
        let home = NSHomeDirectory()
        paths.append("\(home)/.swiftenv/versions/current/usr/lib/libsourcekitdInProc.so")
        
        // Check SWIFT_TOOLCHAIN environment variable
        if let toolchain = ProcessInfo.processInfo.environment["SWIFT_TOOLCHAIN"] {
            paths.append("\(toolchain)/usr/lib/libsourcekitdInProc.so")
        }
        #endif
        
        return paths
    }
    
    private func detectBuildArtifacts() -> Bool {
        let buildDir = projectRoot.appendingPathComponent(".build")
        var isDirectory: ObjCBool = false
        
        if FileManager.default.fileExists(atPath: buildDir.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                // Check if there's actual build output (not just empty .build)
                let debugDir = buildDir.appendingPathComponent("debug")
                let releaseDir = buildDir.appendingPathComponent("release")
                return FileManager.default.fileExists(atPath: debugDir.path) ||
                       FileManager.default.fileExists(atPath: releaseDir.path)
            }
        }
        
        return false
    }
    
    private func detectSwiftPackage() -> Bool {
        let packageSwift = projectRoot.appendingPathComponent("Package.swift")
        return FileManager.default.fileExists(atPath: packageSwift.path)
    }
    
    private func detectSwiftVersion() -> String? {
        if let output = runCommand("swift", arguments: ["--version"]) {
            // Parse "Swift version X.Y.Z" from output
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("Swift version") {
                    // Extract version number
                    let parts = line.components(separatedBy: " ")
                    if let versionIndex = parts.firstIndex(of: "version"),
                       versionIndex + 1 < parts.count {
                        return parts[versionIndex + 1]
                    }
                }
            }
        }
        return nil
    }
    
    private func runCommand(_ command: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)
            }
        } catch {
            // Silently fail - command not available
        }
        
        return nil
    }
}

// MARK: - Semantic Resolution Result

/// Result of semantic mode resolution with degradation info
public struct SemanticModeResolution: Sendable {
    /// The resolved semantic mode to use
    public let mode: SemanticMode
    
    /// The originally requested mode (before degradation)
    public let requestedMode: SemanticMode
    
    /// Whether the mode was degraded from what was requested
    public var wasDegraded: Bool {
        return mode != requestedMode && requestedMode != .auto
    }
    
    /// Reason for degradation, if any
    public let degradationReason: String?
    
    /// Source of the configuration (CLI, env, config file, etc.)
    public let source: ConfigurationSource
    
    /// The detected capabilities
    public let capabilities: SemanticCapabilities
    
    public init(
        mode: SemanticMode,
        requestedMode: SemanticMode,
        degradationReason: String? = nil,
        source: ConfigurationSource,
        capabilities: SemanticCapabilities
    ) {
        self.mode = mode
        self.requestedMode = requestedMode
        self.degradationReason = degradationReason
        self.source = source
        self.capabilities = capabilities
    }
}

/// Source of a configuration value
public enum ConfigurationSource: String, Sendable {
    case cli = "CLI flag"
    case environment = "Environment variable"
    case vscodeSettings = "VS Code settings"
    case yamlConfig = "YAML configuration"
    case ruleOverride = "Rule-specific override"
    case autoDetected = "Auto-detected"
}
