import Foundation

// MARK: - SourceKit Error Types

/// Errors that can occur when interacting with SourceKit
public enum SourceKitError: Error, Sendable {
    case notLoaded
    case requestFailed(kind: SourceKitDErrorKind, description: String)
    case invalidResponse
    case missingRequiredKey(String)
    case timeout
    case cancelled
}

// MARK: - Request Builder

/// Builder for constructing SourceKit request dictionaries
public final class SourceKitRequestBuilder: @unchecked Sendable {
    private let api: SourceKitDAPI
    private let keys: SourceKitDKeys
    private let request: sourcekitd_request_t
    
    /// Create a new request builder
    public init(api: SourceKitDAPI, keys: SourceKitDKeys, requestType: sourcekitd_uid_t) {
        self.api = api
        self.keys = keys
        
        // Create request with the request type set
        guard let keyRequest = keys.keyRequest,
              let req = api.request_dictionary_create(nil, nil, 0) else {
            fatalError("Failed to create SourceKit request")
        }
        
        api.request_dictionary_set_uid(req, keyRequest, requestType)
        self.request = req
    }
    
    deinit {
        // Note: Don't release here - ownership transfers to send
    }
    
    /// Set a UID value for a key
    @discardableResult
    public func set(uid value: sourcekitd_uid_t, for key: sourcekitd_uid_t) -> Self {
        api.request_dictionary_set_uid(request, key, value)
        return self
    }
    
    /// Set a string value for a key
    @discardableResult
    public func set(string value: String, for key: sourcekitd_uid_t) -> Self {
        value.withCString { ptr in
            api.request_dictionary_set_string(request, key, ptr)
        }
        return self
    }
    
    /// Set an integer value for a key
    @discardableResult
    public func set(int64 value: Int64, for key: sourcekitd_uid_t) -> Self {
        api.request_dictionary_set_int64(request, key, value)
        return self
    }
    
    /// Set compiler arguments array
    @discardableResult
    public func setCompilerArgs(_ args: [String]) -> Self {
        guard let keyCompilerArgs = keys.keyCompilerArgs else {
            return self
        }
        
        // Create string objects for each argument first
        var stringObjects: [sourcekitd_object_t?] = []
        for arg in args {
            let stringObj = arg.withCString { ptr -> sourcekitd_object_t? in
                return api.request_string_create(ptr)
            }
            stringObjects.append(stringObj)
        }
        
        // Create the array with pre-built objects
        guard let argsArray = stringObjects.withUnsafeMutableBufferPointer({ ptr -> sourcekitd_request_t? in
            return api.request_array_create(ptr.baseAddress, args.count)
        }) else {
            return self
        }
        
        api.request_dictionary_set_value(request, keyCompilerArgs, argsArray)
        return self
    }
    
    /// Build and return the request, transferring ownership
    public func build() -> sourcekitd_request_t {
        return request
    }
}

// MARK: - Response Wrapper

/// Wrapper for accessing SourceKit response data
public struct SourceKitResponseValue {
    private let api: SourceKitDAPI
    private let keys: SourceKitDKeys
    private let variant: sourcekitd_variant_t
    
    init(api: SourceKitDAPI, keys: SourceKitDKeys, variant: sourcekitd_variant_t) {
        self.api = api
        self.keys = keys
        self.variant = variant
    }
    
    /// Get the variant type
    public var type: SourceKitDVariantType {
        return SourceKitDVariantType(rawValue: api.variant_get_type(variant))
    }
    
    /// Get a string value for a key
    public func getString(for key: sourcekitd_uid_t) -> String? {
        guard let ptr = api.variant_dictionary_get_string(variant, key) else {
            return nil
        }
        return String(cString: ptr)
    }
    
    /// Get an int64 value for a key
    public func getInt64(for key: sourcekitd_uid_t) -> Int64 {
        return api.variant_dictionary_get_int64(variant, key)
    }
    
    /// Get a bool value for a key
    public func getBool(for key: sourcekitd_uid_t) -> Bool {
        return api.variant_dictionary_get_bool(variant, key)
    }
    
    /// Get a UID value for a key
    public func getUID(for key: sourcekitd_uid_t) -> sourcekitd_uid_t? {
        return api.variant_dictionary_get_uid(variant, key)
    }
    
