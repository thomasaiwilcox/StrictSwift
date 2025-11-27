import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - SourceKit C API Type Definitions

/// Opaque pointer types matching SourceKit's C API
public typealias sourcekitd_object_t = UnsafeMutableRawPointer
public typealias sourcekitd_response_t = UnsafeMutableRawPointer
public typealias sourcekitd_request_t = UnsafeMutableRawPointer
public typealias sourcekitd_uid_t = UnsafeMutableRawPointer
public typealias sourcekitd_variant_t = UnsafeMutableRawPointer

/// Callback type for async responses
public typealias sourcekitd_response_receiver_t = @convention(c) (sourcekitd_response_t?) -> Void

/// Error codes from SourceKit
public struct SourceKitDErrorKind: RawRepresentable, Equatable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    
    public static let connectionInterrupted = SourceKitDErrorKind(rawValue: 1)
    public static let invalid = SourceKitDErrorKind(rawValue: 2)
    public static let failed = SourceKitDErrorKind(rawValue: 3)
    public static let cancelled = SourceKitDErrorKind(rawValue: 4)
}

// MARK: - Function Pointer Types

/// Initialize SourceKit - must be called before any other functions
typealias sourcekitd_initialize_func = @convention(c) () -> Void

/// Shutdown SourceKit
typealias sourcekitd_shutdown_func = @convention(c) () -> Void

/// UID operations
typealias sourcekitd_uid_get_from_cstr_func = @convention(c) (UnsafePointer<CChar>) -> sourcekitd_uid_t?
typealias sourcekitd_uid_get_string_ptr_func = @convention(c) (sourcekitd_uid_t) -> UnsafePointer<CChar>?

/// Request dictionary creation
typealias sourcekitd_request_dictionary_create_func = @convention(c) (
    UnsafePointer<sourcekitd_uid_t?>?,
    UnsafePointer<sourcekitd_object_t?>?,
    Int
) -> sourcekitd_request_t?

/// Request dictionary set operations
typealias sourcekitd_request_dictionary_set_uid_func = @convention(c) (
    sourcekitd_request_t, sourcekitd_uid_t, sourcekitd_uid_t
) -> Void

typealias sourcekitd_request_dictionary_set_string_func = @convention(c) (
    sourcekitd_request_t, sourcekitd_uid_t, UnsafePointer<CChar>
) -> Void

typealias sourcekitd_request_dictionary_set_int64_func = @convention(c) (
    sourcekitd_request_t, sourcekitd_uid_t, Int64
) -> Void

typealias sourcekitd_request_dictionary_set_stringbuf_func = @convention(c) (
    sourcekitd_request_t, sourcekitd_uid_t, UnsafePointer<CChar>, Int
) -> Void

typealias sourcekitd_request_dictionary_set_value_func = @convention(c) (
    sourcekitd_request_t, sourcekitd_uid_t, sourcekitd_object_t
) -> Void

/// Request array creation
typealias sourcekitd_request_array_create_func = @convention(c) (
    UnsafePointer<sourcekitd_object_t?>?, Int
) -> sourcekitd_request_t?

typealias sourcekitd_request_array_set_string_func = @convention(c) (
    sourcekitd_request_t, Int, UnsafePointer<CChar>
) -> Void

/// String creation for array elements
typealias sourcekitd_request_string_create_func = @convention(c) (
    UnsafePointer<CChar>
) -> sourcekitd_object_t?

/// Request lifecycle
typealias sourcekitd_request_release_func = @convention(c) (sourcekitd_request_t) -> Void

/// Synchronous request sending
typealias sourcekitd_send_request_sync_func = @convention(c) (sourcekitd_request_t) -> sourcekitd_response_t?

/// Asynchronous request sending
typealias sourcekitd_send_request_func = @convention(c) (
    sourcekitd_request_t,
    UnsafeMutableRawPointer?, // out_handle (can be NULL)
    @escaping sourcekitd_response_receiver_t
) -> Void

/// Cancel async request
typealias sourcekitd_cancel_request_func = @convention(c) (UnsafeMutableRawPointer) -> Void

