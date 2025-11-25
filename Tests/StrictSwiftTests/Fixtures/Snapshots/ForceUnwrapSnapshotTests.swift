import XCTest
@testable import StrictSwiftCore
import Foundation

/// Snapshot tests for ForceUnwrapRule to provide regression protection
final class ForceUnwrapSnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Create snapshot directory in test bundle instead of temp directory
        createSnapshotDirectory()
    }

    func testSnapshotForceUnwrapViolations() async throws {
        // Create comprehensive test source with various force unwrap scenarios
        let source = """
        import Foundation

        // Test 1: Basic force unwrap
        func basicForceUnwrap() {
            let optional: String? = "test"
            let forced = optional!
        }

        // Test 2: Force unwrap in optional chaining
        struct TestStruct {
            var property: String?

            func method() {
                let chained = property!.count
            }
        }

        // Test 3: Multiple force unwraps
        func multipleForceUnwraps() {
            let opt1: String? = "test1"
            let opt2: Int? = 42

            let forced1 = opt1!
            let forced2 = opt2!
        }

        // Test 4: Force unwrap in class context
        class TestClass {
            let optional: String?

            init(optional: String?) {
                self.optional = optional
                let forced = optional!
            }

            func method() {
                if let _ = optional {
                    let forced = optional!
                }
            }
        }

        // Test 5: Nested functions with force unwraps
        func outerFunction() {
            func innerFunction() {
                let optional: String? = "nested"
                let forced = optional!
            }
            innerFunction()
        }

        // Test 6: Force unwrap with complex expressions
        func complexForceUnwrap() {
            let optional: String? = "complex"
            let processed = optional!.uppercased().count
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "force_unwrap_test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = ForceUnwrapRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Sort violations for deterministic snapshot
        let sortedViolations = violations.sorted { lhs, rhs in
            if lhs.location.line != rhs.location.line {
                return lhs.location.line < rhs.location.line
            }
            return lhs.location.column < rhs.location.column
        }

        // Generate snapshot
        let snapshot = generateSnapshot(for: sortedViolations)

        // Assert snapshot matches expected
        assertSnapshot(snapshot, testName: "testSnapshotForceUnwrapViolations")
    }

    func testSnapshotNoViolationsInSafeCode() async throws {
        // Create test source with only safe optional operations
        let source = """
        import Foundation

        func safeOptionalOperations() {
            let optional: String? = "test"

            // Safe operations - should not trigger violations
            if let safe = optional {
                print(safe)
            }

            guard let guarded = optional else { return }
            print(guarded)

            let nilCoalesced = optional ?? "default"
            print(nilCoalesced)

            let optionalChained = optional?.count
            print(optionalChained)

            switch optional {
            case .some(let value):
                print(value)
            case .none:
                print("nil")
            }
        }

        struct SafeStruct {
            var property: String?

            func safeMethod() {
                if let prop = property {
                    print(prop)
                }

                let chained = property?.count
                print(chained)
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "safe_optional_test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = ForceUnwrapRule()

        // Run analysis
        let violations = await rule.analyze(sourceFile, in: context)

        // Should have no violations
        XCTAssertTrue(violations.isEmpty)

        // Generate snapshot even for empty violations
        let snapshot = generateSnapshot(for: violations)

        // Assert snapshot matches expected
        assertSnapshot(snapshot, testName: "testSnapshotNoViolationsInSafeCode")
    }

    // MARK: - Helper Methods

    private func createSourceFile(content: String, filename: String) throws -> SourceFile {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString)-\(filename)")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Register cleanup
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }

        return try SourceFile(url: fileURL)
    }

    private func createAnalysisContext(sourceFile: SourceFile) -> AnalysisContext {
        let configuration = Configuration.default
        let projectRoot = FileManager.default.temporaryDirectory
        let context = AnalysisContext(configuration: configuration, projectRoot: projectRoot)
        context.addSourceFile(sourceFile)
        return context
    }

    private func generateSnapshot(for violations: [Violation]) -> String {
        var result = ""

        for violation in violations {
            result += "\(String(describing: violation.severity).uppercased()) [\(String(describing: violation.category).uppercased()).\(violation.ruleId)]\n"
            result += "  \(violation.message)\n"
            // Normalize file path for snapshot stability
            // Strip UUID prefix from filename if present (format: UUID-filename.swift)
            // UUID format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX (36 chars total including hyphens)
            var filename = URL(fileURLWithPath: violation.location.file.path).lastPathComponent
            if filename.count > 37 {
                let uuidEndIndex = filename.index(filename.startIndex, offsetBy: 36)
                let potentialUUID = String(filename.prefix(upTo: uuidEndIndex))
                // Check if this looks like a UUID (has hyphens in right positions)
                if potentialUUID.count == 36 && 
                   potentialUUID[potentialUUID.index(potentialUUID.startIndex, offsetBy: 8)] == "-" &&
                   potentialUUID[potentialUUID.index(potentialUUID.startIndex, offsetBy: 13)] == "-" &&
                   filename[uuidEndIndex] == "-" {
                    filename = String(filename.suffix(from: filename.index(after: uuidEndIndex)))
                }
            }
            result += "  File: \(filename):\(violation.location.line):\(violation.location.column)\n"

            if !violation.suggestedFixes.isEmpty {
                result += "  Suggested fixes:\n"
                for fix in violation.suggestedFixes {
                    result += "    - \(fix)\n"
                }
            }

            if !violation.context.isEmpty {
                result += "  Context: \(violation.context)\n"
            }

            result += "\n"
        }

        if violations.isEmpty {
            result = "No violations found\n"
        }

        return result
    }

    private func createSnapshotDirectory() {
        let snapshotsDir = snapshotsDirectory()
        try? FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
    }

    private func snapshotsDirectory() -> URL {
        // Use test case's temp directory but don't clean up snapshots
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrictSwiftSnapshotTests")
            .appendingPathComponent("Snapshots")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        return tempDir
    }

    private func assertSnapshot(_ snapshot: String, testName: String, file: StaticString = #filePath, line: UInt = #line) {
        let snapshotFile = snapshotsDirectory().appendingPathComponent("\(testName).snapshot")

        // Create snapshot directory if it doesn't exist
        createSnapshotDirectory()

        if !FileManager.default.fileExists(atPath: snapshotFile.path) {
            // First run - create snapshot
            do {
                try snapshot.write(to: snapshotFile, atomically: true, encoding: .utf8)
                print("✅ Created new snapshot for \(testName) at: \(snapshotFile.path)")
            } catch {
                XCTFail("Failed to create snapshot file: \(error)", file: file, line: line)
            }
            return
        }

        // Compare with existing snapshot
        do {
            let existingSnapshot = try String(contentsOf: snapshotFile, encoding: .utf8)
            if snapshot == existingSnapshot {
                // Snapshots match - test passes
                return
            } else {
                // Snapshots differ - show diff and fail
                print("❌ Snapshot mismatch for \(testName)")
                print("\n--- EXPECTED ---")
                print(existingSnapshot)
                print("--- ACTUAL ---")
                print(snapshot)
                print("--- END DIFF ---\n")

                // For debugging, write actual to .failed file
                let failedFile = snapshotFile.appendingPathExtension("failed")
                try? snapshot.write(to: failedFile, atomically: true, encoding: .utf8)
                print("💾 Saved actual snapshot to: \(failedFile.path)")

                XCTFail("Snapshot does not match expected value for \(testName)", file: file, line: line)
            }
        } catch {
            XCTFail("Failed to read existing snapshot: \(error)", file: file, line: line)
        }
    }
}