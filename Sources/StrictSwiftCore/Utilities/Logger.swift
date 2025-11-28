import Foundation
#if canImport(os)
import os
#endif

// strictswift:ignore-file circular_dependency_graph -- LoggerState↔StrictSwiftLogger is intentional encapsulation

/// Thread-safe storage for log level using os_unfair_lock (or NSLock on Linux)
/// SAFETY: @unchecked Sendable is safe because all mutable state (_minLevel) is
/// protected by the lock, ensuring thread-safe access from any context.
private final class LoggerState: @unchecked Sendable {
    #if canImport(os)
    /// Using os_unfair_lock for efficient thread synchronization
    private var lock = os_unfair_lock()
    #else
    /// Using NSLock for Linux compatibility
    private let lock = NSLock()
    #endif
    
    /// Backing storage for log level (can be changed at runtime)
    private var _minLevel: StrictSwiftLogger.Level?
    
    /// The shared instance - this is immutable after initialization
    static let shared = LoggerState()
    
    private init() {}
    
    /// Get or set the current minimum level
    var minLevel: StrictSwiftLogger.Level? {
        get {
            #if canImport(os)
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            #else
            lock.lock()
            defer { lock.unlock() }
            #endif
            return _minLevel
        }
        set {
            #if canImport(os)
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            #else
            lock.lock()
            defer { lock.unlock() }
            #endif
            _minLevel = newValue
        }
    }
}

/// Simple logging utility for StrictSwift
public enum StrictSwiftLogger: Sendable {
    /// Log levels
    public enum Level: Int, Comparable, Sendable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    /// Current minimum log level
    /// Can be set via:
    /// 1. setMinLevel() at runtime (highest priority)
    /// 2. STRICTSWIFT_LOG_LEVEL environment variable
    /// 3. Default: .warning
    // strictswift:ignore global_state -- Intentional: logger level must be globally accessible
    public static var minLevel: Level {
        get {
            if let level = LoggerState.shared.minLevel { return level }
            return levelFromEnvironment()
        }
        set {
            LoggerState.shared.minLevel = newValue
        }
    }
    
    /// Set minimum log level programmatically
    public static func setMinLevel(_ level: Level) {
        minLevel = level
    }
    
    /// Enable verbose/debug logging
    public static func enableVerbose() {
        minLevel = .debug
    }
    
    private static func levelFromEnvironment() -> Level {
        if let envLevel = ProcessInfo.processInfo.environment["STRICTSWIFT_LOG_LEVEL"]?.lowercased() {
            switch envLevel {
            case "debug": return .debug
            case "info": return .info
            case "warning": return .warning
            case "error": return .error
            default: return .warning
            }
        }
        return .warning
    }

    /// Whether to include file/line information in logs
    public static let includeSourceLocation: Bool = true

    /// Log a debug message
    public static func debug(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        log(level: .debug, message: message(), file: file, line: line)
    }

    /// Log an info message
    public static func info(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        log(level: .info, message: message(), file: file, line: line)
    }

    /// Log a warning message
    public static func warning(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        log(level: .warning, message: message(), file: file, line: line)
    }

    /// Log an error message
    public static func error(_ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
        log(level: .error, message: message(), file: file, line: line)
    }

    private static func log(level: Level, message: String, file: String, line: Int) {
        guard level >= minLevel else { return }

        let prefix: String
        switch level {
        case .debug: prefix = "🔍 DEBUG"
        case .info: prefix = "ℹ️ INFO"
        case .warning: prefix = "⚠️ WARNING"
        case .error: prefix = "❌ ERROR"
        }

        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let location = includeSourceLocation ? " [\(fileName):\(line)]" : ""

        // Use FileHandle for thread-safe stderr access for all log levels
        let output = "\(prefix)\(location): \(message)\n"
        if let data = output.data(using: .utf8) {
            // Debug/info go to stdout, warnings/errors go to stderr
            let handle = level >= .warning ? FileHandle.standardError : FileHandle.standardOutput
            handle.write(data)
        }
    }
}
