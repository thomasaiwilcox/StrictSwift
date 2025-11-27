import Foundation
import StrictSwiftCore

// MARK: - LSP Server Entry Point

@main
struct StrictSwiftLSP {
    static func main() async {
        let server = LSPServer()
        await server.run()
    }
}

// MARK: - LSP Server

/// Language Server Protocol implementation for StrictSwift
actor LSPServer {
    private var transport: JSONRPCTransport
    private var isRunning = true
    private var isInitialized = false
    private var shutdownRequested = false
    private var isShuttingDown = false
    
    // Document management
    private var openDocuments: [String: OpenDocument] = [:]
    
    // Store violations per document for hover lookup
    private var documentViolations: [String: [Violation]] = [:]
    
    // Human-readable rule display names
    private static let ruleDisplayNames: [String: String] = [
        "force_unwrap": "Force Unwrap",
        "force_try": "Force Try",
        "fatal_error": "Fatal Error Usage",
        "print_in_production": "Print in Production",
        "mutable_static": "Mutable Static Property",
        "non_sendable_capture": "Non-Sendable Capture",
        "unstructured_task": "Unstructured Task",
        "actor_isolation": "Actor Isolation",
        "data_race": "Potential Data Race",
        "layered_dependencies": "Layer Dependency Violation",
        "circular_dependency": "Circular Dependency",
        "god_class": "God Class",
        "global_state": "Global State Access",
        "escaping_reference": "Escaping Reference",
        "exclusive_access": "Exclusive Access Violation",
        "cyclomatic_complexity": "High Cyclomatic Complexity",
        "nesting_depth": "Excessive Nesting",
        "function_length": "Function Too Long",
        "module_boundary": "Module Boundary Violation",
        "import_direction": "Import Direction Violation",
        "repeated_allocation": "Repeated Allocation",
        "large_struct_copy": "Large Struct Copy",
        "arc_churn": "ARC Churn",
        "hot_path_validation": "Hot Path Issue",
        "enhanced_god_class": "God Class",
        "enhanced_layered_dependencies": "Layer Violation",
        "architectural_health": "Architectural Health"
    ]
    
    // Human-readable category display names
    private static let categoryDisplayNames: [String: String] = [
        "safety": "🛡️ Safety",
        "concurrency": "⚡ Concurrency", 
        "architecture": "🏛️ Architecture",
        "memory": "💾 Memory",
        "complexity": "🔀 Complexity",
        "performance": "🚀 Performance"
    ]
    
    /// Log a message to stderr in a thread-safe way
    private func log(_ message: String) {
        if let data = (message + "\n").data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }
    
    // Analysis engine
    private var analyzer: Analyzer?
    /// LSP configuration - no include filters since editor explicitly opens files
    private var configuration: Configuration = Configuration(
        profile: .criticalCore,
        rules: RulesConfiguration(
            memory: RuleConfiguration(severity: .error),
            concurrency: RuleConfiguration(severity: .error),
            architecture: RuleConfiguration(severity: .error),
            safety: RuleConfiguration(severity: .error),
            performance: RuleConfiguration(severity: .warning),
            complexity: RuleConfiguration(severity: .error),
            monolith: RuleConfiguration(severity: .error),
            dependency: RuleConfiguration(severity: .error)
        ),
        include: [],  // Empty = include all files
        exclude: ["**/.build/**", "**/*.generated.swift"]
    )
    
    /// Apply configuration from VS Code settings
    private func applyConfiguration(_ settings: [String: JSON]) {
        log("Applying configuration from VS Code settings")
        
        // Parse profile - map VS Code names to actual enum cases
        var profile: Profile = .criticalCore
        if case .string(let profileStr) = settings["profile"] {
            switch profileStr {
            case "criticalCore": profile = .criticalCore
            case "teamDefault", "serverDefault": profile = .serverDefault
            case "legacy", "appRelaxed": profile = .appRelaxed
            case "newProject", "libraryStrict": profile = .libraryStrict
            case "enterprise", "rustEquivalent", "rustInspired": profile = .rustInspired
            default: break
            }
        }
        
        // Parse rule settings
        func parseRuleConfig(_ category: String, defaultSeverity: DiagnosticSeverity) -> RuleConfiguration {
            if case .object(let rules) = settings["rules"],
               case .object(let catConfig) = rules[category] {
                var enabled = true
                if case .bool(let e) = catConfig["enabled"] {
                    enabled = e
                }
                var severity = defaultSeverity
                if case .string(let sevStr) = catConfig["severity"] {
                    severity = DiagnosticSeverity(rawValue: sevStr) ?? defaultSeverity
                }
                return RuleConfiguration(severity: severity, enabled: enabled)
            }
            return RuleConfiguration(severity: defaultSeverity)
        }
        
        let safetyConfig = parseRuleConfig("safety", defaultSeverity: .error)
        let concurrencyConfig = parseRuleConfig("concurrency", defaultSeverity: .error)
        let memoryConfig = parseRuleConfig("memory", defaultSeverity: .error)
        let architectureConfig = parseRuleConfig("architecture", defaultSeverity: .warning)
        let complexityConfig = parseRuleConfig("complexity", defaultSeverity: .warning)
        let performanceConfig = parseRuleConfig("performance", defaultSeverity: .hint)
        
        // Parse exclude paths
        var excludePaths = ["**/.build/**", "**/*.generated.swift"]
        if case .array(let paths) = settings["excludePaths"] {
            excludePaths = paths.compactMap { path in
                if case .string(let str) = path { return str }
                return nil
            }
        }
        
        // Parse useEnhancedRules setting
        var useEnhancedRules = false
        if case .bool(let enhanced) = settings["useEnhancedRules"] {
            useEnhancedRules = enhanced
        }
        
        // Parse threshold settings
        var maxFileLines = 200
        var maxFunctionLines = 50
        var maxCyclomaticComplexity = 10
        
        if case .object(let thresholds) = settings["thresholds"] {
            if case .number(let val) = thresholds["maxFileLines"] {
                maxFileLines = Int(val)
            }
            if case .number(let val) = thresholds["maxFunctionLines"] {
                maxFunctionLines = Int(val)
            }
            if case .number(let val) = thresholds["maxCyclomaticComplexity"] {
                maxCyclomaticComplexity = Int(val)
            }
        }
        
        // Also check for top-level settings (VS Code sends them flat)
        if case .number(let val) = settings["maxFileLines"] {
            maxFileLines = Int(val)
        }
        if case .number(let val) = settings["maxFunctionLines"] {
            maxFunctionLines = Int(val)
        }
        if case .number(let val) = settings["maxCyclomaticComplexity"] {
            maxCyclomaticComplexity = Int(val)
        }
        
        // Create threshold configuration
        let thresholdConfig = ThresholdConfiguration(
            maxCyclomaticComplexity: maxCyclomaticComplexity,
            maxMethodLength: maxFunctionLines,
            maxTypeComplexity: 100,
            maxNestingDepth: 4,
            maxParameterCount: 5,
            maxPropertyCount: 20,
            maxFileLength: maxFileLines
        )
        
        // Create advanced configuration with thresholds
        let advancedConfig = AdvancedConfiguration(
            ruleSettings: [:],
            conditionalSettings: [],
            thresholds: thresholdConfig,
            performanceSettings: PerformanceConfiguration(),
            scopeSettings: ScopeConfiguration()
        )
        
        configuration = Configuration(
            profile: profile,
            rules: RulesConfiguration(
                memory: memoryConfig,
                concurrency: concurrencyConfig,
                architecture: architectureConfig,
                safety: safetyConfig,
                performance: performanceConfig,
                complexity: complexityConfig,
                monolith: architectureConfig,
                dependency: architectureConfig
            ),
            include: [],
            exclude: excludePaths,
            advanced: advancedConfig,
            useEnhancedRules: useEnhancedRules
        )
        
        // Recreate analyzer with new configuration
        analyzer = Analyzer(configuration: configuration)
        log("Configuration applied: profile=\(profile), safety=\(safetyConfig.severity), useEnhancedRules=\(useEnhancedRules), maxFileLines=\(maxFileLines), maxFunctionLines=\(maxFunctionLines), maxCyclomaticComplexity=\(maxCyclomaticComplexity)")
    }
    
    /// Handle workspace/didChangeConfiguration notification
    private func handleDidChangeConfiguration(params: JSON?) async {
        guard let params = params,
              case .object(let obj) = params,
              case .object(let settings) = obj["settings"],
              case .object(let strictswift) = settings["strictswift"] else {
            return
        }
        
        applyConfiguration(strictswift)
        
        // Re-analyze all open documents
        for (_, document) in openDocuments {
            await analyzeAndPublishDiagnostics(for: document)
        }
    }
    
    init() {
        self.transport = JSONRPCTransport(
            input: FileHandle.standardInput,
            output: FileHandle.standardOutput
        )
    }
    
    func run() async {
        log("StrictSwift LSP Server starting...")
        
        while isRunning {
            do {
                if let message = try await transport.readMessage() {
                    await handleMessage(message)
                } else if isShuttingDown {
                    // EOF received during shutdown - this is expected
                    isRunning = false
                    break
                }
            } catch {
                if isShuttingDown {
                    // Errors during shutdown are expected (stream closed)
                    isRunning = false
                    break
                }
                log("Error reading message: \(error)")
                // Don't crash on read errors, just continue
            }
        }
        
        log("StrictSwift LSP Server stopped.")
    }
    
    // MARK: - Message Handling
    
    private func handleMessage(_ message: JSONRPCMessage) async {
        switch message {
        case .request(let id, let method, let params):
            await handleRequest(id: id, method: method, params: params)
        case .notification(let method, let params):
            await handleNotification(method: method, params: params)
        case .response:
            // We don't expect responses from the client in this direction
            break
        }
    }
    
    private func handleRequest(id: RequestID, method: String, params: JSON?) async {
        log("Received request: \(method)")
        
        do {
            let result: JSON
            
            switch method {
            case "initialize":
                result = try handleInitialize(params: params)
            case "shutdown":
                result = handleShutdown()
            case "textDocument/codeAction":
                result = await handleCodeAction(params: params)
            case "textDocument/hover":
                result = await handleHover(params: params)
            default:
                throw LSPError.methodNotFound(method)
            }
            
            try await transport.sendResponse(id: id, result: result)
        } catch let error as LSPError {
            try? await transport.sendError(id: id, code: error.code, message: error.message)
        } catch {
            try? await transport.sendError(id: id, code: -32603, message: error.localizedDescription)
        }
    }
    
    private func handleNotification(method: String, params: JSON?) async {
        log("Received notification: \(method)")
        
        switch method {
        case "initialized":
            handleInitialized()
        case "exit":
            await handleExit()
        case "textDocument/didOpen":
            await handleDidOpen(params: params)
        case "textDocument/didChange":
            await handleDidChange(params: params)
        case "textDocument/didClose":
            handleDidClose(params: params)
        case "textDocument/didSave":
            await handleDidSave(params: params)
        case "workspace/didChangeConfiguration":
            await handleDidChangeConfiguration(params: params)
        default:
            log("Unhandled notification: \(method)")
        }
    }
    
    // MARK: - Lifecycle Methods
    
    private func handleInitialize(params: JSON?) throws -> JSON {
        guard !isInitialized else {
            throw LSPError.invalidRequest("Server already initialized")
        }
        
        isInitialized = true
        
        // Parse initialization options for configuration
        if let params = params,
           case .object(let paramsObj) = params,
           case .object(let initOptions) = paramsObj["initializationOptions"] {
            applyConfiguration(initOptions)
        }
        
        // Return server capabilities
        return .object([
            "capabilities": .object([
                "textDocumentSync": .object([
                    "openClose": .bool(true),
                    "change": .number(1), // Full sync
                    "save": .object([
                        "includeText": .bool(true)
                    ])
                ]),
                "codeActionProvider": .object([
                    "codeActionKinds": .array([
                        .string("quickfix"),
                        .string("refactor")
                    ])
                ]),
                "hoverProvider": .bool(true)
            ]),
            "serverInfo": .object([
                "name": .string("StrictSwift LSP"),
                "version": .string("0.11.0")
            ])
        ])
    }
    
    private func handleInitialized() {
        log("Server initialized successfully")
        
        // Initialize the analyzer
        analyzer = Analyzer(configuration: configuration)
    }
    
    private func handleShutdown() -> JSON {
        log("Shutdown requested")
        shutdownRequested = true
        isShuttingDown = true
        return .null
    }
    
    private func handleExit() async {
        log("Exit notification received")
        isRunning = false
        isShuttingDown = true
        // Mark the transport as shutdown to prevent further writes
        await transport.shutdown()
        // Let the run loop exit gracefully instead of calling exit() abruptly
        // The process will terminate when run() returns
    }
    
    // MARK: - Document Sync
    
    private func handleDidOpen(params: JSON?) async {
        guard let params = params,
              case .object(let obj) = params,
              case .object(let textDocument) = obj["textDocument"],
              case .string(let uri) = textDocument["uri"],
              case .string(let text) = textDocument["text"],
              case .string(let languageId) = textDocument["languageId"],
              case .number(let version) = textDocument["version"] else {
            log("Invalid didOpen params")
            return
        }
        
        // Only handle Swift files
        guard languageId == "swift" else { return }
        
        let document = OpenDocument(
            uri: uri,
            content: text,
            version: Int(version)
        )
        openDocuments[uri] = document
        
        // Analyze and publish diagnostics
        await analyzeAndPublishDiagnostics(for: document)
    }
    
    private func handleDidChange(params: JSON?) async {
        guard let params = params,
              case .object(let obj) = params,
              case .object(let textDocument) = obj["textDocument"],
              case .string(let uri) = textDocument["uri"],
              case .number(let version) = textDocument["version"],
              case .array(let changes) = obj["contentChanges"] else {
            log("Invalid didChange params")
            return
        }
        
        // For full sync, take the last change
        guard case .object(let lastChange) = changes.last,
              case .string(let text) = lastChange["text"] else {
            return
        }
        
        let document = OpenDocument(
            uri: uri,
            content: text,
            version: Int(version)
        )
        openDocuments[uri] = document
        
        // Debounce: only analyze on save for now
        // In production, we'd want proper debouncing
    }
    
    private func handleDidClose(params: JSON?) {
        guard let params = params,
              case .object(let obj) = params,
              case .object(let textDocument) = obj["textDocument"],
              case .string(let uri) = textDocument["uri"] else {
            return
        }
        
        openDocuments.removeValue(forKey: uri)
        
        // Clear diagnostics for closed document
        Task {
            try? await publishDiagnostics(uri: uri, diagnostics: [])
        }
    }
    
    private func handleDidSave(params: JSON?) async {
        guard let params = params,
              case .object(let obj) = params,
              case .object(let textDocument) = obj["textDocument"],
              case .string(let uri) = textDocument["uri"] else {
            return
        }
        
        // Update content if included
        if case .string(let text) = obj["text"] {
            if var document = openDocuments[uri] {
                document.content = text
                document.version += 1
                openDocuments[uri] = document
            }
        }
        
        // Analyze on save
        if let document = openDocuments[uri] {
            await analyzeAndPublishDiagnostics(for: document)
        }
    }
    
    // MARK: - Code Actions
    
    private func handleCodeAction(params: JSON?) async -> JSON {
        guard let params = params,
              case .object(let obj) = params,
              case .object(let textDocument) = obj["textDocument"],
              case .string(let uri) = textDocument["uri"],
              case .object(_) = obj["range"],
              case .object(let contextObj) = obj["context"] else {
            log("Code action: invalid params")
            return .array([])
        }
        
        guard let document = openDocuments[uri] else {
            log("Code action: document not found")
            return .array([])
        }
        
        // Get diagnostics from context
        guard case .array(let diagnostics) = contextObj["diagnostics"] else {
            log("Code action: no diagnostics in context")
            return .array([])
        }
        
        log("Code action: processing \(diagnostics.count) diagnostics")
        
        var codeActions: [JSON] = []
        
        // Find fixes for each diagnostic
        for diagnostic in diagnostics {
            guard case .object(let diagObj) = diagnostic else {
                continue
            }
            
            // Check if we have data with fixes
            if case .object(let data) = diagObj["data"],
               case .array(let fixes) = data["fixes"] {
                
                for fix in fixes {
                    guard case .object(let fixObj) = fix,
                          case .string(let title) = fixObj["title"],
                          case .array(let edits) = fixObj["edits"] else {
                        continue
                    }
                    
                    // Convert to workspace edit
                    var textEdits: [JSON] = []
                    for edit in edits {
                        guard case .object(let editObj) = edit,
                              case .object(let rangeObj) = editObj["range"],
                              case .string(let newText) = editObj["newText"] else {
                            continue
                        }
                        
                        textEdits.append(.object([
                            "range": .object(rangeObj),
                            "newText": .string(newText)
                        ]))
                    }
                    
                    let action: JSON = .object([
                        "title": .string(title),
                        "kind": .string("quickfix"),
                        "diagnostics": .array([diagnostic]),
                        "edit": .object([
                            "changes": .object([
                                uri: .array(textEdits)
                            ])
                        ])
                    ])
                    
                    codeActions.append(action)
                }
            } else {
                // Log what we do have
                if case .string(_) = diagObj["code"] {
                    // diagnostic code available
                }
            }
        }
        
        return .array(codeActions)
    }
    
    // MARK: - Hover
    
    private func handleHover(params: JSON?) async -> JSON {
        guard let params = params,
              case .object(let obj) = params,
              case .object(let textDocument) = obj["textDocument"],
              case .string(let uri) = textDocument["uri"],
              case .object(let position) = obj["position"],
              case .number(let line) = position["line"],
              case .number(_) = position["character"] else {
            return .null
        }
        
        guard openDocuments[uri] != nil else {
            return .null
        }
        
        // Find violations at this position
        guard let violations = documentViolations[uri] else {
            return .null
        }
        
        // LSP uses 0-based lines, our violations use 1-based
        let targetLine = Int(line) + 1
        
        // Find a violation on this line
        guard let violation = violations.first(where: { $0.location.line == targetLine }) else {
            return .null
        }
        
        // Get human-readable rule name
        let ruleDisplayName = Self.ruleDisplayNames[violation.ruleId] ?? violation.ruleId.replacingOccurrences(of: "_", with: " ").capitalized
        let categoryDisplayName = Self.categoryDisplayNames[violation.category.rawValue] ?? violation.category.rawValue
        
        // Build rich hover content
        let severityEmoji: String
        let severityName: String
        switch violation.severity {
        case .error: 
            severityEmoji = "🔴"
            severityName = "Error"
        case .warning: 
            severityEmoji = "🟡"
            severityName = "Warning"
        case .hint: 
            severityEmoji = "💡"
            severityName = "Hint"
        case .info: 
            severityEmoji = "ℹ️"
            severityName = "Info"
        }
        
        var markdown = "## \(severityEmoji) \(ruleDisplayName)\n\n"
        markdown += "**Category:** \(categoryDisplayName)  •  **Severity:** \(severityName)\n\n"
        markdown += "---\n\n"
        markdown += "\(violation.message)\n\n"
        
        // Add suggested fixes
        if !violation.suggestedFixes.isEmpty {
            markdown += "### Suggested Fixes\n\n"
            for fix in violation.suggestedFixes {
                markdown += "- \(fix)\n"
            }
            markdown += "\n"
        }
        
        // Add structured fix info
        if !violation.structuredFixes.isEmpty {
            markdown += "### Quick Fixes Available\n\n"
            for fix in violation.structuredFixes {
                markdown += "- **\(fix.title)**"
                if let description = fix.description {
                    markdown += ": \(description)"
                }
                markdown += "\n"
            }
            markdown += "\n"
            markdown += "_Click the 💡 lightbulb to apply a fix_\n"
        }
        
        // Add context info if available
        if !violation.context.isEmpty {
            markdown += "\n### Context\n\n"
            for (key, value) in violation.context.sorted(by: { $0.key < $1.key }) {
                markdown += "- **\(key):** \(value)\n"
            }
        }
        
        return .object([
            "contents": .object([
                "kind": .string("markdown"),
                "value": .string(markdown)
            ])
        ])
    }
    
    // MARK: - Analysis
    
    private func analyzeAndPublishDiagnostics(for document: OpenDocument) async {
        guard let analyzer = analyzer else { 
            // No analyzer available
            return 
        }
        
        // Convert URI to file path
        guard let url = URL(string: document.uri),
              url.scheme == "file" else {
            // Invalid URI
            return
        }
        
        do {
            // Write content to a temporary file for analysis
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".swift")
            try document.content.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }
            
            // Analyze the file
            let violations = try await analyzer.analyze(paths: [tempFile.path])
            
            // Convert violations to LSP diagnostics
            var diagnostics: [JSON] = []
            for violation in violations {
                let diagnostic = convertViolationToDiagnostic(violation)
                diagnostics.append(diagnostic)
            }
            
            // Store violations for hover lookup
            documentViolations[document.uri] = violations
            
            try await publishDiagnostics(uri: document.uri, diagnostics: diagnostics)
        } catch {
            // Analysis error - log for debugging
            log("Document analysis failed for \(document.uri): \(error)")
        }
    }
    
    private func convertViolationToDiagnostic(_ violation: Violation) -> JSON {
        let severity: Int
        switch violation.severity {
        case .error: severity = 1
        case .warning: severity = 2
        case .hint: severity = 4
        case .info: severity = 3
        }
        
        // Convert fixes to JSON for code actions
        var fixesArray: [JSON] = []
        for fix in violation.structuredFixes {
            var editsArray: [JSON] = []
            for edit in fix.edits {
                let editJSON: JSON = .object([
                    "range": .object([
                        "start": .object([
                            "line": .number(Double(edit.range.startLine - 1)),
                            "character": .number(Double(edit.range.startColumn - 1))
                        ]),
                        "end": .object([
                            "line": .number(Double(edit.range.endLine - 1)),
                            "character": .number(Double(edit.range.endColumn - 1))
                        ])
                    ]),
                    "newText": .string(edit.newText)
                ])
                editsArray.append(editJSON)
            }
            
            let fixJSON: JSON = .object([
                "title": .string(fix.title),
                "edits": .array(editsArray)
            ])
            fixesArray.append(fixJSON)
        }
        
        let rangeJSON: JSON = .object([
            "start": .object([
                "line": .number(Double(violation.location.line - 1)),
                "character": .number(Double(violation.location.column - 1))
            ]),
            "end": .object([
                "line": .number(Double(violation.location.line - 1)),
                "character": .number(Double(violation.location.column + 10))
            ])
        ])
        
        return .object([
            "range": rangeJSON,
            "severity": .number(Double(severity)),
            "source": .string("strictswift"),
            "code": .string(violation.ruleId),
            "message": .string(violation.message),
            "data": .object([
                "fixes": .array(fixesArray)
            ])
        ])
    }
    
    private func publishDiagnostics(uri: String, diagnostics: [JSON]) async throws {
        let notification: JSON = .object([
            "uri": .string(uri),
            "diagnostics": .array(diagnostics)
        ])
        
        try await transport.sendNotification(method: "textDocument/publishDiagnostics", params: notification)
    }
}

// MARK: - Open Document

struct OpenDocument {
    let uri: String
    var content: String
    var version: Int
}

// MARK: - LSP Errors

enum LSPError: Error {
    case methodNotFound(String)
    case invalidRequest(String)
    case invalidParams(String)
    case internalError(String)
    
    var code: Int {
        switch self {
        case .methodNotFound: return -32601
        case .invalidRequest: return -32600
        case .invalidParams: return -32602
        case .internalError: return -32603
        }
    }
    
    var message: String {
        switch self {
        case .methodNotFound(let method): return "Method not found: \(method)"
        case .invalidRequest(let msg): return "Invalid request: \(msg)"
        case .invalidParams(let msg): return "Invalid params: \(msg)"
        case .internalError(let msg): return "Internal error: \(msg)"
        }
    }
}
