import XCTest
@testable import StrictSwiftCore

final class MainActorBlockingRuleTests: XCTestCase {
    
    private var rule: MainActorBlockingRule!
    
    override func setUp() {
        super.setUp()
        rule = MainActorBlockingRule()
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
    
    func testDetectsThreadSleepOnMainActor() async throws {
        let source = """
        @MainActor
        class ViewController {
            func doWork() {
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.ruleId, "mainactor_blocking")
        XCTAssertTrue(violations.first?.message.contains("Thread.sleep") ?? false)
    }
    
    func testDetectsDataContentsOfOnMainActor() async throws {
        let source = """
        @MainActor
        func loadData() {
            let data = try? Data(contentsOf: URL(string: "https://example.com")!)
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertTrue(violations.first?.message.contains("Data(contentsOf:)") ?? false)
    }
    
    func testDetectsBlockingInMainActorFunction() async throws {
        let source = """
        class ViewController {
            @MainActor
            func updateUI() {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
    }
    
    func testAllowsBlockingOffMainActor() async throws {
        let source = """
        class DataLoader {
            func loadData() {
                // Not on MainActor, so blocking is OK
                Thread.sleep(forTimeInterval: 1.0)
                let data = try? Data(contentsOf: URL(string: "https://example.com")!)
            }
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertTrue(violations.isEmpty)
    }
    
    func testDetectsSemaphoreWaitOnMainActor() async throws {
        let source = """
        @MainActor
        class ViewController {
            let semaphore = DispatchSemaphore(value: 0)
            
            func waitForSomething() {
                semaphore.wait()
            }
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertTrue(violations.first?.message.lowercased().contains("semaphore") ?? false)
    }
    
    func testDetectsFileManagerOperationsOnMainActor() async throws {
        let source = """
        @MainActor
        func readFile() {
            let data = FileManager.default.contents(atPath: "/some/path")
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
    }
    
    func testNestedMainActorContext() async throws {
        let source = """
        @MainActor
        class ViewController {
            func outer() {
                func inner() {
                    Thread.sleep(forTimeInterval: 1.0)
                }
                inner()
            }
        }
        """
        
        let violations = try await analyze(source)
        
        // Should detect because we're still in @MainActor class
        XCTAssertEqual(violations.count, 1)
    }
    
    func testProvidesAsyncAlternative() async throws {
        let source = """
        @MainActor
        func loadData() {
            let data = try? Data(contentsOf: URL(string: "https://example.com")!)
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        let context = violations.first?.context["asyncAlternative"]
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("URLSession") ?? false)
    }
}
