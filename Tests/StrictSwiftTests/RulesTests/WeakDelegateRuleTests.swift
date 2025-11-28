import XCTest
@testable import StrictSwiftCore

final class WeakDelegateRuleTests: XCTestCase {
    
    private var rule: WeakDelegateRule!
    
    override func setUp() {
        super.setUp()
        rule = WeakDelegateRule()
    }
    
    // MARK: - Test Helpers
    
    private func analyze(_ source: String) async throws -> [Violation] {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let fileURL = tempDir.appendingPathComponent("test.swift")
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        
        let sourceFile = try SourceFile(url: fileURL)
        let config = Configuration.loadCriticalCore()
        let context = AnalysisContext(configuration: config, projectRoot: tempDir)
        
        return await rule.analyze(sourceFile, in: context)
    }
    
    // MARK: - Detection Tests
    
    func testDetectsStrongDelegate() async throws {
        let source = """
        class ViewController {
            var delegate: SomeDelegate?
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.ruleId, "weak_delegate")
        XCTAssertTrue(violations.first?.message.contains("delegate") ?? false)
    }
    
    func testAllowsWeakDelegate() async throws {
        let source = """
        class ViewController {
            weak var delegate: SomeDelegate?
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertTrue(violations.isEmpty)
    }
    
    func testDetectsStrongDataSource() async throws {
        let source = """
        class TableView {
            var dataSource: TableViewDataSource?
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.ruleId, "weak_delegate")
    }
    
    func testDetectsDelegateByTypeName() async throws {
        let source = """
        protocol MyCustomDelegate {}
        
        class MyClass {
            var handler: MyCustomDelegate?
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
    }
    
    func testIgnoresNonDelegateProperties() async throws {
        let source = """
        class MyClass {
            var name: String?
            var count: Int = 0
            var items: [String] = []
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertTrue(violations.isEmpty)
    }
    
    func testIgnoresStructs() async throws {
        let source = """
        struct MyStruct {
            var delegate: SomeDelegate?
        }
        """
        
        let violations = try await analyze(source)
        
        // Structs don't create retain cycles
        XCTAssertTrue(violations.isEmpty)
    }
    
    func testIgnoresEnums() async throws {
        let source = """
        enum MyEnum {
            case delegate(SomeDelegate)
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertTrue(violations.isEmpty)
    }
    
    func testDetectsMultipleDelegates() async throws {
        let source = """
        class ViewController {
            var delegate: ViewDelegate?
            var dataSource: DataSource?
            weak var properlyWeakDelegate: OtherDelegate?
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 2)
    }
    
    func testProvidesStructuredFix() async throws {
        let source = """
        class ViewController {
            var delegate: SomeDelegate?
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertFalse(violations.first?.structuredFixes.isEmpty ?? true)
        XCTAssertEqual(violations.first?.structuredFixes.first?.kind, .addAnnotation)
    }
    
    func testDetectsLetDelegate() async throws {
        let source = """
        class ViewController {
            let delegate: SomeDelegate?
        }
        """
        
        let violations = try await analyze(source)
        
        // Should detect even let bindings (they can't be weak but should be flagged)
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.ruleId, "weak_delegate")
    }
    
    func testFixForLetDelegateReplacesWithWeakVar() async throws {
        let source = """
        class ViewController {
            let delegate: SomeDelegate?
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        
        // The fix should replace 'let' with 'weak var', not insert 'weak ' before 'let'
        guard let fix = violations.first?.structuredFixes.first,
              let edit = fix.edits.first else {
            XCTFail("Expected structured fix with edit")
            return
        }
        
        // Verify the fix replaces 'let' with 'weak var'
        XCTAssertEqual(edit.newText, "weak var")
        // The range should cover the 'let' keyword (3 characters)
        XCTAssertEqual(edit.range.endColumn - edit.range.startColumn, 3)
    }
    
    func testFixForVarDelegateInsertsWeak() async throws {
        let source = """
        class ViewController {
            var delegate: SomeDelegate?
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        
        // The fix should insert 'weak ' before 'var'
        guard let fix = violations.first?.structuredFixes.first,
              let edit = fix.edits.first else {
            XCTFail("Expected structured fix with edit")
            return
        }
        
        // Verify the fix inserts 'weak '
        XCTAssertEqual(edit.newText, "weak ")
        // The range should be a point insertion (start == end)
        XCTAssertEqual(edit.range.startColumn, edit.range.endColumn)
    }
}
