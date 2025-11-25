import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

/// Tests for ForceUnwrapRule
final class ForceUnwrapRuleUnitTests: XCTestCase {
    
    func testDetectsForceUnwrap() async throws {
        let sourceCode = """
        let value: String? = "hello"
        let unwrapped = value!
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ForceUnwrapRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 1, "Should detect one force unwrap")
        XCTAssertEqual(violations.first?.ruleId, "force_unwrap")
        XCTAssertEqual(violations.first?.category, .safety)
    }
    
    func testNoFalsePositivesOnOptionalBinding() async throws {
        let sourceCode = """
        let value: String? = "hello"
        if let unwrapped = value {
            print(unwrapped)
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ForceUnwrapRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 0, "Should not flag optional binding")
    }
    
    func testDetectsMultipleForceUnwraps() async throws {
        let sourceCode = """
        let a: Int? = 1
        let b: String? = "test"
        let x = a!
        let y = b!
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ForceUnwrapRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 2, "Should detect both force unwraps")
    }
}

/// Tests for ForceTryRule
final class ForceTryRuleUnitTests: XCTestCase {
    
    func testDetectsForceTry() async throws {
        let sourceCode = """
        func mayThrow() throws -> String { "hello" }
        let result = try! mayThrow()
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ForceTryRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 1, "Should detect one force try")
        XCTAssertEqual(violations.first?.ruleId, "force_try")
    }
    
    func testNoFalsePositivesOnRegularTry() async throws {
        let sourceCode = """
        func mayThrow() throws -> String { "hello" }
        do {
            let result = try mayThrow()
        } catch {
            print(error)
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = ForceTryRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 0, "Should not flag regular try")
    }
}

/// Tests for FatalErrorRule
final class FatalErrorRuleUnitTests: XCTestCase {
    
    func testDetectsFatalError() async throws {
        let sourceCode = """
        func doSomething() {
            fatalError("This should never happen")
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = FatalErrorRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 1, "Should detect fatalError")
        XCTAssertEqual(violations.first?.ruleId, "fatal_error")
    }
    
    func testDetectsPreconditionFailure() async throws {
        let sourceCode = """
        func validate(_ condition: Bool) {
            if !condition {
                preconditionFailure("Condition failed")
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = FatalErrorRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertGreaterThanOrEqual(violations.count, 1, "Should detect preconditionFailure")
    }
}

/// Tests for PrintInProductionRule
final class PrintInProductionRuleUnitTests: XCTestCase {
    
    func testDetectsPrint() async throws {
        let sourceCode = """
        func process() {
            print("Debug message")
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = PrintInProductionRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 1, "Should detect print statement")
        XCTAssertEqual(violations.first?.ruleId, "print_in_production")
    }
    
    func testDetectsDump() async throws {
        let sourceCode = """
        let data = ["key": "value"]
        dump(data)
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = PrintInProductionRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertGreaterThanOrEqual(violations.count, 1, "Should detect dump call")
    }
}

/// Tests for MutableStaticRule
final class MutableStaticRuleUnitTests: XCTestCase {
    
    func testDetectsMutableStatic() async throws {
        let sourceCode = """
        class Config {
            static var shared = Config()
            var value: Int = 0
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = MutableStaticRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertGreaterThanOrEqual(violations.count, 1, "Should detect mutable static")
        XCTAssertEqual(violations.first?.ruleId, "mutable_static")
    }
    
    func testNoFalsePositivesOnStaticLet() async throws {
        let sourceCode = """
        struct Constants {
            static let maxRetries = 3
            static let timeout: TimeInterval = 30
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = MutableStaticRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertEqual(violations.count, 0, "Should not flag static let")
    }
}
