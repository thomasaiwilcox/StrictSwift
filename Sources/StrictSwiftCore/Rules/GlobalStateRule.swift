import Foundation
import SwiftSyntax

/// Detects use of global mutable state
public final class GlobalStateRule: Rule {
    public var id: String { "global_state" }
    public var name: String { "Global State" }
    public var description: String { "Detects use of global mutable state" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    // Patterns that indicate global mutable state
    private let globalStatePatterns: Set<String> = [
        // Global variables and properties
        "var ",
        "static var ",
        "class var ",

        // Singletons that often contain global state
        "UserDefaults.standard",
        "UserDefaults.shared",
        "UIApplication.shared",
        "HTTPCookieStorage.shared",
        "FileManager.default",
        "NotificationCenter.default",
        "URLCache.shared",
        "URLSession.shared",

        // Global collections
        "global ",
        "sharedInstance",
        ".shared",
        ".default",
        ".main"
    ]

    // Allowed patterns (false positives)
    private let allowedPatterns: Set<String> = [
        "static let ",  // Constants are fine
        "private static var ",  // Private static vars in single-file modules
        "fileprivate static var ",  // File-private static vars
        "guard let ",  // Guard statements
        "if let ",  // Optional binding
        "for ",  // For loops with 'var'
        "func ",  // Function parameters with 'var'
    ]

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let source = sourceFile.source()

        let lines = source.components(separatedBy: .newlines)

        for (lineNumber, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip comments and empty lines
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("//") || trimmedLine.hasPrefix("/*") {
                continue
            }

            // Check for global state patterns
            if containsGlobalStatePattern(trimmedLine) {
                let location = Location(
                    file: sourceFile.url,
                    line: lineNumber + 1,
                    column: 1
                )

                let violation = ViolationBuilder(
                    ruleId: "global_state",
                    category: .architecture,
                    location: location
                )
                .message("Use of global mutable state detected: '\(trimmedLine.prefix(50))...'")
                .suggestFix("Consider using dependency injection or encapsulating state in instances")
                .severity(.warning)
                .build()

                violations.append(violation)
            }
        }

        return violations
    }

    private func containsGlobalStatePattern(_ line: String) -> Bool {
        // First check if it's an allowed pattern
        for allowedPattern in allowedPatterns {
            if line.contains(allowedPattern) {
                return false
            }
        }

        // Then check for global state patterns
        for pattern in globalStatePatterns {
            if line.contains(pattern) {
                // Additional verification to avoid false positives
                if isRealGlobalStateUsage(line, pattern: pattern) {
                    return true
                }
            }
        }

        return false
    }

    private func isRealGlobalStateUsage(_ line: String, pattern: String) -> Bool {
        // More specific checks for different patterns

        switch pattern {
        case "var ":
            // Check if it's a global variable (not inside a class/function)
            return isGlobalVariable(line)

        case "static var ", "class var ":
            // Check if it's a non-private static/class variable
            return isPublicStaticVariable(line)

        case ".shared", ".default", ".main":
            // Check if it's accessing a known global singleton
            return isSingletonAccess(line, pattern: pattern)

        default:
            return line.contains(pattern)
        }
    }

    private func isGlobalVariable(_ line: String) -> Bool {
        // Simple heuristic: if 'var' is at the start of the line (after trimming)
        // and not preceded by access modifiers that would make it private
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("var ") {
            // Check if it has private/fileprivate access
            return !trimmed.hasPrefix("private var ") && !trimmed.hasPrefix("fileprivate var ")
        }

        return false
    }

    private func isPublicStaticVariable(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for public/internal static variables
        if trimmed.hasPrefix("static var ") || trimmed.hasPrefix("class var ") {
            // Exclude private and file-private static variables
            return !trimmed.hasPrefix("private static var ") &&
                   !trimmed.hasPrefix("fileprivate static var ") &&
                   !trimmed.hasPrefix("private class var ") &&
                   !trimmed.hasPrefix("fileprivate class var ")
        }

        return false
    }

    private func isSingletonAccess(_ line: String, pattern: String) -> Bool {
        // Check if it's accessing known singletons that contain global state
        let singletonPatterns = [
            "UserDefaults.standard",
            "UserDefaults.shared",
            "UIApplication.shared",
            "HTTPCookieStorage.shared",
            "FileManager.default",
            "NotificationCenter.default",
            "URLCache.shared",
            "URLSession.shared"
        ]

        for singleton in singletonPatterns {
            if line.contains(singleton) {
                return true
            }
        }

        // For generic .shared/.default/.main access, be more conservative
        // Only flag if it's not a local variable access
        if pattern == ".shared" || pattern == ".default" || pattern == ".main" {
            // Avoid flagging things like "self.shared" or "instance.shared"
            return !line.contains("self.") && !line.contains("instance.")
        }

        return false
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}