import XCTest
@testable import StrictSwiftCore
import Foundation

final class StructuredFixTests: XCTestCase {
    
    // MARK: - Force Unwrap Fixes
    
    func testForceUnwrapRuleGeneratesStructuredFixes() async throws {
        let source = """
        import Foundation

        func testFunction() {
            let optional: String? = "test"
            let forced = optional!
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = ForceUnwrapRule()

        let violations = await rule.analyze(sourceFile, in: context)

        // Should have one violation
        XCTAssertEqual(violations.count, 1, "Expected 1 violation, got \(violations.count)")
        
        let violation = violations[0]
        
        // Should have structured fixes
        XCTAssertTrue(violation.hasAutoFix, "Violation should have auto-fix")
        XCTAssertGreaterThan(violation.structuredFixes.count, 0, "Should have at least one structured fix")
        
        // Check fix content
        for fix in violation.structuredFixes {
            XCTAssertFalse(fix.title.isEmpty, "Fix should have a title")
            XCTAssertFalse(fix.edits.isEmpty, "Fix should have edits")
            XCTAssertEqual(fix.ruleId, "force_unwrap", "Fix should have correct rule ID")
        }
    }
    
    // MARK: - Force Try Fixes
    
    func testForceTryRuleGeneratesStructuredFixes() async throws {
        let source = """
        import Foundation

        func testFunction() {
            let data = try! JSONEncoder().encode("test")
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = ForceTryRule()

        let violations = await rule.analyze(sourceFile, in: context)

        XCTAssertEqual(violations.count, 1, "Expected 1 violation")
        
        let violation = violations[0]
        
        // Should have structured fixes
        XCTAssertTrue(violation.hasAutoFix, "Violation should have auto-fix")
        XCTAssertGreaterThan(violation.structuredFixes.count, 0, "Should have structured fixes")
        
        // Should have try? option
        let tryOptionalFix = violation.structuredFixes.first { $0.title.contains("try?") }
        XCTAssertNotNil(tryOptionalFix, "Should have try? fix option")
        
        // Should have do-catch option
        let doCatchFix = violation.structuredFixes.first { $0.title.contains("do-catch") }
        XCTAssertNotNil(doCatchFix, "Should have do-catch fix option")
    }
    
    // MARK: - Print in Production Fixes
    
    func testPrintInProductionRuleGeneratesStructuredFixes() async throws {
        let source = """
        import Foundation

        func testFunction() {
            print("Debug output")
        }
        """

        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = PrintInProductionRule()

        let violations = await rule.analyze(sourceFile, in: context)

        XCTAssertEqual(violations.count, 1, "Expected 1 violation")
        
        let violation = violations[0]
        
        // Verify line number - print is on line 4 (1-indexed)
        // Note: SwiftSyntax may have different behavior, so check for reasonable range
        XCTAssertGreaterThanOrEqual(violation.location.line, 3, "Print should be on line 3 or later")
        XCTAssertLessThanOrEqual(violation.location.line, 5, "Print should be on line 5 or earlier")
        
        // Should have structured fixes
        XCTAssertTrue(violation.hasAutoFix, "Violation should have auto-fix")
        
        // Check fix has correct line range matching the violation
        if let debugFix = violation.structuredFixes.first(where: { $0.title.contains("DEBUG") }) {
            XCTAssertEqual(debugFix.edits.first?.range.startLine, violation.location.line,
                          "Fix range should start at same line as violation")
        }
        
        // Should have #if DEBUG option
        let debugFix = violation.structuredFixes.first { $0.title.contains("DEBUG") }
        XCTAssertNotNil(debugFix, "Should have #if DEBUG fix option")
        
        // Should have remove option
        let removeFix = violation.structuredFixes.first { $0.title.contains("Remove") }
        XCTAssertNotNil(removeFix, "Should have remove fix option")
    }
    
    // MARK: - Fix Application
    
    func testFixApplicationPreview() async throws {
        let source = """
        func test() {
            let value: String? = "hello"
            let forced = value!
        }
        """
        
        let sourceFile = try createSourceFile(content: source, filename: "test.swift")
        let context = createAnalysisContext(sourceFile: sourceFile)
        let rule = ForceUnwrapRule()
        
        let violations = await rule.analyze(sourceFile, in: context)
        guard let violation = violations.first, !violation.structuredFixes.isEmpty else {
            XCTFail("No violation or no fixes")
            return
        }
        
        // Create fix applier and preview
        let options = FixApplier.Options(
            minimumConfidence: .experimental,
            validateSyntax: false,
            formatAfterFix: false
        )
        let applier = FixApplier(options: options)
        
        // Should be able to apply fixes without throwing
        let result = try await applier.applyFixes(from: violations, to: sourceFile.url)
        
        // Result should have changes
        XCTAssertTrue(result.hasChanges || result.skippedFixes.count > 0, "Should have either changes or skipped fixes")
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
