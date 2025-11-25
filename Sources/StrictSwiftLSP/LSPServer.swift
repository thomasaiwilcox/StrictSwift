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
    
    // Document management
    private var openDocuments: [String: OpenDocument] = [:]
    
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
    
    init() {
        self.transport = JSONRPCTransport(
            input: FileHandle.standardInput,
            output: FileHandle.standardOutput
        )
    }
    
    func run() async {
        fputs("StrictSwift LSP Server starting...\n", stderr)
        
        while isRunning {
            do {
                if let message = try await transport.readMessage() {
                    await handleMessage(message)
                }
            } catch {
                fputs("Error reading message: \(error)\n", stderr)
                // Don't crash on read errors, just continue
            }
        }
        
        fputs("StrictSwift LSP Server stopped.\n", stderr)
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
        fputs("Received request: \(method)\n", stderr)
        
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
        fputs("Received notification: \(method)\n", stderr)
        
        switch method {
        case "initialized":
            handleInitialized()
        case "exit":
            handleExit()
        case "textDocument/didOpen":
            await handleDidOpen(params: params)
        case "textDocument/didChange":
            await handleDidChange(params: params)
        case "textDocument/didClose":
            handleDidClose(params: params)
        case "textDocument/didSave":
            await handleDidSave(params: params)
        default:
            fputs("Unhandled notification: \(method)\n", stderr)
        }
    }
    
    // MARK: - Lifecycle Methods
    
    private func handleInitialize(params: JSON?) throws -> JSON {
        guard !isInitialized else {
            throw LSPError.invalidRequest("Server already initialized")
        }
        
        isInitialized = true
        
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
        fputs("Server initialized successfully\n", stderr)
        
        // Initialize the analyzer
        analyzer = Analyzer(configuration: configuration)
    }
    
    private func handleShutdown() -> JSON {
        shutdownRequested = true
        return .null
    }
    
    private func handleExit() {
        isRunning = false
        let exitCode: Int32 = shutdownRequested ? 0 : 1
        exit(exitCode)
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
            fputs("Invalid didOpen params\n", stderr)
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
            fputs("Invalid didChange params\n", stderr)
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
            return .array([])
        }
        
        guard openDocuments[uri] != nil else {
            return .array([])
        }
        
        // Get diagnostics from context
        guard case .array(let diagnostics) = contextObj["diagnostics"] else {
            return .array([])
        }
        
        var codeActions: [JSON] = []
        
        // Find fixes for each diagnostic
        for diagnostic in diagnostics {
            guard case .object(let diagObj) = diagnostic,
                  case .object(let data) = diagObj["data"],
                  case .array(let fixes) = data["fixes"] else {
                continue
            }
            
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
              case .number(_) = position["line"],
              case .number(_) = position["character"] else {
            return .null
        }
        
        guard openDocuments[uri] != nil else {
            return .null
        }
        
        // For now, return a simple hover for diagnostics at this position
        // In a full implementation, we'd check if the position is on a violation
        
        return .null
    }
    
    // MARK: - Analysis
    
    private func analyzeAndPublishDiagnostics(for document: OpenDocument) async {
        guard let analyzer = analyzer else { 
            fputs("No analyzer available\n", stderr)
            return 
        }
        
        // Convert URI to file path
        guard let url = URL(string: document.uri),
              url.scheme == "file" else {
            fputs("Invalid URI: \(document.uri)\n", stderr)
            return
        }
        
        do {
            // Write content to a temporary file for analysis
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".swift")
            try document.content.write(to: tempFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempFile) }
            
            fputs("Analyzing temp file: \(tempFile.path)\n", stderr)
            fputs("Content length: \(document.content.count)\n", stderr)
            
            // Analyze the file
            let violations = try await analyzer.analyze(paths: [tempFile.path])
            
            fputs("Found \(violations.count) violations\n", stderr)
            for v in violations {
                fputs("  - \(v.ruleId): \(v.message) at line \(v.location.line)\n", stderr)
            }
            
            // Convert violations to LSP diagnostics
            var diagnostics: [JSON] = []
            for violation in violations {
                let diagnostic = convertViolationToDiagnostic(violation)
                diagnostics.append(diagnostic)
            }
            
            try await publishDiagnostics(uri: document.uri, diagnostics: diagnostics)
        } catch {
            fputs("Analysis error: \(error)\n", stderr)
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