/// Response error checking
typealias sourcekitd_response_is_error_func = @convention(c) (sourcekitd_response_t) -> Bool
typealias sourcekitd_response_error_get_kind_func = @convention(c) (sourcekitd_response_t) -> UInt32
typealias sourcekitd_response_error_get_description_func = @convention(c) (sourcekitd_response_t) -> UnsafePointer<CChar>?

/// Response lifecycle
typealias sourcekitd_response_dispose_func = @convention(c) (sourcekitd_response_t) -> Void

/// Response description (returns allocated string that must be freed)
typealias sourcekitd_response_description_copy_func = @convention(c) (sourcekitd_response_t) -> UnsafeMutablePointer<CChar>?

/// Response dictionary access
typealias sourcekitd_response_get_value_func = @convention(c) (sourcekitd_response_t) -> sourcekitd_variant_t

/// Variant type checking
typealias sourcekitd_variant_get_type_func = @convention(c) (sourcekitd_variant_t) -> UInt32

/// Variant dictionary access
typealias sourcekitd_variant_dictionary_get_value_func = @convention(c) (
    sourcekitd_variant_t, sourcekitd_uid_t
) -> sourcekitd_variant_t

typealias sourcekitd_variant_dictionary_get_string_func = @convention(c) (
    sourcekitd_variant_t, sourcekitd_uid_t
) -> UnsafePointer<CChar>?

typealias sourcekitd_variant_dictionary_get_int64_func = @convention(c) (
    sourcekitd_variant_t, sourcekitd_uid_t
) -> Int64

typealias sourcekitd_variant_dictionary_get_bool_func = @convention(c) (
    sourcekitd_variant_t, sourcekitd_uid_t
) -> Bool

typealias sourcekitd_variant_dictionary_get_uid_func = @convention(c) (
    sourcekitd_variant_t, sourcekitd_uid_t
) -> sourcekitd_uid_t?

/// Variant string access
typealias sourcekitd_variant_string_get_ptr_func = @convention(c) (sourcekitd_variant_t) -> UnsafePointer<CChar>?
typealias sourcekitd_variant_string_get_length_func = @convention(c) (sourcekitd_variant_t) -> Int

/// Variant array access
typealias sourcekitd_variant_array_get_count_func = @convention(c) (sourcekitd_variant_t) -> Int
typealias sourcekitd_variant_array_get_value_func = @convention(c) (sourcekitd_variant_t, Int) -> sourcekitd_variant_t

// MARK: - Variant Type Constants

public struct SourceKitDVariantType: RawRepresentable, Equatable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    
    public static let null = SourceKitDVariantType(rawValue: 0)
    public static let dictionary = SourceKitDVariantType(rawValue: 1)
    public static let array = SourceKitDVariantType(rawValue: 2)
    public static let int64 = SourceKitDVariantType(rawValue: 3)
    public static let string = SourceKitDVariantType(rawValue: 4)
    public static let uid = SourceKitDVariantType(rawValue: 5)
    public static let bool = SourceKitDVariantType(rawValue: 6)
    public static let data = SourceKitDVariantType(rawValue: 7)
}

// MARK: - SourceKitD API Container

/// Container holding all loaded SourceKit function pointers
/// SAFETY: @unchecked Sendable is safe because all function pointers are immutable
/// after initialization - they point to C functions loaded from the SourceKit dylib.
public final class SourceKitDAPI: @unchecked Sendable {
    // Lifecycle
    let initialize: sourcekitd_initialize_func
    let shutdown: sourcekitd_shutdown_func
    
    // UIDs
    let uid_get_from_cstr: sourcekitd_uid_get_from_cstr_func
    let uid_get_string_ptr: sourcekitd_uid_get_string_ptr_func
    
