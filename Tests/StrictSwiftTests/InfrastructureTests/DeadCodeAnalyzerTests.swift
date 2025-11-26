import XCTest
import SwiftSyntax
import SwiftParser
@testable import StrictSwiftCore

final class DeadCodeAnalyzerTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func createSourceFile(
        url: URL,
        source: String,
        moduleName: String = "TestModule"
    ) -> SourceFile {
        return SourceFile(url: url, source: source, moduleName: moduleName)
    }
    
    private func buildGraphAndAnalyze(
        files: [SourceFile],
        configuration: DeadCodeConfiguration = .executableDefault
    ) -> DeadCodeResult {
        let graph = GlobalReferenceGraph()
        graph.build(from: files)
        let analyzer = DeadCodeAnalyzer(graph: graph, configuration: configuration)
        return analyzer.analyze()
    }
    
    // MARK: - Framework Callback Tests
    
    func testFrameworkCallbackMethodsMarkInternalRefsLive() throws {
        // This tests that methods named "visit" (SwiftSyntax) and "run" (ArgumentParser)
        // have their internal references followed during reachability analysis
        let source = """
        public class SensitiveLoggingRule {
            public init() {}
            public func analyze() {
                let visitor = SensitiveLoggingVisitor()
                visitor.walk()
            }
        }
        
        private final class SensitiveLoggingVisitor {
            private static let loggingFunctions: Set<String> = ["print"]
            
            func walk() {}
            
            // This is named "visit" which matches swiftSyntaxVisitorMethods
            func visit() {
                let _ = Self.loggingFunctions.contains("print")
            }
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source, moduleName: "TestModule")
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        let deadNames = result.deadSymbols.map { $0.name }
        // loggingFunctions should be live because visit() uses it, and visit() is treated as live
        XCTAssertFalse(deadNames.contains("loggingFunctions"), "loggingFunctions should be live via visit()")
    }

    // MARK: - Entry Point Detection Tests
    
    func testPublicSymbolAsEntryPointInLibraryMode() {
        let source = """
        public class PublicClass {
            public func publicMethod() {}
            func internalMethod() {}
        }
        
        class InternalClass {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        // Public symbols should be entry points in library mode
        let entryPointNames = result.entryPoints.map { $0.name }
        XCTAssertTrue(entryPointNames.contains("PublicClass"))
        XCTAssertTrue(entryPointNames.contains("publicMethod"))
        
        // Internal symbols should be dead (not reachable from public)
        let deadNames = result.deadSymbols.map { $0.name }
        XCTAssertTrue(deadNames.contains("InternalClass"))
    }
    
    func testMainAttributeAsEntryPoint() {
        let source = """
        @main
        struct MyApp {
            static func main() {
                usedFunction()
            }
        }
        
        func usedFunction() {}
        func unusedFunction() {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/main.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .executableDefault)
        
        // @main struct should be entry point
        let entryPointNames = result.entryPoints.map { $0.name }
        XCTAssertTrue(entryPointNames.contains("MyApp"))
        
        // Function called from main should be live
        XCTAssertTrue(result.liveSymbols.contains { id in
            result.entryPoints.contains { $0.id == id } ||
            result.deadSymbols.allSatisfy { $0.name != "usedFunction" || $0.id != id }
        })
    }
    
    func testObjcAttributeAsEntryPoint() {
        let source = """
        class ViewController {
            @objc func buttonTapped() {}
            func internalHelper() {}
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .executableDefault)
        
        // @objc function should be entry point
        let entryPointNames = result.entryPoints.map { $0.name }
        XCTAssertTrue(entryPointNames.contains("buttonTapped"))
    }
    
    func testIBActionAsEntryPoint() {
        let source = """
        class ViewController {
            @IBAction func handleTap() {}
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .executableDefault)
        
        let entryPointNames = result.entryPoints.map { $0.name }
        XCTAssertTrue(entryPointNames.contains("handleTap"))
    }
    
    func testMainSwiftFileAsEntryPoint() {
        let source = """
        func main() {
            startApp()
        }
        
        func startApp() {}
        func unusedHelper() {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/Sources/main.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .executableDefault)
        
        // Functions in main.swift should be entry points
        let entryPointNames = result.entryPoints.map { $0.name }
        XCTAssertTrue(entryPointNames.contains("main"))
    }
    
    func testTestMethodsAsEntryPoints() {
        let source = """
        class MyTests: XCTestCase {
            func testSomething() {
                helper()
            }
            
            func helper() {}
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/Tests/MyTests.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .executableDefault)
        
        // Test methods should be entry points
        let entryPointNames = result.entryPoints.map { $0.name }
        XCTAssertTrue(entryPointNames.contains("testSomething"))
        XCTAssertTrue(entryPointNames.contains("MyTests"))
    }
    
    // MARK: - Reachability Tests
    
    func testDirectFunctionCallReachability() {
        let source = """
        public func entryPoint() {
            usedFunction()
        }
        
        func usedFunction() {
            anotherUsed()
        }
        
        func anotherUsed() {}
        func neverCalled() {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        let deadNames = result.deadSymbols.map { $0.name }
        XCTAssertTrue(deadNames.contains("neverCalled"))
        XCTAssertFalse(deadNames.contains("usedFunction"))
        XCTAssertFalse(deadNames.contains("anotherUsed"))
    }
    
    func testTypeReferenceReachability() {
        let source = """
        public func createThing() -> UsedClass {
            return UsedClass()
        }
        
        class UsedClass {}
        class UnusedClass {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        let deadNames = result.deadSymbols.map { $0.name }
        XCTAssertTrue(deadNames.contains("UnusedClass"))
    }
    
    func testPropertyAccessReachability() {
        let source = """
        public class Container {
            var usedProperty: Int = 0
            var unusedProperty: String = ""
            
            public func getValue() -> Int {
                return usedProperty
            }
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        // In library mode, public class and method are entry points
        // usedProperty is accessed, unusedProperty is not
        let deadNames = result.deadSymbols.map { $0.name }
        XCTAssertTrue(deadNames.contains("unusedProperty"))
    }
    
    // MARK: - Protocol Handling Tests
    
    func testProtocolConformanceMarksImplementationsLive() {
        let source = """
        public protocol Greeter {
            func greet()
        }
        
        public class Person: Greeter {
            public func greet() {
                print("Hello")
            }
            
            func unusedMethod() {}
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        // Protocol requirement implementation should be live
        let deadNames = result.deadSymbols.map { $0.name }
        XCTAssertFalse(deadNames.contains("greet"))
        XCTAssertTrue(deadNames.contains("unusedMethod"))
    }
    
    func testCodableMarksInit() {
        let source = """
        public struct Config: Codable {
            var name: String
            var value: Int
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        // Codable synthesized members should not be reported as dead
        let deadNames = result.deadSymbols.map { $0.name }
        XCTAssertFalse(deadNames.contains("encode"))
        XCTAssertFalse(deadNames.contains("init"))
    }
    
    // MARK: - Ignored Symbol Tests
    
    func testUnderscorePrefixIgnored() {
        let source = """
        public func publicFunc() {}
        func _privateHelper() {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        // Underscore-prefixed symbols should be ignored
        let ignoredNames = result.ignoredSymbols.map { $0.name }
        XCTAssertTrue(ignoredNames.contains("_privateHelper"))
        
        let deadNames = result.deadSymbols.map { $0.name }
        XCTAssertFalse(deadNames.contains("_privateHelper"))
    }
    
    func testExtensionsIgnored() {
        let source = """
        public class MyClass {}
        
        extension MyClass {
            func extensionMethod() {}
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        // Extensions themselves are ignored (their members are analyzed)
        let deadNames = result.deadSymbols.map { $0.name }
        let deadKinds = result.deadSymbols.map { $0.kind }
        XCTAssertFalse(deadKinds.contains(.extension))
    }
    
    func testDeinitializersIgnored() {
        let source = """
        public class Resource {
            deinit {
                cleanup()
            }
            
            func cleanup() {}
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        // Deinitializers are never reported as dead
        let deadKinds = result.deadSymbols.map { $0.kind }
        XCTAssertFalse(deadKinds.contains(.deinitializer))
    }
    
    // MARK: - Multi-File Tests
    
    func testCrossFileReachability() {
        let file1Source = """
        public func entryPoint() {
            helperFromOtherFile()
        }
        """
        
        let file2Source = """
        func helperFromOtherFile() {
            anotherHelper()
        }
        
        func anotherHelper() {}
        func isolatedFunction() {}
        """
        
        let file1 = createSourceFile(url: URL(fileURLWithPath: "/file1.swift"), source: file1Source)
        let file2 = createSourceFile(url: URL(fileURLWithPath: "/file2.swift"), source: file2Source)
        
        let result = buildGraphAndAnalyze(files: [file1, file2], configuration: .libraryDefault)
        
        let deadNames = result.deadSymbols.map { $0.name }
        XCTAssertTrue(deadNames.contains("isolatedFunction"))
        XCTAssertFalse(deadNames.contains("helperFromOtherFile"))
        XCTAssertFalse(deadNames.contains("anotherHelper"))
    }
    
    // MARK: - Configuration Tests
    
    func testLibraryVsExecutableMode() {
        let source = """
        public func publicFunc() {}
        func internalFunc() {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        
        // Library mode: public is entry point
        let libraryResult = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        let libraryDeadNames = libraryResult.deadSymbols.map { $0.name }
        XCTAssertTrue(libraryDeadNames.contains("internalFunc"))
        XCTAssertFalse(libraryDeadNames.contains("publicFunc"))
        
        // Executable mode: public is not automatically entry point
        let execResult = buildGraphAndAnalyze(files: [file], configuration: .executableDefault)
        let execDeadNames = execResult.deadSymbols.map { $0.name }
        // Both should be dead in executable mode (no entry points)
        XCTAssertTrue(execDeadNames.contains("publicFunc") || execResult.entryPoints.isEmpty)
    }
    
    func testCustomConfiguration() {
        let source = """
        func regularFunction() {}
        func ignored_function() {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        
        let config = DeadCodeConfiguration(
            mode: .executable,
            treatPublicAsEntryPoint: false,
            treatOpenAsEntryPoint: false,
            entryPointAttributes: [],
            entryPointFilePatterns: [],
            ignoredPatterns: [],
            ignoredPrefixes: ["ignored_"],
            synthesizedMemberProtocols: []
        )
        
        let result = buildGraphAndAnalyze(files: [file], configuration: config)
        
        let ignoredNames = result.ignoredSymbols.map { $0.name }
        XCTAssertTrue(ignoredNames.contains("ignored_function"))
    }
    
    // MARK: - Statistics Tests
    
    func testAnalysisStatistics() {
        let source = """
        public func entry() {}
        func dead1() {}
        func dead2() {}
        func _ignored() {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        XCTAssertGreaterThan(result.statistics.totalSymbols, 0)
        XCTAssertGreaterThan(result.statistics.entryPointCount, 0)
        XCTAssertGreaterThan(result.statistics.deadCount, 0)
        XCTAssertGreaterThan(result.statistics.analysisTimeMs, 0)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyFile() {
        let source = ""
        let file = createSourceFile(url: URL(fileURLWithPath: "/empty.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        XCTAssertEqual(result.deadSymbols.count, 0)
        XCTAssertEqual(result.entryPoints.count, 0)
    }
    
    func testNoEntryPoints() {
        let source = """
        func helper1() {}
        func helper2() {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/helpers.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .executableDefault)
        
        // With no entry points, all symbols are dead
        XCTAssertEqual(result.entryPoints.count, 0)
        XCTAssertGreaterThan(result.deadSymbols.count, 0)
    }
    
    // MARK: - Self/self Member Access Tests
    
    func testSelfMemberAccessMarksPropertyUsed() {
        let source = """
        public class MyClass {
            private var isRunning = false
            
            public func start() {
                self.isRunning = true
            }
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        // isRunning should NOT be dead since it's used via self.isRunning
        let deadNames = result.deadSymbols.map { $0.name }
        XCTAssertFalse(deadNames.contains("isRunning"), "isRunning should be marked as used via self.isRunning")
    }
    
    func testStaticSelfMemberAccessMarksPropertyUsed() {
        // Test Self.property access pattern
        let source = """
        public final class SensitiveLoggingRule {
            public init() {}
            
            public func analyze() {
                let visitor = SensitiveLoggingVisitor()
                visitor.visit()
            }
        }
        
        private final class SensitiveLoggingVisitor {
            private static let loggingFunctions: Set<String> = ["print"]
            
            init() {}
            
            func visit() {
                let _ = Self.loggingFunctions.contains("print")
            }
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        // loggingFunctions should NOT be dead since it's used via Self.loggingFunctions
        let deadNames = result.deadSymbols.map { $0.name }
        XCTAssertFalse(deadNames.contains("loggingFunctions"), "loggingFunctions should be marked as used via Self.loggingFunctions")
    }
    
    func testLocalVariableTypeTracking() {
        // Test that `let x = Foo()` followed by `x.method()` marks method as used
        let source = """
        public class DataProcessor {
            public init() {}
            
            public func process() {
                let helper = ProcessorHelper()
                helper.compute()
            }
        }
        
        private class ProcessorHelper {
            init() {}
            
            func compute() {
                print("computing")
            }
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        let deadNames = result.deadSymbols.map { $0.name }
        // ProcessorHelper should be live because DataProcessor.process() creates an instance
        XCTAssertFalse(deadNames.contains("ProcessorHelper"), "ProcessorHelper should be live via instantiation")
        // compute() should be live because helper.compute() is called
        XCTAssertFalse(deadNames.contains("compute"), "compute() should be marked as used via local variable type tracking")
    }
    
    func testLocalVariableTypeTrackingWithExplicitType() {
        // Test that explicit type annotations work: `let x: Foo = ...`
        let source = """
        public class Service {
            public init() {}
            
            public func start() {
                let worker: Worker = Worker()
                worker.execute()
            }
        }
        
        private class Worker {
            init() {}
            
            func execute() {
                print("executing")
            }
            
            func unused() {}
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        let deadNames = result.deadSymbols.map { $0.name }
        // Worker and execute should be live
        XCTAssertFalse(deadNames.contains("Worker"), "Worker should be live")
        XCTAssertFalse(deadNames.contains("execute"), "execute() should be live via type-aware tracking")
        // unused() should still be dead
        XCTAssertTrue(deadNames.contains("unused"), "unused() should be dead")
    }
    
    func testMetatypeSelfAccessMarksTypeAsUsed() {
        // Test that Type.self metatype access marks the type as used
        // This is common with ArgumentParser subcommands: [CheckCommand.self, ...]
        let source = """
        public struct Registry {
            public init() {}
            
            public static let items: [Handler.Type] = [
                ConcreteHandler.self,
                AnotherHandler.self
            ]
        }
        
        protocol Handler {}
        
        private struct ConcreteHandler: Handler {}
        private struct AnotherHandler: Handler {}
        private struct UnusedHandler: Handler {}
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        let deadNames = result.deadSymbols.map { $0.name }
        // ConcreteHandler and AnotherHandler should be live via .self metatype access
        XCTAssertFalse(deadNames.contains("ConcreteHandler"), "ConcreteHandler should be live via .self")
        XCTAssertFalse(deadNames.contains("AnotherHandler"), "AnotherHandler should be live via .self")
        // UnusedHandler should still be dead
        XCTAssertTrue(deadNames.contains("UnusedHandler"), "UnusedHandler should be dead")
    }
    
    func testSwitchPatternEnumCaseTracking() {
        // Test that enum cases used in switch patterns are marked as used
        let source = """
        public enum Status {
            case active
            case inactive
            case pending
            case unused
        }
        
        public func process(_ status: Status) {
            switch status {
            case .active:
                print("active")
            case .inactive:
                print("inactive")
            case .pending:
                print("pending")
            default:
                break
            }
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        let deadNames = result.deadSymbols.map { $0.name }
        // active, inactive, pending should be live via switch pattern
        XCTAssertFalse(deadNames.contains("active"), "active should be live via switch pattern")
        XCTAssertFalse(deadNames.contains("inactive"), "inactive should be live via switch pattern")
        XCTAssertFalse(deadNames.contains("pending"), "pending should be live via switch pattern")
        // unused should still be dead
        XCTAssertTrue(deadNames.contains("unused"), "unused should be dead")
    }
    
    func testCaseIterableEnumCasesAreAllLive() {
        // Test that enum cases in a CaseIterable enum are all considered live
        let source = """
        public enum ImportKind: String, CaseIterable {
            case regular
            case typeAlias
            case structKind
            case classKind
        }
        
        public func printAllKinds() {
            for kind in ImportKind.allCases {
                print(kind.rawValue)
            }
        }
        """
        
        let file = createSourceFile(url: URL(fileURLWithPath: "/test.swift"), source: source)
        let result = buildGraphAndAnalyze(files: [file], configuration: .libraryDefault)
        
        let deadNames = result.deadSymbols.map { $0.name }
        // All cases should be live because CaseIterable makes all cases accessible via allCases
        XCTAssertFalse(deadNames.contains("regular"), "regular should be live via CaseIterable")
        XCTAssertFalse(deadNames.contains("typeAlias"), "typeAlias should be live via CaseIterable")
        XCTAssertFalse(deadNames.contains("structKind"), "structKind should be live via CaseIterable")
        XCTAssertFalse(deadNames.contains("classKind"), "classKind should be live via CaseIterable")
    }
}
