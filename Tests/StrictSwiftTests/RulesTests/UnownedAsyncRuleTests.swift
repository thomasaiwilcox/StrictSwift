import XCTest
@testable import StrictSwiftCore

final class UnownedAsyncRuleTests: XCTestCase {
    
    private var rule: UnownedAsyncRule!
    
    override func setUp() {
        super.setUp()
        rule = UnownedAsyncRule()
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
    
    func testDetectsUnownedSelfInTask() async throws {
        let source = """
        class ViewModel {
            func doWork() {
                Task { [unowned self] in
                    self.process()
                }
            }
            
            func process() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.ruleId, "unowned_async")
        XCTAssertEqual(violations.first?.severity, .error) // Should be error severity
    }
    
    func testDetectsUnownedSelfInTaskDetached() async throws {
        let source = """
        class ViewModel {
            func doWork() {
                Task.detached { [unowned self] in
                    self.process()
                }
            }
            
            func process() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.ruleId, "unowned_async")
    }
    
    func testAllowsWeakSelfInTask() async throws {
        let source = """
        class ViewModel {
            func doWork() {
                Task { [weak self] in
                    self?.process()
                }
            }
            
            func process() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertTrue(violations.isEmpty)
    }
    
    func testAllowsUnownedSelfInNonAsyncContext() async throws {
        let source = """
        class ViewModel {
            var handler: (() -> Void)?
            
            func setup() {
                // Regular closure, not async - unowned is fine here
                handler = { [unowned self] in
                    self.process()
                }
            }
            
            func process() {}
        }
        """
        
        let violations = try await analyze(source)
        
        // Should not flag unowned in non-async closures
        XCTAssertTrue(violations.isEmpty)
    }
    
    func testDetectsUnownedInDispatchAsync() async throws {
        let source = """
        class ViewModel {
            func doWork() {
                DispatchQueue.main.async { [unowned self] in
                    self.process()
                }
            }
            
            func process() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
    }
    
    func testProvidesStructuredFix() async throws {
        let source = """
        class ViewModel {
            func doWork() {
                Task { [unowned self] in
                    self.process()
                }
            }
            
            func process() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertFalse(violations.first?.structuredFixes.isEmpty ?? true)
        XCTAssertEqual(violations.first?.structuredFixes.first?.kind, .replace)
    }
    
    func testErrorSeverity() async throws {
        let source = """
        class ViewModel {
            func doWork() {
                Task { [unowned self] in
                    self.process()
                }
            }
            func process() {}
        }
        """
        
        let violations = try await analyze(source)
        
        // This rule should use .error severity since it's a crash risk
        XCTAssertEqual(violations.first?.severity, .error)
    }
}