    // Request creation
    let request_dictionary_create: sourcekitd_request_dictionary_create_func
    let request_dictionary_set_uid: sourcekitd_request_dictionary_set_uid_func
    let request_dictionary_set_string: sourcekitd_request_dictionary_set_string_func
    let request_dictionary_set_int64: sourcekitd_request_dictionary_set_int64_func
    let request_dictionary_set_stringbuf: sourcekitd_request_dictionary_set_stringbuf_func
    let request_dictionary_set_value: sourcekitd_request_dictionary_set_value_func
    let request_array_create: sourcekitd_request_array_create_func
    let request_array_set_string: sourcekitd_request_array_set_string_func
    let request_string_create: sourcekitd_request_string_create_func
    let request_release: sourcekitd_request_release_func
    
    // Request sending
    let send_request_sync: sourcekitd_send_request_sync_func
    let send_request: sourcekitd_send_request_func
    let cancel_request: sourcekitd_cancel_request_func
    
    // Response handling
    let response_is_error: sourcekitd_response_is_error_func
    let response_error_get_kind: sourcekitd_response_error_get_kind_func
    let response_error_get_description: sourcekitd_response_error_get_description_func
    let response_dispose: sourcekitd_response_dispose_func
    let response_description_copy: sourcekitd_response_description_copy_func
    let response_get_value: sourcekitd_response_get_value_func
    
    // Variant access
    let variant_get_type: sourcekitd_variant_get_type_func
    let variant_dictionary_get_value: sourcekitd_variant_dictionary_get_value_func
    let variant_dictionary_get_string: sourcekitd_variant_dictionary_get_string_func
    let variant_dictionary_get_int64: sourcekitd_variant_dictionary_get_int64_func
    let variant_dictionary_get_bool: sourcekitd_variant_dictionary_get_bool_func
    let variant_dictionary_get_uid: sourcekitd_variant_dictionary_get_uid_func
    let variant_string_get_ptr: sourcekitd_variant_string_get_ptr_func
    let variant_string_get_length: sourcekitd_variant_string_get_length_func
    let variant_array_get_count: sourcekitd_variant_array_get_count_func
    let variant_array_get_value: sourcekitd_variant_array_get_value_func
    
