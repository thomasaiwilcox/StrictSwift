import XCTest
@testable import StrictSwiftCore
import SwiftParser
import SwiftSyntax

/// Tests for Phase 2 Deep Symbol Collection enhancements
/// Covers: actors, operators, precedence groups, macros, and multiple variable bindings
final class SymbolCollectorPhase2Tests: XCTestCase {
    
    private func collectSymbols(from source: String, moduleName: String = "TestModule") -> [Symbol] {
        let url = URL(fileURLWithPath: "/test.swift")
        let tree = Parser.parse(source: source)
        let collector = SymbolCollector(fileURL: url, tree: tree, moduleName: moduleName)
        collector.walk(tree)
        return collector.symbols
    }
    
    // MARK: - Actor Tests
    
    func testCollectActor() {
        let source = """
        actor MyActor {
            var state: Int = 0
            
            func doWork() {}
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 3)
        
        let actor = symbols[0]
        XCTAssertEqual(actor.name, "MyActor")
        XCTAssertEqual(actor.kind, .actor)
        XCTAssertEqual(actor.qualifiedName, "MyActor")
        XCTAssertNil(actor.parentID)
        
        // Verify members have correct parent
        XCTAssertEqual(symbols[1].name, "state")
        XCTAssertEqual(symbols[1].kind, .variable)
        XCTAssertEqual(symbols[1].parentID, actor.id)
        
        XCTAssertEqual(symbols[2].name, "doWork")
        XCTAssertEqual(symbols[2].kind, .function)
        XCTAssertEqual(symbols[2].parentID, actor.id)
    }
    
    func testActorWithNestedTypes() {
        let source = """
        actor DataManager {
            struct Item {
                var id: Int
            }
            
            enum State {
                case ready
                case processing
            }
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        // DataManager, Item, id, State, ready, processing
        XCTAssertEqual(symbols.count, 6)
        
        let names = symbols.map { $0.qualifiedName }
        XCTAssertTrue(names.contains("DataManager"))
        XCTAssertTrue(names.contains("DataManager.Item"))
        XCTAssertTrue(names.contains("DataManager.Item.id"))
        XCTAssertTrue(names.contains("DataManager.State"))
        XCTAssertTrue(names.contains("DataManager.State.ready"))
        XCTAssertTrue(names.contains("DataManager.State.processing"))
    }
    
    func testPublicActor() {
        let source = """
        public actor SharedActor {}
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].accessibility, .public)
        XCTAssertEqual(symbols[0].kind, .actor)
    }
    
    // MARK: - Operator Tests
    
    func testInfixOperator() {
        let source = """
        infix operator +++: AdditionPrecedence
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].name, "+++")
        XCTAssertEqual(symbols[0].kind, .operator)
    }
    
    func testPrefixOperator() {
        let source = """
        prefix operator !!!
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].name, "!!!")
        XCTAssertEqual(symbols[0].kind, .operator)
    }
    
    func testPostfixOperator() {
        let source = """
        postfix operator ???
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].name, "???")
        XCTAssertEqual(symbols[0].kind, .operator)
    }
    
    func testMultipleOperators() {
        let source = """
        infix operator <=>
        prefix operator ~~
        postfix operator ^^
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 3)
        XCTAssertTrue(symbols.allSatisfy { $0.kind == .operator })
        
        let names = symbols.map { $0.name }
        XCTAssertTrue(names.contains("<=>"))
        XCTAssertTrue(names.contains("~~"))
        XCTAssertTrue(names.contains("^^"))
    }
    
    // MARK: - Precedence Group Tests
    
    func testPrecedenceGroup() {
        let source = """
        precedencegroup MyPrecedence {
            higherThan: AdditionPrecedence
            lowerThan: MultiplicationPrecedence
            associativity: left
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].name, "MyPrecedence")
        XCTAssertEqual(symbols[0].kind, .precedenceGroup)
    }
    
    func testOperatorWithPrecedenceGroup() {
        let source = """
        precedencegroup PowerPrecedence {
            higherThan: MultiplicationPrecedence
            associativity: right
        }
        
        infix operator **: PowerPrecedence
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 2)
        
        let precedenceGroup = symbols.first { $0.kind == .precedenceGroup }
        let operatorSymbol = symbols.first { $0.kind == .operator }
        
        XCTAssertNotNil(precedenceGroup)
        XCTAssertNotNil(operatorSymbol)
        XCTAssertEqual(precedenceGroup?.name, "PowerPrecedence")
        XCTAssertEqual(operatorSymbol?.name, "**")
    }
    
    // MARK: - Macro Tests
    
    func testMacroDeclaration() {
        let source = """
        macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "MyMacros", type: "StringifyMacro")
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].name, "stringify")
        XCTAssertEqual(symbols[0].kind, .macro)
    }
    
    func testPublicMacro() {
        let source = """
        public macro log(_ message: String) = #externalMacro(module: "Logging", type: "LogMacro")
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].accessibility, .public)
        XCTAssertEqual(symbols[0].kind, .macro)
    }
    
    // MARK: - Multiple Variable Binding Tests
    
    func testMultipleVariableBindings() {
        let source = """
        let x = 1, y = 2, z = 3
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 3)
        
        let names = symbols.map { $0.name }
        XCTAssertTrue(names.contains("x"))
        XCTAssertTrue(names.contains("y"))
        XCTAssertTrue(names.contains("z"))
        
        XCTAssertTrue(symbols.allSatisfy { $0.kind == .variable })
    }
    
    func testMultipleVariableBindingsInStruct() {
        let source = """
        struct Point {
            var x: Int, y: Int
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        // Point, x, y
        XCTAssertEqual(symbols.count, 3)
        
        let structSymbol = symbols.first { $0.kind == .struct }!
        let properties = symbols.filter { $0.kind == .variable }
        
        XCTAssertEqual(properties.count, 2)
        XCTAssertTrue(properties.allSatisfy { $0.parentID == structSymbol.id })
        
        let names = properties.map { $0.name }
        XCTAssertTrue(names.contains("x"))
        XCTAssertTrue(names.contains("y"))
    }
    
    func testMixedLetVar() {
        let source = """
        class Config {
            let a = 1, b = 2
            var c = 3, d = 4
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        // Config, a, b, c, d
        XCTAssertEqual(symbols.count, 5)
        
        let variables = symbols.filter { $0.kind == .variable }
        XCTAssertEqual(variables.count, 4)
        
        let names = variables.map { $0.name }
        XCTAssertTrue(names.contains("a"))
        XCTAssertTrue(names.contains("b"))
        XCTAssertTrue(names.contains("c"))
        XCTAssertTrue(names.contains("d"))
    }
    
    // MARK: - Complex Integration Tests
    
    func testActorWithOperators() {
        let source = """
        infix operator <~>
        
        actor DataProcessor {
            var buffer: [Int] = []
            
            static func <~> (lhs: DataProcessor, rhs: DataProcessor) async -> DataProcessor {
                fatalError()
            }
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        // operator, actor, buffer, function
        XCTAssertEqual(symbols.count, 4)
        
        let operatorSymbol = symbols.first { $0.kind == .operator }
        let actorSymbol = symbols.first { $0.kind == .actor }
        
        XCTAssertNotNil(operatorSymbol)
        XCTAssertNotNil(actorSymbol)
        XCTAssertEqual(operatorSymbol?.name, "<~>")
        XCTAssertEqual(actorSymbol?.name, "DataProcessor")
    }
    
    func testAllNewSymbolKinds() {
        let source = """
        precedencegroup CustomPrecedence {
            associativity: left
        }
        
        infix operator <*>: CustomPrecedence
        
        actor MyActor {
            var value: Int = 0
        }
        
        macro debug(_ value: Int) = #externalMacro(module: "Debug", type: "DebugMacro")
        """
        
        let symbols = collectSymbols(from: source)
        
        let kinds = Set(symbols.map { $0.kind })
        
        XCTAssertTrue(kinds.contains(.precedenceGroup))
        XCTAssertTrue(kinds.contains(.operator))
        XCTAssertTrue(kinds.contains(.actor))
        XCTAssertTrue(kinds.contains(.macro))
        XCTAssertTrue(kinds.contains(.variable))
    }
    
    // MARK: - Edge Cases
    
    func testEmptyActor() {
        let source = """
        actor EmptyActor {}
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].kind, .actor)
    }
    
    func testActorWithInitializer() {
        let source = """
        actor Counter {
            var count: Int
            
            init(initial: Int) {
                self.count = initial
            }
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        // Counter, count, init
        XCTAssertEqual(symbols.count, 3)
        
        let initSymbol = symbols.first { $0.kind == .initializer }
        XCTAssertNotNil(initSymbol)
        XCTAssertEqual(initSymbol?.qualifiedName, "Counter.init")
    }
    
    func testNestedActorInClass() {
        // Note: Swift doesn't actually allow nested actors, but the collector should still handle the syntax
        let source = """
        class Container {
            func getActor() -> some Actor { fatalError() }
        }
        
        actor OutsideActor {}
        """
        
        let symbols = collectSymbols(from: source)
        
        // Container, getActor, OutsideActor
        XCTAssertEqual(symbols.count, 3)
        
        let actorSymbol = symbols.first { $0.kind == .actor }
        XCTAssertNotNil(actorSymbol)
        XCTAssertNil(actorSymbol?.parentID) // OutsideActor is top-level
    }
    
    func testAttributedActor() {
        let source = """
        @globalActor
        actor MyGlobalActor {
            static let shared = MyGlobalActor()
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        // MyGlobalActor, shared
        XCTAssertEqual(symbols.count, 2)
        
        let actorSymbol = symbols.first { $0.kind == .actor }!
        XCTAssertTrue(actorSymbol.attributes.contains { $0.name == "globalActor" })
    }
}
