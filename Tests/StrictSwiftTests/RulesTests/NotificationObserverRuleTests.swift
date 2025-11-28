import XCTest
@testable import StrictSwiftCore

final class NotificationObserverRuleTests: XCTestCase {
    
    private var rule: NotificationObserverRule!
    
    override func setUp() {
        super.setUp()
        rule = NotificationObserverRule()
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
    
    func testDetectsAddObserverWithoutDeinit() async throws {
        let source = """
        class ViewController {
            func setup() {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleNotification),
                    name: .someNotification,
                    object: nil
                )
            }
            
            @objc func handleNotification() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.ruleId, "notification_observer")
        XCTAssertTrue(violations.first?.message.contains("cleanup") ?? false)
    }
    
    func testDetectsAddObserverWithDeinitButNoRemove() async throws {
        let source = """
        class ViewController {
            func setup() {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleNotification),
                    name: .someNotification,
                    object: nil
                )
            }
            
            deinit {
                // Does something else but no removeObserver
                print("deinit")
            }
            
            @objc func handleNotification() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
    }
    
    func testAllowsAddObserverWithProperCleanup() async throws {
        let source = """
        class ViewController {
            func setup() {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleNotification),
                    name: .someNotification,
                    object: nil
                )
            }
            
            deinit {
                NotificationCenter.default.removeObserver(self)
            }
            
            @objc func handleNotification() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertTrue(violations.isEmpty)
    }
    
    func testAllowsBlockBasedObserverStoredInProperty() async throws {
        let source = """
        class ViewController {
            var observer: Any?
            
            func setup() {
                observer = NotificationCenter.default.addObserver(
                    forName: .someNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.handleNotification()
                }
            }
            
            deinit {
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
            
            func handleNotification() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertTrue(violations.isEmpty)
    }
    
    func testDetectsMultipleUnmatchedObservers() async throws {
        let source = """
        class ViewController {
            func setup() {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleA),
                    name: .notificationA,
                    object: nil
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleB),
                    name: .notificationB,
                    object: nil
                )
            }
            
            @objc func handleA() {}
            @objc func handleB() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 2)
    }
    
    func testIgnoresStructs() async throws {
        let source = """
        struct DataHandler {
            func setup() {
                // Structs can't use selector-based observers
                // This would be a compile error anyway
            }
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertTrue(violations.isEmpty)
    }
    
    func testProvidesSuggestedFix() async throws {
        let source = """
        class ViewController {
            func setup() {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleNotification),
                    name: .someNotification,
                    object: nil
                )
            }
            
            @objc func handleNotification() {}
        }
        """
        
        let violations = try await analyze(source)
        
        XCTAssertEqual(violations.count, 1)
        XCTAssertFalse(violations.first?.suggestedFixes.isEmpty ?? true)
        XCTAssertTrue(violations.first?.suggestedFixes.first?.contains("deinit") ?? false)
    }
    
    func testAllowsRemoveInViewWillDisappear() async throws {
        // iOS pattern: remove in viewWillDisappear instead of deinit
        let source = """
        class ViewController {
            func viewDidAppear() {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleNotification),
                    name: .someNotification,
                    object: nil
                )
            }
            
            func viewWillDisappear() {
                NotificationCenter.default.removeObserver(self)
            }
            
            @objc func handleNotification() {}
        }
        """
        
        let violations = try await analyze(source)
        
        // Should still warn - viewWillDisappear may not be called if view is never shown
        // But this is a lower priority warning, so we'll accept either behavior
        // For now, we expect the rule to require deinit cleanup
        XCTAssertEqual(violations.count, 1)
    }
}