    init(
        initialize: @escaping sourcekitd_initialize_func,
        shutdown: @escaping sourcekitd_shutdown_func,
        uid_get_from_cstr: @escaping sourcekitd_uid_get_from_cstr_func,
        uid_get_string_ptr: @escaping sourcekitd_uid_get_string_ptr_func,
        request_dictionary_create: @escaping sourcekitd_request_dictionary_create_func,
        request_dictionary_set_uid: @escaping sourcekitd_request_dictionary_set_uid_func,
        request_dictionary_set_string: @escaping sourcekitd_request_dictionary_set_string_func,
        request_dictionary_set_int64: @escaping sourcekitd_request_dictionary_set_int64_func,
        request_dictionary_set_stringbuf: @escaping sourcekitd_request_dictionary_set_stringbuf_func,
        request_dictionary_set_value: @escaping sourcekitd_request_dictionary_set_value_func,
        request_array_create: @escaping sourcekitd_request_array_create_func,
        request_array_set_string: @escaping sourcekitd_request_array_set_string_func,
        request_string_create: @escaping sourcekitd_request_string_create_func,
        request_release: @escaping sourcekitd_request_release_func,
        send_request_sync: @escaping sourcekitd_send_request_sync_func,
        send_request: @escaping sourcekitd_send_request_func,
        cancel_request: @escaping sourcekitd_cancel_request_func,
        response_is_error: @escaping sourcekitd_response_is_error_func,
        response_error_get_kind: @escaping sourcekitd_response_error_get_kind_func,
        response_error_get_description: @escaping sourcekitd_response_error_get_description_func,
        response_dispose: @escaping sourcekitd_response_dispose_func,
        response_description_copy: @escaping sourcekitd_response_description_copy_func,
        response_get_value: @escaping sourcekitd_response_get_value_func,
        variant_get_type: @escaping sourcekitd_variant_get_type_func,
        variant_dictionary_get_value: @escaping sourcekitd_variant_dictionary_get_value_func,
        variant_dictionary_get_string: @escaping sourcekitd_variant_dictionary_get_string_func,
        variant_dictionary_get_int64: @escaping sourcekitd_variant_dictionary_get_int64_func,
        variant_dictionary_get_bool: @escaping sourcekitd_variant_dictionary_get_bool_func,
        variant_dictionary_get_uid: @escaping sourcekitd_variant_dictionary_get_uid_func,
        variant_string_get_ptr: @escaping sourcekitd_variant_string_get_ptr_func,
        variant_string_get_length: @escaping sourcekitd_variant_string_get_length_func,
        variant_array_get_count: @escaping sourcekitd_variant_array_get_count_func,
        variant_array_get_value: @escaping sourcekitd_variant_array_get_value_func
    ) {
        self.initialize = initialize
        self.shutdown = shutdown
        self.uid_get_from_cstr = uid_get_from_cstr
        self.uid_get_string_ptr = uid_get_string_ptr
        self.request_dictionary_create = request_dictionary_create
        self.request_dictionary_set_uid = request_dictionary_set_uid
        self.request_dictionary_set_string = request_dictionary_set_string
        self.request_dictionary_set_int64 = request_dictionary_set_int64
        self.request_dictionary_set_stringbuf = request_dictionary_set_stringbuf
        self.request_dictionary_set_value = request_dictionary_set_value
        self.request_array_create = request_array_create
        self.request_array_set_string = request_array_set_string
        self.request_string_create = request_string_create
        self.request_release = request_release
        self.send_request_sync = send_request_sync
        self.send_request = send_request
        self.cancel_request = cancel_request
        self.response_is_error = response_is_error
        self.response_error_get_kind = response_error_get_kind
        self.response_error_get_description = response_error_get_description
        self.response_dispose = response_dispose
        self.response_description_copy = response_description_copy
        self.response_get_value = response_get_value
        self.variant_get_type = variant_get_type
        self.variant_dictionary_get_value = variant_dictionary_get_value
        self.variant_dictionary_get_string = variant_dictionary_get_string
        self.variant_dictionary_get_int64 = variant_dictionary_get_int64
        self.variant_dictionary_get_bool = variant_dictionary_get_bool
        self.variant_dictionary_get_uid = variant_dictionary_get_uid
        self.variant_string_get_ptr = variant_string_get_ptr
        self.variant_string_get_length = variant_string_get_length
        self.variant_array_get_count = variant_array_get_count
        self.variant_array_get_value = variant_array_get_value
    }
}

// MARK: - SourceKitD Loader

/// Errors that can occur when loading SourceKit
public enum SourceKitDLoadError: Error, Sendable {
    case libraryNotFound(searchPaths: [String])
    case symbolNotFound(name: String)
    case initializationFailed
    case alreadyLoaded
}

