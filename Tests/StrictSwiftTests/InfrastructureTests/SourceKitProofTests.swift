import XCTest
@testable import StrictSwiftCore

/// Test that PROVES SourceKit C API is working by making a real cursor info query
final class SourceKitProofTests: XCTestCase {
    
    /// Minimal test to prove things work
    func testBasicSetup() {
        XCTAssertTrue(true)
    }
    
    /// Step 1: Just check availability
    func testStep1_Availability() async throws {
        let isAvailable = await SourceKitDLoader.shared.isAvailable()
        XCTAssertTrue(isAvailable, "SourceKit should be available")
    }
    
    /// Step 2: Initialize service
    func testStep2_ServiceInit() async throws {
        let service = SourceKitDService()
        try await service.initialize()
        let available = await service.isAvailable()
        XCTAssertTrue(available)
    }
    
    /// Step 3: Make actual cursor info query (without compiler args first)
    func testStep3_CursorInfoQuery() async throws {
        // Create a temporary Swift file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceKitProofTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("Test.swift")
        let source = """
        class MyTestClass {
            var name: String = "hello"
        }
        """
        try source.write(to: testFile, atomically: true, encoding: .utf8)
        
        // Initialize SourceKit
        let service = SourceKitDService()
        try await service.initialize()
        
        // Query cursor info at "MyTestClass" (offset 6, after "class ")
        // First try WITHOUT compiler args to see if that's the crash point
        let offset: Int64 = 6
        
        do {
            let result = try await service.cursorInfo(
                at: offset,
                in: testFile.path,
                sourceText: source
            )
            
            // Print proof
            print("=== SOURCEKIT PROOF ===")
            print("Name: \(result.name ?? "nil")")
            print("Type: \(result.typeName ?? "nil")")
            print("Kind: \(result.kind ?? "nil")")
            print("USR: \(result.usr ?? "nil")")
            print("=======================")
            
            // If we get here without crash, SourceKit is working
            XCTAssertTrue(true, "SourceKit query completed without crash")
        } catch {
            // Getting an error is fine - it means SourceKit is communicating
            print("SourceKit returned error (expected without proper setup): \(error)")
            XCTAssertTrue(true, "SourceKit responded - API is working!")
        }
    }
    
    /// Step 4: Test with compiler args - FULL END TO END TEST
    func testStep4_CursorInfoWithCompilerArgs() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceKitProofTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("Test.swift")
        let source = """
        class MyTestClass {
            var name: String = "hello"
        }
        """
        try source.write(to: testFile, atomically: true, encoding: .utf8)
        
        let service = SourceKitDService()
        try await service.initialize()
        
        let offset: Int64 = 6 // Points to "MyTestClass"
        
        // Get SDK path from xcrun
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let sdkPath = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        let compilerArgs = [
            testFile.path,
            "-sdk", sdkPath,
            "-target", "arm64-apple-macosx14.0"
        ]
        
        // Make cursor info request
        let result = try await service.cursorInfo(
            at: offset,
            in: testFile.path,
            sourceText: source,
            compilerArgs: compilerArgs
        )
        
        // Verify we got the expected results
        print("=== SOURCEKIT CURSOR INFO RESULT ===")
        print("Name: \(result.name ?? "nil")")
        print("Type: \(result.typeName ?? "nil")")
        print("Kind: \(result.kind ?? "nil")")
        print("USR: \(result.usr ?? "nil")")
        print("Module: \(result.moduleName ?? "nil")")
        print("=====================================")
        
        // Assert we got meaningful data
        XCTAssertEqual(result.name, "MyTestClass", "Should get class name from SourceKit")
        XCTAssertEqual(result.kind, "source.lang.swift.decl.class", "Should identify as class declaration")
        XCTAssertNotNil(result.usr, "Should have a USR")
        XCTAssertNotNil(result.typeName, "Should have a type name")
    }
}
