import XCTest
@testable import StrictSwiftCore
import Foundation

final class StringConcatenationFixTests: XCTestCase {
    
    func testStringConcatenationLoopRuleGeneratesStructuredFixes() async throws {
        let source = """
        func test() {
            var str = ""
            for i in 0..<10 {
                str += "a"
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = StringConcatenationLoopRule()

        let violations = await rule.analyze(sourceFile, in: context)

        XCTAssertEqual(violations.count, 1, "Expected 1 violation")
        let violation = violations[0]
        
        XCTAssertTrue(violation.hasAutoFix, "Violation should have auto-fix")
        XCTAssertEqual(violation.structuredFixes.count, 1, "Should have 1 structured fix")
        
        let fix = violation.structuredFixes[0]
        XCTAssertEqual(fix.title, "Convert to .append()")
        XCTAssertEqual(fix.edits.count, 2, "Should have 2 edits")
        
        // Verify edits
        // 1. Replace += with .append(
        let edit1 = fix.edits[0]
        XCTAssertEqual(edit1.newText, ".append(")
        
        // 2. Insert ) at end
        let edit2 = fix.edits[1]
        XCTAssertEqual(edit2.newText, ")")
        
        // Apply fixes to verify result
        let applier = FixApplier()
        let fixedSource = try await applier.apply(fix: fix, to: source)
        
        let expectedSource = """
        func test() {
            var str = ""
            for i in 0..<10 {
                str .append("a")
            }
        }
        """
        
        XCTAssertEqual(fixedSource, expectedSource)
    }

    // MARK: - Helpers
    
    private func createSourceFile(content: String, filename: String) throws -> SourceFile {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileURL = tempDir.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return try SourceFile(url: fileURL)
    }
    
    private func createAnalysisContext(sourceFile: SourceFile) -> AnalysisContext {
        let projectRoot = sourceFile.url.deletingLastPathComponent()
        let configuration = Configuration.loadCriticalCore()
        return AnalysisContext(configuration: configuration, projectRoot: projectRoot)
    }
}
