import XCTest
@testable import StrictSwiftCore
import Foundation

final class ResourceLeakFixTests: XCTestCase {
    
    func testResourceLeakRuleGeneratesStructuredFixes() async throws {
        let source = """
        func test() {
            let file = FileHandle(forReadingAtPath: "path")
            // do something
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = ResourceLeakRule()

        let violations = await rule.analyze(sourceFile, in: context)

        XCTAssertEqual(violations.count, 1, "Expected 1 violation")
        let violation = violations[0]
        
        XCTAssertTrue(violation.hasAutoFix, "Violation should have auto-fix")
        
        let fix = violation.structuredFixes[0]
        XCTAssertTrue(fix.title.contains("Add defer"), "Fix title should mention defer")
        
        // Apply fix
        let applier = FixApplier()
        let fixedSource = try await applier.apply(fix: fix, to: source)
        
        // We expect the defer to be inserted after the declaration
        // Note: Indentation might be tricky, so we check for presence and order
        XCTAssertTrue(fixedSource.contains("defer { file.close() }"))
        
        // Check that it's inserted after the declaration
        let declIndex = fixedSource.range(of: "let file =")?.upperBound
        let deferIndex = fixedSource.range(of: "defer {")?.lowerBound
        
        XCTAssertNotNil(declIndex)
        XCTAssertNotNil(deferIndex)
        XCTAssertTrue(deferIndex! > declIndex!)
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
