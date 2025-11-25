import XCTest
@testable import StrictSwiftCore
import Foundation

final class SwallowedErrorFixTests: XCTestCase {
    
    func testSwallowedErrorRuleGeneratesStructuredFixes() async throws {
        let source = """
        func test() {
            do {
                try something()
            } catch {
            }
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = SwallowedErrorRule()

        let violations = await rule.analyze(sourceFile, in: context)

        XCTAssertEqual(violations.count, 1, "Expected 1 violation")
        let violation = violations[0]
        
        XCTAssertTrue(violation.hasAutoFix, "Violation should have auto-fix")
        
        let fix = violation.structuredFixes[0]
        XCTAssertEqual(fix.title, "Add TODO comment")
        
        // Apply fix
        let applier = FixApplier()
        let fixedSource = try await applier.apply(fix: fix, to: source)
        
        XCTAssertTrue(fixedSource.contains("// TODO: Handle error"))
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
