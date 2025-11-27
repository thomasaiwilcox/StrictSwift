import Foundation

// MARK: - SourceKit UID Keys

/// Thread-safe container for SourceKit UID keys
/// Uses nonisolated access with locks for safe concurrent access
public final class SourceKitDKeys: @unchecked Sendable {
    
    /// Shared instance - requires SourceKitDLoader to be loaded first
    public static let shared = SourceKitDKeys()
    
    private var api: SourceKitDAPI?
    private var cachedKeys: [String: sourcekitd_uid_t] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    /// Initialize with the loaded API
    public func initialize(with api: SourceKitDAPI) {
        lock.lock()
        defer { lock.unlock() }
        self.api = api
    }
    
    /// Get a UID for a key string, caching the result
    public func uid(_ key: String) -> sourcekitd_uid_t? {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cachedKeys[key] {
            return cached
        }
        
        guard let api = api else { return nil }
        guard let uid = api.uid_get_from_cstr(key) else { return nil }
        
        cachedKeys[key] = uid
        return uid
    }
    
    /// Get the string representation of a UID
    public func string(from uid: sourcekitd_uid_t) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let api = api else { return nil }
        guard let ptr = api.uid_get_string_ptr(uid) else { return nil }
        return String(cString: ptr)
    }
    
    // MARK: - Request Keys
    
    /// key.request - the type of request
    public var keyRequest: sourcekitd_uid_t? { uid("key.request") }
    
    /// key.sourcefile - path to the source file
    public var keySourceFile: sourcekitd_uid_t? { uid("key.sourcefile") }
    
    /// key.sourcetext - source code content
    public var keySourceText: sourcekitd_uid_t? { uid("key.sourcetext") }
    
    /// key.offset - byte offset in the file
    public var keyOffset: sourcekitd_uid_t? { uid("key.offset") }
    
    /// key.length - length in bytes
    public var keyLength: sourcekitd_uid_t? { uid("key.length") }
    
    /// key.compilerargs - compiler arguments array
    public var keyCompilerArgs: sourcekitd_uid_t? { uid("key.compilerargs") }
    
    /// key.usr - Unified Symbol Resolution identifier
    public var keyUSR: sourcekitd_uid_t? { uid("key.usr") }
    
    /// key.name - symbol name
    public var keyName: sourcekitd_uid_t? { uid("key.name") }
    
    /// key.typename - type name string
    public var keyTypeName: sourcekitd_uid_t? { uid("key.typename") }
    
    /// key.doc.full_as_xml - full documentation as XML
    public var keyDocFullAsXML: sourcekitd_uid_t? { uid("key.doc.full_as_xml") }
    
    /// key.annotated_decl - annotated declaration
    public var keyAnnotatedDecl: sourcekitd_uid_t? { uid("key.annotated_decl") }
    
    /// key.fully_annotated_decl - fully annotated declaration
    public var keyFullyAnnotatedDecl: sourcekitd_uid_t? { uid("key.fully_annotated_decl") }
    
    /// key.kind - symbol kind UID
    public var keyKind: sourcekitd_uid_t? { uid("key.kind") }
    
    /// key.filepath - path where symbol is defined
    public var keyFilePath: sourcekitd_uid_t? { uid("key.filepath") }
    
    /// key.line - line number (1-based)
    public var keyLine: sourcekitd_uid_t? { uid("key.line") }
    
    /// key.column - column number (1-based)
    public var keyColumn: sourcekitd_uid_t? { uid("key.column") }
    
    /// key.is_system - whether symbol is from system module
    public var keyIsSystem: sourcekitd_uid_t? { uid("key.is_system") }
    
    /// key.modulename - module name
    public var keyModuleName: sourcekitd_uid_t? { uid("key.modulename") }
    
    /// key.decl_lang - declaration language
    public var keyDeclLang: sourcekitd_uid_t? { uid("key.decl_lang") }
    
    /// key.effective_access - effective access level
    public var keyEffectiveAccess: sourcekitd_uid_t? { uid("key.effective_access") }
    
    /// key.receivers - array of receivers for symbol
    public var keyReceivers: sourcekitd_uid_t? { uid("key.receivers") }
    
    /// key.entities - child entities
    public var keyEntities: sourcekitd_uid_t? { uid("key.entities") }
    
    /// key.substructure - substructure information
    public var keySubstructure: sourcekitd_uid_t? { uid("key.substructure") }
    
    /// key.syntaxmap - syntax map
    public var keySyntaxMap: sourcekitd_uid_t? { uid("key.syntaxmap") }
    
    /// key.diagnostic_stage - diagnostic stage
    public var keyDiagnosticStage: sourcekitd_uid_t? { uid("key.diagnostic_stage") }
    
    /// key.diagnostics - array of diagnostics
    public var keyDiagnostics: sourcekitd_uid_t? { uid("key.diagnostics") }
    
    /// key.description - diagnostic description
    public var keyDescription: sourcekitd_uid_t? { uid("key.description") }
    
    /// key.severity - diagnostic severity
    public var keySeverity: sourcekitd_uid_t? { uid("key.severity") }
    
    // MARK: - Request Types
    
    /// source.request.cursorinfo - cursor info request
    public var requestCursorInfo: sourcekitd_uid_t? { uid("source.request.cursorinfo") }
    
    /// source.request.indexsource - index source request
    public var requestIndexSource: sourcekitd_uid_t? { uid("source.request.indexsource") }
    
    /// source.request.editor.open - open document for editing
    public var requestEditorOpen: sourcekitd_uid_t? { uid("source.request.editor.open") }
    
    /// source.request.editor.close - close document
    public var requestEditorClose: sourcekitd_uid_t? { uid("source.request.editor.close") }
    
    /// source.request.editor.replacetext - replace text in document
    public var requestEditorReplaceText: sourcekitd_uid_t? { uid("source.request.editor.replacetext") }
    
    /// source.request.codecomplete - code completion request
    public var requestCodeComplete: sourcekitd_uid_t? { uid("source.request.codecomplete") }
    
    /// source.request.docinfo - documentation info request
    public var requestDocInfo: sourcekitd_uid_t? { uid("source.request.docinfo") }
    
    /// source.request.expression.type - expression type request
    public var requestExpressionType: sourcekitd_uid_t? { uid("source.request.expression.type") }
    
    /// source.request.variable.type - variable type request
    public var requestVariableType: sourcekitd_uid_t? { uid("source.request.variable.type") }
    
    /// source.request.semantic_tokens - semantic tokens request
    public var requestSemanticTokens: sourcekitd_uid_t? { uid("source.request.semantic_tokens") }
    
    // MARK: - Symbol Kinds
    
    /// source.lang.swift.decl.class
    public var declClass: sourcekitd_uid_t? { uid("source.lang.swift.decl.class") }
    
    /// source.lang.swift.decl.struct
    public var declStruct: sourcekitd_uid_t? { uid("source.lang.swift.decl.struct") }
    
    /// source.lang.swift.decl.enum
    public var declEnum: sourcekitd_uid_t? { uid("source.lang.swift.decl.enum") }
    
    /// source.lang.swift.decl.protocol
    public var declProtocol: sourcekitd_uid_t? { uid("source.lang.swift.decl.protocol") }
    
    /// source.lang.swift.decl.extension
    public var declExtension: sourcekitd_uid_t? { uid("source.lang.swift.decl.extension") }
    
    /// source.lang.swift.decl.typealias
    public var declTypeAlias: sourcekitd_uid_t? { uid("source.lang.swift.decl.typealias") }
    
    /// source.lang.swift.decl.associatedtype
    public var declAssociatedType: sourcekitd_uid_t? { uid("source.lang.swift.decl.associatedtype") }
    
    /// source.lang.swift.decl.function.free
    public var declFunctionFree: sourcekitd_uid_t? { uid("source.lang.swift.decl.function.free") }
    
    /// source.lang.swift.decl.function.method.instance
    public var declMethodInstance: sourcekitd_uid_t? { uid("source.lang.swift.decl.function.method.instance") }
    
    /// source.lang.swift.decl.function.method.static
    public var declMethodStatic: sourcekitd_uid_t? { uid("source.lang.swift.decl.function.method.static") }
    
    /// source.lang.swift.decl.function.method.class
    public var declMethodClass: sourcekitd_uid_t? { uid("source.lang.swift.decl.function.method.class") }
    
    /// source.lang.swift.decl.function.constructor
    public var declConstructor: sourcekitd_uid_t? { uid("source.lang.swift.decl.function.constructor") }
    
    /// source.lang.swift.decl.function.destructor
    public var declDestructor: sourcekitd_uid_t? { uid("source.lang.swift.decl.function.destructor") }
    
    /// source.lang.swift.decl.var.instance
    public var declVarInstance: sourcekitd_uid_t? { uid("source.lang.swift.decl.var.instance") }
    
    /// source.lang.swift.decl.var.static
    public var declVarStatic: sourcekitd_uid_t? { uid("source.lang.swift.decl.var.static") }
    
    /// source.lang.swift.decl.var.class
    public var declVarClass: sourcekitd_uid_t? { uid("source.lang.swift.decl.var.class") }
    
    /// source.lang.swift.decl.var.global
    public var declVarGlobal: sourcekitd_uid_t? { uid("source.lang.swift.decl.var.global") }
    
    /// source.lang.swift.decl.var.local
    public var declVarLocal: sourcekitd_uid_t? { uid("source.lang.swift.decl.var.local") }
    
    /// source.lang.swift.decl.var.parameter
    public var declVarParameter: sourcekitd_uid_t? { uid("source.lang.swift.decl.var.parameter") }
    
    /// source.lang.swift.decl.actor
    public var declActor: sourcekitd_uid_t? { uid("source.lang.swift.decl.actor") }
    
    /// source.lang.swift.decl.macro
    public var declMacro: sourcekitd_uid_t? { uid("source.lang.swift.decl.macro") }
    
    // MARK: - Reference Kinds
    
    /// source.lang.swift.ref.class
    public var refClass: sourcekitd_uid_t? { uid("source.lang.swift.ref.class") }
    
    /// source.lang.swift.ref.struct
    public var refStruct: sourcekitd_uid_t? { uid("source.lang.swift.ref.struct") }
    
    /// source.lang.swift.ref.enum
    public var refEnum: sourcekitd_uid_t? { uid("source.lang.swift.ref.enum") }
    
    /// source.lang.swift.ref.protocol
    public var refProtocol: sourcekitd_uid_t? { uid("source.lang.swift.ref.protocol") }
    
    /// source.lang.swift.ref.function.free
    public var refFunctionFree: sourcekitd_uid_t? { uid("source.lang.swift.ref.function.free") }
    
    /// source.lang.swift.ref.function.method.instance
    public var refMethodInstance: sourcekitd_uid_t? { uid("source.lang.swift.ref.function.method.instance") }
    
    /// source.lang.swift.ref.function.constructor
    public var refConstructor: sourcekitd_uid_t? { uid("source.lang.swift.ref.function.constructor") }
    
    /// source.lang.swift.ref.var.instance
    public var refVarInstance: sourcekitd_uid_t? { uid("source.lang.swift.ref.var.instance") }
    
    /// source.lang.swift.ref.var.global
    public var refVarGlobal: sourcekitd_uid_t? { uid("source.lang.swift.ref.var.global") }
    
    // MARK: - Diagnostic Severity
    
    /// source.diagnostic.severity.error
    public var severityError: sourcekitd_uid_t? { uid("source.diagnostic.severity.error") }
    
    /// source.diagnostic.severity.warning
    public var severityWarning: sourcekitd_uid_t? { uid("source.diagnostic.severity.warning") }
    
    /// source.diagnostic.severity.note
    public var severityNote: sourcekitd_uid_t? { uid("source.diagnostic.severity.note") }
    
    // MARK: - Languages
    
    /// source.lang.swift
    public var langSwift: sourcekitd_uid_t? { uid("source.lang.swift") }
    
    /// source.lang.objc
    public var langObjC: sourcekitd_uid_t? { uid("source.lang.objc") }
    
    /// source.lang.c
    public var langC: sourcekitd_uid_t? { uid("source.lang.c") }
    
    /// source.lang.cxx
    public var langCXX: sourcekitd_uid_t? { uid("source.lang.cxx") }
    
    // MARK: - Convenience Methods
    
    /// Check if a kind UID represents a type declaration
    public func isTypeDeclaration(_ kind: sourcekitd_uid_t?) -> Bool {
        guard let kind = kind else { return false }
        
        return kind == declClass ||
               kind == declStruct ||
               kind == declEnum ||
               kind == declProtocol ||
               kind == declActor ||
               kind == declTypeAlias ||
               kind == declAssociatedType
    }
    
    /// Check if a kind UID represents a function/method declaration
    public func isFunctionDeclaration(_ kind: sourcekitd_uid_t?) -> Bool {
        guard let kind = kind else { return false }
        
        return kind == declFunctionFree ||
               kind == declMethodInstance ||
               kind == declMethodStatic ||
               kind == declMethodClass ||
               kind == declConstructor ||
               kind == declDestructor
    }
    
    /// Check if a kind UID represents a variable/property declaration
    public func isVariableDeclaration(_ kind: sourcekitd_uid_t?) -> Bool {
        guard let kind = kind else { return false }
        
        return kind == declVarInstance ||
               kind == declVarStatic ||
               kind == declVarClass ||
               kind == declVarGlobal ||
               kind == declVarLocal ||
               kind == declVarParameter
    }
    
    /// Get a human-readable name for a symbol kind
    public func kindName(_ kind: sourcekitd_uid_t?) -> String? {
        guard let kind = kind else { return nil }
        guard let str = string(from: kind) else { return nil }
        
        // Convert "source.lang.swift.decl.class" to "class"
        let components = str.split(separator: ".")
        return components.last.map(String.init)
    }
}
