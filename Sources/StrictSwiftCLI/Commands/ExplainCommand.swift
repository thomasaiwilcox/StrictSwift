import ArgumentParser
import Foundation

/// Get detailed information about a rule
struct ExplainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "explain",
        abstract: "Get detailed information about a rule"
    )

    @Argument(help: "The rule ID to explain")
    var ruleId: String

    func run() async throws {
        guard let explanation = ruleExplanations[ruleId] else {
            print("Unknown rule: \(ruleId)")
            print("\nAvailable rules:")
            for ruleId in ruleExplanations.keys.sorted() {
                print("  - \(ruleId)")
            }
            return
        }
        
        print(explanation)
    }
}

// MARK: - Rule Explanations

private let ruleExplanations: [String: String] = [
    "dead-code": """
        ╔══════════════════════════════════════════════════════════════════════════════╗
        ║                              DEAD CODE RULE                                   ║
        ╠══════════════════════════════════════════════════════════════════════════════╣
        ║  Rule ID: dead-code                                                          ║
        ║  Category: Architecture                                                       ║
        ║  Default Severity: Warning                                                    ║
        ╚══════════════════════════════════════════════════════════════════════════════╝
        
        DESCRIPTION
        ───────────
        Detects unreachable code that is never called or used in your codebase.
        Dead code increases maintenance burden, clutters the codebase, and can
        hide potential bugs.
        
        HOW IT WORKS
        ────────────
        The rule builds a global reference graph of all symbols in your project,
        then performs reachability analysis from entry points to identify which
        symbols are "live" (reachable) and which are "dead" (unreachable).
        
        Entry points include:
        • @main and @UIApplicationMain/@NSApplicationMain types
        • main.swift files
        • Public/open symbols (in library mode)
        • @objc and @IBAction/@IBOutlet methods
        • XCTest methods (test*, setUp*, tearDown*)
        • Protocol implementations
        
        CONFIGURATION
        ─────────────
        In your .strictswift.yml:
        
        ```yaml
        rules:
          dead-code:
            enabled: true
            severity: warning
            parameters:
              # Mode: 'library', 'executable', 'hybrid', or 'auto'
              # - library: public/open symbols are entry points
              # - executable: only @main, main.swift are entry points
              # - hybrid: both public and @main are entry points
              # - auto: detect from Package.swift (default)
              mode: auto
              
              # Treat public symbols as entry points (for library mode)
              treatPublicAsEntryPoint: true
              
              # Prefixes to ignore (e.g., "_" for internal APIs)
              ignoredPrefixes:
                - "_"
                
              # Additional attributes that mark entry points
              entryPointAttributes:
                - "@IBAction"
                - "@objc"
                
              # Minimum confidence level to report
              # - high: only private/fileprivate (definitely dead)
              # - medium: include internal/package
              # - low: include public/open (might be used externally)
              minimumConfidence: medium
        ```
        
        CONFIDENCE LEVELS
        ─────────────────
        • HIGH: Private/fileprivate symbols - definitely dead if unreachable
        • MEDIUM: Internal/package symbols - likely dead within module
        • LOW: Public/open symbols - might be used by external modules
        
        Higher confidence dead code is reported with higher severity.
        
        EXAMPLES
        ────────
        
        ✗ BAD - Unused private function:
        
            class MyClass {
                func publicMethod() { }
                
                private func unusedHelper() {  // Dead code!
                    // Never called anywhere
                }
            }
        
        ✓ GOOD - All code is reachable:
        
            class MyClass {
                func publicMethod() {
                    helper()
                }
                
                private func helper() {
                    // Called from publicMethod
                }
            }
        
        AUTO-FIXES
        ──────────
        The rule provides structured fixes to remove dead code:
        
        • Remove the entire declaration
        • Includes the symbol name and location
        • Safe confidence level for private/fileprivate symbols
        
        RELATED RULES
        ─────────────
        • god-class - Detects classes with too many responsibilities
        • circular-dependency - Detects circular type dependencies
        • global-state - Detects mutable global state
        
        SEE ALSO
        ────────
        • https://en.wikipedia.org/wiki/Dead_code_elimination
        • Swift Evolution SE-0302: Sendable and @Sendable closures
        """,
    
    "force-unwrap": """
        ╔══════════════════════════════════════════════════════════════════════════════╗
        ║                            FORCE UNWRAP RULE                                  ║
        ╠══════════════════════════════════════════════════════════════════════════════╣
        ║  Rule ID: force-unwrap                                                        ║
        ║  Category: Safety                                                             ║
        ║  Default Severity: Warning                                                    ║
        ╚══════════════════════════════════════════════════════════════════════════════╝
        
        DESCRIPTION
        ───────────
        Detects force unwrapping of optionals using the ! operator, which can
        cause runtime crashes if the value is nil.
        
        EXAMPLES
        ────────
        
        ✗ BAD:
            let value = optionalValue!  // Crash if nil
        
        ✓ GOOD:
            if let value = optionalValue { ... }
            guard let value = optionalValue else { return }
            let value = optionalValue ?? defaultValue
        """,
    
    "force-try": """
        ╔══════════════════════════════════════════════════════════════════════════════╗
        ║                              FORCE TRY RULE                                   ║
        ╠══════════════════════════════════════════════════════════════════════════════╣
        ║  Rule ID: force-try                                                           ║
        ║  Category: Safety                                                             ║
        ║  Default Severity: Warning                                                    ║
        ╚══════════════════════════════════════════════════════════════════════════════╝
        
        DESCRIPTION
        ───────────
        Detects use of try! which crashes if an error is thrown. Use proper
        error handling with do-catch or try? instead.
        
        EXAMPLES
        ────────
        
        ✗ BAD:
            let data = try! Data(contentsOf: url)  // Crash on error
        
        ✓ GOOD:
            do {
                let data = try Data(contentsOf: url)
            } catch {
                // Handle error
            }
        """
]