/// Singleton loader for SourceKit dynamic library
/// Thread-safe via actor isolation
public actor SourceKitDLoader {
    
    /// Shared instance
    public static let shared = SourceKitDLoader()
    
    /// The loaded API, nil if not yet loaded
    private var api: SourceKitDAPI?
    
    /// Handle to the loaded dynamic library
    private var libraryHandle: UnsafeMutableRawPointer?
    
    /// Path where library was loaded from
    private var loadedPath: String?
    
    /// Whether initialization has been called
    private var isInitialized = false
    
    private init() {}
    
    deinit {
        // Note: We don't shutdown here because this is a singleton
        // and should live for the process lifetime
    }
    
    // MARK: - Public API
    
    /// Load SourceKit if not already loaded. Returns the API interface.
    public func load() throws -> SourceKitDAPI {
        if let api = api {
            return api
        }
        
        let (handle, path) = try loadLibrary()
        let loadedAPI = try loadSymbols(from: handle)
        
        // Initialize SourceKit
        loadedAPI.initialize()
        
        self.libraryHandle = handle
        self.loadedPath = path
        self.api = loadedAPI
        self.isInitialized = true
        
        return loadedAPI
    }
    
    /// Check if SourceKit is available without loading it
    public func isAvailable() -> Bool {
        if api != nil { return true }
        
        for path in librarySearchPaths() {
            if FileManager.default.fileExists(atPath: path) {
                // Try to actually open it to verify it's loadable
                if let handle = dlopen(path, RTLD_LAZY) {
                    dlclose(handle)
                    return true
                }
            }
        }
        return false
    }
    
    /// Get the path where SourceKit was loaded from, if loaded
    public func getLoadedPath() -> String? {
        return loadedPath
    }
    
    /// Get the API if already loaded, nil otherwise
    public func getAPI() -> SourceKitDAPI? {
        return api
    }
    
    /// Shutdown SourceKit (call before process exit if needed)
    public func shutdown() {
        guard isInitialized, let api = api else { return }
        api.shutdown()
        isInitialized = false
        
        if let handle = libraryHandle {
            dlclose(handle)
            libraryHandle = nil
        }
        
        self.api = nil
        self.loadedPath = nil
    }
    
    // MARK: - Private Loading
    
    private func librarySearchPaths() -> [String] {
        var paths: [String] = []
        
        #if os(macOS)
        // Check TOOLCHAINS environment variable first
        if let toolchain = ProcessInfo.processInfo.environment["TOOLCHAINS"] {
            paths.append("/Library/Developer/Toolchains/\(toolchain).xctoolchain/usr/lib/sourcekitd.framework/sourcekitd")
        }
        
        // Xcode default locations
        paths.append(contentsOf: [
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/sourcekitd",
            "/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/sourcekitd"
        ])
        
        // Developer directory from xcode-select
        if let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
            paths.append("\(developerDir)/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/sourcekitd")
        }
        
        #elseif os(Linux)
        // Swift toolchain on Linux
        paths.append(contentsOf: [
            "/usr/lib/libsourcekitdInProc.so",
            "/usr/local/lib/libsourcekitdInProc.so"
        ])
        
        // swiftenv paths
        let home = NSHomeDirectory()
        paths.append("\(home)/.swiftenv/versions/current/usr/lib/libsourcekitdInProc.so")
        
        // Check SWIFT_TOOLCHAIN environment variable
        if let toolchain = ProcessInfo.processInfo.environment["SWIFT_TOOLCHAIN"] {
            paths.append("\(toolchain)/usr/lib/libsourcekitdInProc.so")
        }
        #endif
        
        return paths
    }
    
    private func loadLibrary() throws -> (UnsafeMutableRawPointer, String) {
        let searchPaths = librarySearchPaths()
        
        for path in searchPaths {
            if let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) {
                return (handle, path)
            }
        }
        
        throw SourceKitDLoadError.libraryNotFound(searchPaths: searchPaths)
    }
    
    private func loadSymbols(from handle: UnsafeMutableRawPointer) throws -> SourceKitDAPI {
        func loadSymbol<T>(_ name: String) throws -> T {
            guard let sym = dlsym(handle, name) else {
                throw SourceKitDLoadError.symbolNotFound(name: name)
            }
            return unsafeBitCast(sym, to: T.self)
        }
        
        return try SourceKitDAPI(
            initialize: loadSymbol("sourcekitd_initialize"),
            shutdown: loadSymbol("sourcekitd_shutdown"),
            uid_get_from_cstr: loadSymbol("sourcekitd_uid_get_from_cstr"),
            uid_get_string_ptr: loadSymbol("sourcekitd_uid_get_string_ptr"),
            request_dictionary_create: loadSymbol("sourcekitd_request_dictionary_create"),
            request_dictionary_set_uid: loadSymbol("sourcekitd_request_dictionary_set_uid"),
            request_dictionary_set_string: loadSymbol("sourcekitd_request_dictionary_set_string"),
            request_dictionary_set_int64: loadSymbol("sourcekitd_request_dictionary_set_int64"),
            request_dictionary_set_stringbuf: loadSymbol("sourcekitd_request_dictionary_set_stringbuf"),
            request_dictionary_set_value: loadSymbol("sourcekitd_request_dictionary_set_value"),
            request_array_create: loadSymbol("sourcekitd_request_array_create"),
            request_array_set_string: loadSymbol("sourcekitd_request_array_set_string"),
            request_string_create: loadSymbol("sourcekitd_request_string_create"),
            request_release: loadSymbol("sourcekitd_request_release"),
            send_request_sync: loadSymbol("sourcekitd_send_request_sync"),
            send_request: loadSymbol("sourcekitd_send_request"),
            cancel_request: loadSymbol("sourcekitd_cancel_request"),
            response_is_error: loadSymbol("sourcekitd_response_is_error"),
            response_error_get_kind: loadSymbol("sourcekitd_response_error_get_kind"),
            response_error_get_description: loadSymbol("sourcekitd_response_error_get_description"),
            response_dispose: loadSymbol("sourcekitd_response_dispose"),
            response_description_copy: loadSymbol("sourcekitd_response_description_copy"),
            response_get_value: loadSymbol("sourcekitd_response_get_value"),
            variant_get_type: loadSymbol("sourcekitd_variant_get_type"),
            variant_dictionary_get_value: loadSymbol("sourcekitd_variant_dictionary_get_value"),
            variant_dictionary_get_string: loadSymbol("sourcekitd_variant_dictionary_get_string"),
            variant_dictionary_get_int64: loadSymbol("sourcekitd_variant_dictionary_get_int64"),
            variant_dictionary_get_bool: loadSymbol("sourcekitd_variant_dictionary_get_bool"),
            variant_dictionary_get_uid: loadSymbol("sourcekitd_variant_dictionary_get_uid"),
            variant_string_get_ptr: loadSymbol("sourcekitd_variant_string_get_ptr"),
            variant_string_get_length: loadSymbol("sourcekitd_variant_string_get_length"),
            variant_array_get_count: loadSymbol("sourcekitd_variant_array_get_count"),
            variant_array_get_value: loadSymbol("sourcekitd_variant_array_get_value")
        )
    }
}

