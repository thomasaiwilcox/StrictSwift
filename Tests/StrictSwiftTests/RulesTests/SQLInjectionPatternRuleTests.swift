import XCTest
@testable import StrictSwiftCore
import SwiftSyntax
import SwiftParser

final class SQLInjectionPatternRuleTests: XCTestCase {
    
    // MARK: - False Positive Prevention Tests
    
    func testDoesNotFlagSwiftUnionMethod() async throws {
        let sourceCode = """
        import Foundation
        
        func process(items: Set<Int>) -> Set<Int> {
            let result = "Combined set: \\(items.union(otherSet))"
            return items
        }
        
        let otherSet: Set<Int> = []
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = SQLInjectionPatternRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertTrue(violations.isEmpty, "Should not flag .union() Swift method as SQL UNION")
    }
    
    func testDoesNotFlagUpdatePropertyName() async throws {
        let sourceCode = """
        struct Tracker {
            var lastUpdate: Date = Date()
            var updateCount: Int = 0
            
            func logUpdate() {
                print("Last update: \\(lastUpdate), count: \\(updateCount)")
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = SQLInjectionPatternRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertTrue(violations.isEmpty, "Should not flag 'update' in property names as SQL UPDATE")
    }
    
    func testDoesNotFlagSelectedPropertyName() async throws {
        let sourceCode = """
        struct SelectableItem {
            var isSelected: Bool = false
            var selectedItems: [String] = []
            
            func showSelection() {
                print("Selected: \\(isSelected), items: \\(selectedItems)")
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = SQLInjectionPatternRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertTrue(violations.isEmpty, "Should not flag 'selected' in property names as SQL SELECT")
    }
    
    func testDoesNotFlagCreateMethodName() async throws {
        let sourceCode = """
        class Factory {
            func createWidget(name: String) -> String {
                return "Created: \\(name)"
            }
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = SQLInjectionPatternRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertTrue(violations.isEmpty, "Should not flag 'create' in method names as SQL CREATE")
    }
    
    // MARK: - Real SQL Injection Detection Tests
    
    func testFlagsRealSelectFromQuery() async throws {
        let sourceCode = """
        func fetchUser(userId: String) {
            let query = "SELECT * FROM users WHERE id = '\\(userId)'"
            print(query)
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = SQLInjectionPatternRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should flag real SELECT FROM SQL with interpolation")
    }
    
    func testFlagsRealInsertIntoQuery() async throws {
        let sourceCode = """
        func insertUser(name: String) {
            let query = "INSERT INTO users (name) VALUES ('\\(name)')"
            print(query)
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = SQLInjectionPatternRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should flag real INSERT INTO SQL with interpolation")
    }
    
    func testFlagsRealUpdateSetQuery() async throws {
        let sourceCode = """
        func updateUser(id: String, name: String) {
            let query = "UPDATE users SET name = '\\(name)' WHERE id = \\(id)"
            print(query)
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = SQLInjectionPatternRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should flag real UPDATE SET SQL with interpolation")
    }
    
    func testFlagsRealDeleteFromQuery() async throws {
        let sourceCode = """
        func deleteUser(userId: String) {
            let query = "DELETE FROM users WHERE id = '\\(userId)'"
            print(query)
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = SQLInjectionPatternRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertFalse(violations.isEmpty, "Should flag real DELETE FROM SQL with interpolation")
    }
    
    func testDoesNotFlagSafeParameterizedQuery() async throws {
        let sourceCode = """
        func fetchUser(userId: String) {
            // Safe - using parameterized query
            let query = "SELECT * FROM users WHERE id = ?"
            database.execute(query, parameters: [userId])
        }
        
        struct database {
            static func execute(_ query: String, parameters: [String]) {}
        }
        """
        
        let sourceFile = SourceFile(url: URL(fileURLWithPath: "/tmp/test.swift"), source: sourceCode)
        let rule = SQLInjectionPatternRule()
        let context = AnalysisContext(
            sourceFiles: [sourceFile],
            workspace: URL(fileURLWithPath: "/tmp"),
            configuration: Configuration()
        )
        
        let violations = await rule.analyze(sourceFile, in: context)
        
        XCTAssertTrue(violations.isEmpty, "Should not flag parameterized queries without interpolation")
    }
}
