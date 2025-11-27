import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

/// Tests for DeadCodeRule integration with the Rule protocol
/// Note: Core dead code analysis logic is tested in DeadCodeAnalyzerTests
final class DeadCodeRuleTests: XCTestCase {
    
    // MARK: - Basic Detection Tests
    
    func testDetectsUnusedPrivateFunction() async throws {
        let sourceCode = """
        class MyClass {
            func publicMethod() {
                print("Hello")
            }
            
            private func unusedHelper() {
                print("Never called")
            }
        }
        """
        
        let sourceFile = SourceFile(
            url: URL(fileURLWithPath: "/tmp/test.swift"),
            source: sourceCode
        )
        let rule = DeadCodeRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        // Should detect the unused private helper
        XCTAssertFalse(violations.isEmpty, "Should detect unused private function")
        XCTAssertTrue(
            violations.contains { $0.message.contains("unusedHelper") },
            "Should mention the unused function name"
        )
        XCTAssertEqual(violations.first?.ruleId, "dead-code")
        XCTAssertEqual(violations.first?.category, .architecture)
    }
    
    // MARK: - Structured Fix Tests
    
    func testStructuredFixProvided() async throws {
        let sourceCode = """
        class MyClass {
            private func unusedMethod() {
                print("unused")
            }
        }
        """
        
        let sourceFile = SourceFile(
            url: URL(fileURLWithPath: "/tmp/test.swift"),
            source: sourceCode
        )
        let rule = DeadCodeRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should detect unused method")
        
        // Check that a structured fix is provided
        let violation = violations.first { $0.message.contains("unusedMethod") }
        XCTAssertFalse(violation?.structuredFixes.isEmpty ?? true, "Should provide structured fix for removal")
        XCTAssertEqual(violation?.structuredFixes.first?.kind, .removeCode, "Fix should be removal")
    }
    
    // MARK: - Rule Metadata Tests
    
    func testRuleMetadata() {
        let rule = DeadCodeRule()
        
        XCTAssertEqual(rule.id, "dead-code")
        XCTAssertEqual(rule.category, .architecture)
        XCTAssertEqual(rule.defaultSeverity, .warning)
        XCTAssertFalse(rule.description.isEmpty, "Rule should have a description")
        XCTAssertFalse(rule.name.isEmpty, "Rule should have a name")
    }
    
    func testRuleEnabledByDefault() {
        let rule = DeadCodeRule()
        XCTAssertTrue(rule.enabledByDefault, "DeadCodeRule should be enabled by default")
    }
    
    func testRuleShouldAnalyzeSwiftFiles() {
        let rule = DeadCodeRule()
        
        let swiftFile = SourceFile(
            url: URL(fileURLWithPath: "/tmp/test.swift"),
            source: ""
        )
        let nonSwiftFile = SourceFile(
            url: URL(fileURLWithPath: "/tmp/test.txt"),
            source: ""
        )
        
        XCTAssertTrue(rule.shouldAnalyze(swiftFile), "Should analyze .swift files")
        XCTAssertFalse(rule.shouldAnalyze(nonSwiftFile), "Should not analyze non-swift files")
    }
    
    // MARK: - Violation Structure Tests
    
    func testViolationContainsLocation() async throws {
        let sourceCode = """
        private func deadCode() {}
        """
        
        let sourceFile = SourceFile(
            url: URL(fileURLWithPath: "/tmp/test.swift"),
            source: sourceCode
        )
        let rule = DeadCodeRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should detect dead code")
        
        if let violation = violations.first {
            XCTAssertEqual(violation.location.file.path, "/tmp/test.swift")
            XCTAssertGreaterThan(violation.location.line, 0, "Should have valid line number")
        }
    }
}
