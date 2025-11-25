import Foundation
#if canImport(Darwin)
import CoreFoundation
#endif

// MARK: - JSON Type

/// A simple JSON value type for LSP communication
enum JSON: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])
    
    subscript(key: String) -> JSON? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }
    
    subscript(index: Int) -> JSON? {
        guard case .array(let arr) = self, index < arr.count else { return nil }
        return arr[index]
    }
}

// MARK: - JSON Encoding/Decoding

extension JSON {
    static func parse(_ data: Data) throws -> JSON {
        let object = try JSONSerialization.jsonObject(with: data)
        return try fromAny(object)
    }
    
    private static func fromAny(_ value: Any) throws -> JSON {
        // Handle NSNull first
        if value is NSNull {
            return .null
        }
        
        // Handle strings
        if let string = value as? String {
            return .string(string)
        }
        
        // Handle arrays
        if let array = value as? [Any] {
            return .array(try array.map { try fromAny($0) })
        }
        
        // Handle dictionaries
        if let dict = value as? [String: Any] {
            return .object(try dict.mapValues { try fromAny($0) })
        }
        
        // Handle numbers - check type carefully
        // NSNumber wraps both booleans and numbers
        if let number = value as? NSNumber {
            #if canImport(Darwin)
            // CFBoolean has a specific type ID that we can check
            let boolID = CFBooleanGetTypeID()
            let numID = CFGetTypeID(number as CFTypeRef)
            if numID == boolID {
                return .bool(number.boolValue)
            }
            #else
            // On Linux, we treat everything as number to avoid CoreFoundation dependency issues
            // This is a compromise for build stability
            #endif
            return .number(number.doubleValue)
        }
        
        throw JSONError.unsupportedType
    }
    
    func toData() throws -> Data {
        let object = toAny()
        return try JSONSerialization.data(withJSONObject: object)
    }
    
    func toAny() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .number(let n):
            return n
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map { $0.toAny() }
        case .object(let dict):
            return dict.mapValues { $0.toAny() }
        }
    }
}

enum JSONError: Error {
    case unsupportedType
    case invalidJSON
}

// MARK: - Request ID

/// JSON-RPC request identifier
enum RequestID: Sendable, Equatable {
    case number(Int)
    case string(String)
    
    init?(json: JSON?) {
        guard let json = json else { return nil }
        switch json {
        case .number(let n):
            self = .number(Int(n))
        case .string(let s):
            self = .string(s)
        default:
            return nil
        }
    }
    
    var json: JSON {
        switch self {
        case .number(let n): return .number(Double(n))
        case .string(let s): return .string(s)
        }
    }
}

// MARK: - JSON-RPC Message

/// Represents a JSON-RPC 2.0 message
enum JSONRPCMessage: Sendable {
    case request(id: RequestID, method: String, params: JSON?)
    case notification(method: String, params: JSON?)
    case response(id: RequestID?, result: JSON?, error: JSON?)
    
    static func parse(_ json: JSON) throws -> JSONRPCMessage {
        guard case .object(let obj) = json else {
            throw JSONRPCError.invalidMessage
        }
        
        // Check for method (request or notification)
        if case .string(let method) = obj["method"] {
            let params = obj["params"]
            
            // If id is present, it's a request; otherwise notification
            if let id = RequestID(json: obj["id"]) {
                return .request(id: id, method: method, params: params)
            } else {
                return .notification(method: method, params: params)
            }
        }
        
        // Otherwise it's a response
        let id = RequestID(json: obj["id"])
        let result = obj["result"]
        let error = obj["error"]
        return .response(id: id, result: result, error: error)
    }
}

enum JSONRPCError: Error {
    case invalidMessage
    case invalidContentLength
    case readError
    case writeError
}

// MARK: - JSON-RPC Transport

/// Handles JSON-RPC message transport over stdin/stdout
actor JSONRPCTransport {
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()
    private var isShutdown = false
    
    init(input: FileHandle, output: FileHandle) {
        self.input = input
        self.output = output
    }
    
    /// Mark the transport as shut down to prevent further writes
    func shutdown() {
        isShutdown = true
    }
    
    // MARK: - Reading
    
    func readMessage() async throws -> JSONRPCMessage? {
        // Read headers
        var headers: [String: String] = [:]
        
        while true {
            guard let line = try await readLine() else {
                return nil
            }
            
            if line.isEmpty {
                // Empty line signals end of headers
                break
            }
            
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        guard let contentLengthStr = headers["Content-Length"],
              let contentLength = Int(contentLengthStr) else {
            throw JSONRPCError.invalidContentLength
        }
        
        // Read body
        let body = try await readBytes(count: contentLength)
        let json = try JSON.parse(body)
        return try JSONRPCMessage.parse(json)
    }
    
    private func readLine() async throws -> String? {
        while true {
            // Check if we have a complete line in the buffer
            if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[..<newlineIndex]
                buffer = Data(buffer[(newlineIndex + 1)...])
                
                // Remove CR if present
                var line = String(decoding: lineData, as: UTF8.self)
                if line.hasSuffix("\r") {
                    line.removeLast()
                }
                return line
            }
            
            // Read more data
            let chunk = input.availableData
            if chunk.isEmpty {
                // EOF or error
                if buffer.isEmpty {
                    return nil
                }
                // Return remaining data as last line
                let line = String(decoding: buffer, as: UTF8.self)
                buffer = Data()
                return line
            }
            buffer.append(chunk)
        }
    }
    
    private func readBytes(count: Int) async throws -> Data {
        while buffer.count < count {
            let chunk = input.availableData
            if chunk.isEmpty {
                throw JSONRPCError.readError
            }
            buffer.append(chunk)
        }
        
        let data = Data(buffer[..<count])
        buffer = Data(buffer[count...])
        return data
    }
    
    // MARK: - Writing
    
    func sendResponse(id: RequestID, result: JSON) async throws {
        let message: JSON = .object([
            "jsonrpc": .string("2.0"),
            "id": id.json,
            "result": result
        ])
        try await writeMessage(message)
    }
    
    func sendError(id: RequestID, code: Int, message: String, data: JSON? = nil) async throws {
        var error: [String: JSON] = [
            "code": .number(Double(code)),
            "message": .string(message)
        ]
        if let data = data {
            error["data"] = data
        }
        
        let response: JSON = .object([
            "jsonrpc": .string("2.0"),
            "id": id.json,
            "error": .object(error)
        ])
        try await writeMessage(response)
    }
    
    func sendNotification(method: String, params: JSON) async throws {
        let message: JSON = .object([
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": params
        ])
        try await writeMessage(message)
    }
    
    private func writeMessage(_ json: JSON) async throws {
        // Don't write if shutdown has been requested
        guard !isShutdown else {
            return
        }
        
        let body = try json.toData()
        let header = "Content-Length: \(body.count)\r\n\r\n"
        
        guard let headerData = header.data(using: .utf8) else {
            throw JSONRPCError.writeError
        }
        
        // Use do-catch to handle write errors gracefully (e.g., broken pipe)
        do {
            try output.write(contentsOf: headerData)
            try output.write(contentsOf: body)
        } catch {
            // Stream might be closed - this is okay during shutdown
        }
    }
}
