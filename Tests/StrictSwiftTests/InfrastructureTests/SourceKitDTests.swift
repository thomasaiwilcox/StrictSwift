import XCTest
@testable import StrictSwiftCore

/// Tests for the SourceKit C API integration
final class SourceKitDTests: XCTestCase {
    
    // MARK: - Loader Tests
    
    func testSourceKitDLoaderIsAvailable() async throws {
        // Test that we can detect if SourceKit is available
        let isAvailable = await SourceKitDLoader.shared.isAvailable()
        
        // On macOS with Xcode, this should be true
        #if os(macOS)
        XCTAssertTrue(isAvailable, "SourceKit should be available on macOS with Xcode")
        #endif
    }
    
    func testSourceKitDLoaderCanLoad() async throws {
        // Test that we can load the API
        do {
            let api = try await SourceKitDLoader.shared.load()
            XCTAssertNotNil(api)
            
            // Verify the loaded path
            let path = await SourceKitDLoader.shared.getLoadedPath()
            XCTAssertNotNil(path, "Should have a loaded path after loading")
            
            #if os(macOS)
            XCTAssertTrue(path?.contains("sourcekitd") == true, "Path should contain 'sourcekitd'")
            #elseif os(Linux)
            XCTAssertTrue(path?.contains("libsourcekitdInProc") == true, "Path should contain 'libsourcekitdInProc'")
            #endif
        } catch SourceKitDLoadError.libraryNotFound {
            // Skip if SourceKit is not available
            throw XCTSkip("SourceKit not available on this system")
        }
    }
    
    // MARK: - Keys Tests
    
    func testSourceKitDKeysInitialization() async throws {
        do {
            let api = try await SourceKitDLoader.shared.load()
            let keys = SourceKitDKeys.shared
            keys.initialize(with: api)
            
            // Test that we can get UIDs for common keys
            XCTAssertNotNil(keys.keyRequest, "keyRequest should be resolvable")
            XCTAssertNotNil(keys.keySourceFile, "keySourceFile should be resolvable")
            XCTAssertNotNil(keys.keyOffset, "keyOffset should be resolvable")
            XCTAssertNotNil(keys.requestCursorInfo, "requestCursorInfo should be resolvable")
        } catch SourceKitDLoadError.libraryNotFound {
            throw XCTSkip("SourceKit not available on this system")
        }
    }
    
    func testSourceKitDKeysUIDStrings() async throws {
        do {
            let api = try await SourceKitDLoader.shared.load()
            let keys = SourceKitDKeys.shared
            keys.initialize(with: api)
            
            // Test round-trip: string -> UID -> string
            if let uid = keys.uid("key.request") {
                let str = keys.string(from: uid)
                XCTAssertEqual(str, "key.request", "UID string should match original")
            } else {
                XCTFail("Could not resolve 'key.request' to a UID")
            }
        } catch SourceKitDLoadError.libraryNotFound {
            throw XCTSkip("SourceKit not available on this system")
        }
    }
    
    // MARK: - Service Tests
    
    func testSourceKitDServiceInitialization() async throws {
        do {
            // Check if we can load first
            _ = try await SourceKitDLoader.shared.load()
            
            let service = SourceKitDService()
            
            // Should be able to initialize without error
            try await service.initialize()
            
            // Should be available after initialization
            let available = await service.isAvailable()
            XCTAssertTrue(available, "Service should be available after initialization")
        } catch SourceKitDLoadError.libraryNotFound {
            throw XCTSkip("SourceKit not available on this system")
        }
    }
    
    // MARK: - Mode Detection Tests
    
    func testSemanticModeDetection() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceKitDTest-\(UUID().uuidString)")
        
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create a Package.swift to simulate a Swift package
        let packageSwift = """
        // swift-tools-version: 5.9
        import PackageDescription
        
        let package = Package(
            name: "TestPackage",
            targets: [
                .executableTarget(name: "TestPackage")
            ]
        )
        """
        try? packageSwift.write(
            to: tempDir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        
        let detector = SemanticCapabilityDetector(projectRoot: tempDir)
        let capabilities = detector.detect()
        
        // With SourceKit available, we should get hybrid mode at minimum
        #if os(macOS)
        XCTAssertTrue(capabilities.sourceKitAvailable, "SourceKit should be detected on macOS")
        
        // Without .build directory, best mode should be hybrid
        XCTAssertEqual(capabilities.bestAvailableMode, SemanticMode.hybrid, 
                       "Without build artifacts, best mode should be hybrid")
        #endif
        
        // It should detect this as a Swift package
        XCTAssertTrue(capabilities.isSwiftPackage, "Should detect as Swift package")
    }
    
    // MARK: - Client Tests
    
    func testSourceKitClientCreation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceKitClientTest-\(UUID().uuidString)")
        
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let detector = SemanticCapabilityDetector(projectRoot: tempDir)
        let capabilities = detector.detect()
        
        let client = try SourceKitClient.create(for: tempDir, capabilities: capabilities)
        
        #if os(macOS)
        XCTAssertNotNil(client, "Should be able to create client on macOS")
        #endif
    }
}
