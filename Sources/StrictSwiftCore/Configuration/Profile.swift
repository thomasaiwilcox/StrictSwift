import Foundation

/// Configuration profiles for different strictness levels
public enum Profile: String, Codable, CaseIterable, Sendable {
    case criticalCore = "critical-core"
    case serverDefault = "server-default"
    case libraryStrict = "library-strict"
    case appRelaxed = "app-relaxed"
    case rustInspired = "rust-inspired" // Beta

    /// Get the default configuration for this profile
    public var configuration: Configuration {
        switch self {
        case .criticalCore:
            return Configuration.loadCriticalCore()
        case .serverDefault:
            return Configuration.loadServerDefault()
        case .libraryStrict:
            return Configuration.loadLibraryStrict()
        case .appRelaxed:
            return Configuration.loadAppRelaxed()
        case .rustInspired:
            return Configuration.loadRustInspired()
        }
    }
}