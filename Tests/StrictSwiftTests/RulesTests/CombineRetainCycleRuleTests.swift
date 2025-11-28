import XCTest
@testable import StrictSwiftCore

final class CombineRetainCycleRuleTests: XCTestCase {
    
    private var rule: CombineRetainCycleRule!
    
    override func setUp() {
        super.setUp()
        rule = CombineRetainCycleRule()
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
    
    func testDetectsSinkWithStrongSelf() async throws {
        let source = """
        import Combine
        
        class ViewModel {
            var cancellables = Set<AnyCancellable>()
            var value: Int = 0
            
            func setup() {
                publisher.sink { value in
                    self.value = value
                }
                .store(in: &cancellables)
            }
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertGreaterThanOrEqual(violations.count, 1)
        XCTAssertTrue(violations.contains { $0.ruleId == "combine_retain_cycle" })
    }
    
    func testAllowsSinkWithWeakSelf() async throws {
        let source = """
        import Combine
        
        class ViewModel {
            var cancellables = Set<AnyCancellable>()
            var value: Int = 0
            
            func setup() {
                publisher.sink { [weak self] value in
                    self?.value = value
                }
                .store(in: &cancellables)
            }
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertFalse(violations.contains { $0.ruleId == "combine_retain_cycle" })
    }
    
    func testAllowsSinkWithUnownedSelf() async throws {
        let source = """
        import Combine
        
        class ViewModel {
            var cancellables = Set<AnyCancellable>()
            var value: Int = 0
            
            func setup() {
                publisher.sink { [unowned self] value in
                    self.value = value
                }
                .store(in: &cancellables)
            }
        }
        """
        
        let violations = try await analyze(source)
        
        // This is allowed by CombineRetainCycleRule (though UnownedAsyncRule might flag it)
        XCTAssertFalse(violations.contains { $0.ruleId == "combine_retain_cycle" })
    }
    
    func testIgnoresNonCombineCode() async throws {
        let source = """
        class ViewModel {
            var value: Int = 0
            
            func doSomething() {
                let closure = {
                    self.value = 42
                }
                closure()
            }
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertFalse(violations.contains { $0.ruleId == "combine_retain_cycle" })
    }
    
    func testDetectsReceiveWithStrongSelf() async throws {
        let source = """
        import Combine
        
        class ViewModel {
            var cancellables = Set<AnyCancellable>()
            
            func setup() {
                publisher
                    .receive(on: DispatchQueue.main)
                    .sink { self.handle($0) }
                    .store(in: &cancellables)
            }
            
            func handle(_ value: Int) {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertGreaterThanOrEqual(violations.count, 1)
    }
    
    func testIgnoresStructs() async throws {
        let source = """
        import Combine
        
        struct ViewModel {
            mutating func setup() {
                publisher.sink { value in
                    // Structs don't have retain cycles
                }
            }
        }
        """
        
        let violations = try await analyze(source)
        
        // Structs don't create retain cycles, so no violation
        XCTAssertFalse(violations.contains { $0.ruleId == "combine_retain_cycle" })
    }
}
