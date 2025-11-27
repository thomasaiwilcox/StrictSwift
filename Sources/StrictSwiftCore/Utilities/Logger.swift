import Foundation

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

    /// Lock for thread-safe access to mutable state
    private static let lock = NSLock()
    
    /// Backing storage for log level (can be changed at runtime)
    /// Thread-safety is ensured via lock - marked nonisolated(unsafe) to suppress warning
    nonisolated(unsafe) private static var _minLevel: Level?
    
    /// Current minimum log level
    /// Can be set via:
    /// 1. setMinLevel() at runtime (highest priority)
    /// 2. STRICTSWIFT_LOG_LEVEL environment variable
    /// 3. Default: .warning
    public static var minLevel: Level {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let level = _minLevel { return level }
            return levelFromEnvironment()
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _minLevel = newValue
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

        let fileName = (file as NSString).lastPathComponent
        let location = includeSourceLocation ? " [\(fileName):\(line)]" : ""

        // Use FileHandle for thread-safe stderr access
        let output = "\(prefix)\(location): \(message)\n"
        if level >= .warning {
            if let data = output.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        } else {
            print("\(prefix)\(location): \(message)")
        }
    }
}