// MARK: - RAII Wrapper Types

/// RAII wrapper for SourceKit request objects
/// Automatically releases the request when deallocated
/// SAFETY: @unchecked Sendable is safe because raw is a C pointer that is immutable
/// after initialization and is only used for cleanup in deinit.
public final class SKDRequest: @unchecked Sendable {
    public let raw: sourcekitd_request_t
    private let api: SourceKitDAPI
    
    public init(raw: sourcekitd_request_t, api: SourceKitDAPI) {
        self.raw = raw
        self.api = api
    }
    
    deinit {
        api.request_release(raw)
    }
}

/// RAII wrapper for SourceKit response objects
/// Automatically disposes the response when deallocated
/// SAFETY: @unchecked Sendable is safe because raw is a C pointer that is immutable
/// after initialization and is only used for reading and cleanup in deinit.
public final class SKDResponse: @unchecked Sendable {
    public let raw: sourcekitd_response_t
    private let api: SourceKitDAPI
    
    public init(raw: sourcekitd_response_t, api: SourceKitDAPI) {
        self.raw = raw
        self.api = api
    }
    
    deinit {
        api.response_dispose(raw)
    }
    
    /// Check if this response is an error
    public var isError: Bool {
        return api.response_is_error(raw)
    }
    
    /// Get error kind if this is an error response
    public var errorKind: SourceKitDErrorKind? {
        guard isError else { return nil }
        return SourceKitDErrorKind(rawValue: api.response_error_get_kind(raw))
    }
    
    /// Get error description if this is an error response
    public var errorDescription: String? {
        guard isError else { return nil }
        guard let ptr = api.response_error_get_description(raw) else { return nil }
        return String(cString: ptr)
    }
    
    /// Get the root value of the response
    public var value: sourcekitd_variant_t {
        return api.response_get_value(raw)
    }
    
    /// Get the response as a formatted description string
    /// This is the reliable way to read response data without variant type issues
    public var description: String? {
        guard let ptr = api.response_description_copy(raw) else { return nil }
        defer { free(ptr) }
        return String(cString: ptr)
    }
}