    /// Get a nested dictionary value for a key
    public func getValue(for key: sourcekitd_uid_t) -> SourceKitResponseValue {
        let inner = api.variant_dictionary_get_value(variant, key)
        return SourceKitResponseValue(api: api, keys: keys, variant: inner)
    }
    
    /// Get the raw string from a string variant
    public var stringValue: String? {
        guard type == .string else { return nil }
        guard let ptr = api.variant_string_get_ptr(variant) else { return nil }
        return String(cString: ptr)
    }
    
    /// Get array count if this is an array variant
    public var arrayCount: Int {
        guard type == .array else { return 0 }
        return api.variant_array_get_count(variant)
    }
    
    /// Get array element at index
    public func getArrayElement(at index: Int) -> SourceKitResponseValue {
        let element = api.variant_array_get_value(variant, index)
        return SourceKitResponseValue(api: api, keys: keys, variant: element)
    }
    
    /// Iterate over array elements
    public func forEachArrayElement(_ body: (SourceKitResponseValue) -> Void) {
        let count = arrayCount
        for i in 0..<count {
            body(getArrayElement(at: i))
        }
    }
}

// MARK: - Async Service

/// Async service for making SourceKit requests
/// Uses continuation-based bridging for async/await support
public actor SourceKitDService {
    private var api: SourceKitDAPI?
    private var keys: SourceKitDKeys { SourceKitDKeys.shared }
    private var isInitialized = false
    
    public init() {}
    
    /// Initialize the service, loading SourceKit if needed
    public func initialize() async throws {
        guard !isInitialized else { return }
        
        let loadedAPI = try await SourceKitDLoader.shared.load()
        keys.initialize(with: loadedAPI)
        self.api = loadedAPI
        self.isInitialized = true
    }
    
    /// Check if the service is available
    public func isAvailable() async -> Bool {
        return await SourceKitDLoader.shared.isAvailable()
    }
    
    /// Create a cursor info request builder
    public func createCursorInfoRequest() throws -> SourceKitRequestBuilder {
        guard let api = api else { throw SourceKitError.notLoaded }
        guard let requestType = keys.requestCursorInfo else {
            throw SourceKitError.missingRequiredKey("source.request.cursorinfo")
        }
        return SourceKitRequestBuilder(api: api, keys: keys, requestType: requestType)
    }
    
    /// Send a synchronous request (runs on background thread)
    public func sendSync(_ request: sourcekitd_request_t) async throws -> SKDResponse {
        guard let api = api else { throw SourceKitError.notLoaded }
        
        // Run sync request on background thread to not block actor
        // Note: sourcekitd_request_t is a type alias for UnsafeMutableRawPointer
        // We convert to Int and back to avoid Sendable issues - this is safe because
        // the pointer value is just an address that remains valid for the duration
        let requestBits = Int(bitPattern: request)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let requestPtr = UnsafeMutableRawPointer(bitPattern: requestBits) else {
                    continuation.resume(throwing: SourceKitError.invalidResponse)
                    return
                }
                guard let responsePtr = api.send_request_sync(requestPtr) else {
                    continuation.resume(throwing: SourceKitError.invalidResponse)
                    return
                }
                
                // Release the request now that we're done with it
                api.request_release(requestPtr)
                
                let response = SKDResponse(raw: responsePtr, api: api)
                
                if response.isError {
                    let kind = response.errorKind ?? .failed
                    let description = response.errorDescription ?? "Unknown error"
                    continuation.resume(throwing: SourceKitError.requestFailed(kind: kind, description: description))
                } else {
                    continuation.resume(returning: response)
                }
            }
        }
    }
    
    /// Parse a cursor info response into structured data
    /// Uses string-based parsing via response_description_copy for reliability
    public func parseCursorInfo(_ response: SKDResponse) -> CursorInfoResult {
        guard let description = response.description else {
            return CursorInfoResult()
        }
        
        return CursorInfoResult.parse(from: description)
    }
}

// MARK: - Response Parser

