import Foundation

/// Configuration profiles for different strictness levels
public enum Profile: String, Codable, CaseIterable, Sendable {
    case criticalCore = "critical-core"
    case serverDefault = "server-default"
    case libraryStrict = "library-strict"
    case appRelaxed = "app-relaxed"
    case rustEquivalent = "rust-equivalent" // Beta

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
        case .rustEquivalent:
            return Configuration.loadRustEquivalent()
        }
    }
}