extension CursorInfoResult {
    /// Parse cursor info from a SourceKit response description string
    static func parse(from description: String) -> CursorInfoResult {
        var result = CursorInfoResult()
        
        // Parse key-value pairs from the response format
        // Format: key.name: value, or key.name: "string value"
        let lines = description.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip braces
            guard !trimmed.isEmpty && trimmed != "{" && trimmed != "}" else { continue }
            
            // Remove trailing comma
            let cleaned = trimmed.hasSuffix(",") ? String(trimmed.dropLast()) : trimmed
            
            // Split on first colon
            guard let colonIndex = cleaned.firstIndex(of: ":") else { continue }
            let key = String(cleaned[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            var value = String(cleaned[cleaned.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            
            // Remove quotes from string values
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            
            // Map to result fields
            switch key {
            case "key.name":
                result.name = value
            case "key.usr":
                result.usr = value
            case "key.typename":
                result.typeName = value
            case "key.kind":
                result.kind = value
            case "key.filepath":
                result.filePath = value
            case "key.line":
                result.line = Int(value)
            case "key.column":
                result.column = Int(value)
            case "key.modulename":
                result.moduleName = value
            case "key.is_system":
                result.isSystem = (value == "1" || value == "true")
            case "key.annotated_decl":
                result.annotatedDecl = value
            case "key.fully_annotated_decl":
                result.fullyAnnotatedDecl = value
            case "key.doc.full_as_xml":
                result.docFullAsXML = value
            default:
                break
            }
        }
        
        return result
    }
}

// MARK: - Result Types

/// Result of a cursor info request
/// Note: @unchecked Sendable because kindUID pointer is safe - it points to process-lifetime interned strings
public struct CursorInfoResult: @unchecked Sendable {
    public var name: String?
    public var usr: String?
    public var typeName: String?
    public var kind: String?
    /// The UID representing the symbol kind (internal use)
    /// Note: Safe to store as UIDs are interned for the process lifetime
    internal var kindUID: sourcekitd_uid_t?
    public var filePath: String?
    public var line: Int?
    public var column: Int?
    public var moduleName: String?
    public var isSystem: Bool = false
    public var annotatedDecl: String?
    public var fullyAnnotatedDecl: String?
    public var docFullAsXML: String?
    
    public init() {}
    
    /// Check if this result has meaningful data
    public var hasData: Bool {
        return name != nil || usr != nil || typeName != nil
    }
}

// MARK: - Convenience Extensions

extension SourceKitDService {
    
    /// Query cursor info at a specific location in a file
    public func cursorInfo(
        at offset: Int64,
        in filePath: String,
        sourceText: String? = nil,
        compilerArgs: [String] = []
    ) async throws -> CursorInfoResult {
        let builder = try createCursorInfoRequest()
        
        if let keySourceFile = keys.keySourceFile {
            builder.set(string: filePath, for: keySourceFile)
        }
        
        if let keyOffset = keys.keyOffset {
            builder.set(int64: offset, for: keyOffset)
        }
        
        if let sourceText = sourceText, let keySourceText = keys.keySourceText {
            builder.set(string: sourceText, for: keySourceText)
        }
        
        if !compilerArgs.isEmpty {
            builder.setCompilerArgs(compilerArgs)
        }
        
        let response = try await sendSync(builder.build())
        return parseCursorInfo(response)
    }
    
    /// Batch query cursor info at multiple locations
    public func batchCursorInfo(
        offsets: [Int64],
        in filePath: String,
        sourceText: String? = nil,
        compilerArgs: [String] = []
    ) async throws -> [Int64: CursorInfoResult] {
        var results: [Int64: CursorInfoResult] = [:]
        
        // Process in batches to avoid overwhelming SourceKit
        let batchSize = 10
        for batch in offsets.chunked(into: batchSize) {
            try await withThrowingTaskGroup(of: (Int64, CursorInfoResult).self) { group in
                for offset in batch {
                    group.addTask {
                        let result = try await self.cursorInfo(
                            at: offset,
                            in: filePath,
                            sourceText: sourceText,
                            compilerArgs: compilerArgs
                        )
                        return (offset, result)
                    }
                }
                
                for try await (offset, result) in group {
                    results[offset] = result
                }
            }
        }
        
        return results
    }
}

// MARK: - Array Chunking Helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
