import XCTest
@testable import StrictSwiftCore
import SwiftParser
import SwiftSyntax

/// Tests for Symbol and SymbolID functionality
final class SymbolTests: XCTestCase {
    
    // MARK: - SymbolID Tests
    
    func testSymbolIDCreation() {
        let symbolID = SymbolID.create(
            moduleName: "MyModule",
            qualifiedName: "MyClass.myMethod",
            kind: .function,
            filePath: "/path/to/file.swift",
            line: 42
        )
        
        XCTAssertEqual(symbolID.moduleName, "MyModule")
        XCTAssertEqual(symbolID.qualifiedName, "MyClass.myMethod")
        XCTAssertEqual(symbolID.kind, .function)
        XCTAssertFalse(symbolID.locationHash.isEmpty)
    }
    
    func testSymbolIDStringFormat() {
        let symbolID = SymbolID.create(
            moduleName: "MyModule",
            qualifiedName: "MyClass",
            kind: .class,
            filePath: "/path/to/file.swift",
            line: 10
        )
        
        let idString = symbolID.id
        XCTAssertTrue(idString.contains("MyModule::"))
        XCTAssertTrue(idString.contains("::MyClass::"))
        XCTAssertTrue(idString.contains("::class::"))
    }
    
    func testSymbolIDEquality() {
        let id1 = SymbolID.create(
            moduleName: "Module",
            qualifiedName: "Class",
            kind: .class,
            filePath: "/path.swift",
            line: 1
        )
        
        let id2 = SymbolID.create(
            moduleName: "Module",
            qualifiedName: "Class",
            kind: .class,
            filePath: "/path.swift",
            line: 1
        )
        
        XCTAssertEqual(id1, id2)
        XCTAssertEqual(id1.hashValue, id2.hashValue)
    }
    
    func testSymbolIDDiffersByLocation() {
        let id1 = SymbolID.create(
            moduleName: "Module",
            qualifiedName: "Class",
            kind: .class,
            filePath: "/path.swift",
            line: 1
        )
        
        let id2 = SymbolID.create(
            moduleName: "Module",
            qualifiedName: "Class",
            kind: .class,
            filePath: "/path.swift",
            line: 100
        )
        
        XCTAssertNotEqual(id1, id2)
    }
    
    func testSymbolIDCodable() throws {
        let original = SymbolID.create(
            moduleName: "TestModule",
            qualifiedName: "TestClass.method",
            kind: .function,
            filePath: "/test.swift",
            line: 50
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SymbolID.self, from: data)
        
        XCTAssertEqual(original, decoded)
    }
    
    // MARK: - Symbol Tests
    
    func testSymbolWithID() {
        let location = Location(file: URL(fileURLWithPath: "/test.swift"), line: 10, column: 5)
        
        let symbol = Symbol(
            moduleName: "TestModule",
            name: "TestClass",
            qualifiedName: "TestClass",
            kind: .class,
            location: location,
            accessibility: .public
        )
        
        XCTAssertEqual(symbol.name, "TestClass")
        XCTAssertEqual(symbol.qualifiedName, "TestClass")
        XCTAssertEqual(symbol.id.moduleName, "TestModule")
        XCTAssertEqual(symbol.id.kind, .class)
        XCTAssertNil(symbol.parentID)
    }
    
    func testSymbolWithParent() {
        let location = Location(file: URL(fileURLWithPath: "/test.swift"), line: 10, column: 5)
        
        let parentID = SymbolID.create(
            moduleName: "TestModule",
            qualifiedName: "ParentClass",
            kind: .class,
            filePath: "/test.swift",
            line: 5
        )
        
        let symbol = Symbol(
            moduleName: "TestModule",
            name: "nestedMethod",
            qualifiedName: "ParentClass.nestedMethod",
            kind: .function,
            location: location,
            accessibility: .internal,
            parentID: parentID
        )
        
        XCTAssertEqual(symbol.qualifiedName, "ParentClass.nestedMethod")
        XCTAssertEqual(symbol.parentID, parentID)
    }
    
    func testSymbolCodable() throws {
        let location = Location(file: URL(fileURLWithPath: "/test.swift"), line: 10, column: 5)
        
        let original = Symbol(
            moduleName: "TestModule",
            name: "TestStruct",
            qualifiedName: "TestStruct",
            kind: .struct,
            location: location,
            accessibility: .internal,
            attributes: [Attribute(name: "frozen")]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Symbol.self, from: data)
        
        XCTAssertEqual(original, decoded)
    }
}

// MARK: - SymbolCollector Tests

final class SymbolCollectorTests: XCTestCase {
    
    private func collectSymbols(from source: String, moduleName: String = "TestModule") -> [Symbol] {
        let url = URL(fileURLWithPath: "/test.swift")
        let tree = Parser.parse(source: source)
        let collector = SymbolCollector(fileURL: url, tree: tree, moduleName: moduleName)
        collector.walk(tree)
        return collector.symbols
    }
    
    // MARK: - Basic Collection Tests
    
    func testCollectClass() {
        let source = """
        class MyClass {}
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].name, "MyClass")
        XCTAssertEqual(symbols[0].kind, .class)
        XCTAssertEqual(symbols[0].qualifiedName, "MyClass")
        XCTAssertNil(symbols[0].parentID)
    }
    
    func testCollectStruct() {
        let source = """
        struct MyStruct {}
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].name, "MyStruct")
        XCTAssertEqual(symbols[0].kind, .struct)
    }
    
    func testCollectEnum() {
        let source = """
        enum MyEnum {
            case first
            case second
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 3)
        XCTAssertEqual(symbols[0].name, "MyEnum")
        XCTAssertEqual(symbols[0].kind, .enum)
        XCTAssertEqual(symbols[1].name, "first")
        XCTAssertEqual(symbols[1].kind, .case)
        XCTAssertEqual(symbols[2].name, "second")
        XCTAssertEqual(symbols[2].kind, .case)
    }
    
    func testCollectProtocol() {
        let source = """
        protocol MyProtocol {
            func doSomething()
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[0].name, "MyProtocol")
        XCTAssertEqual(symbols[0].kind, .protocol)
        XCTAssertEqual(symbols[1].name, "doSomething")
        XCTAssertEqual(symbols[1].kind, .function)
    }
    
    // MARK: - Nested Symbol Tests
    
    func testNestedClass() {
        let source = """
        class Outer {
            class Inner {}
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 2)
        
        let outer = symbols[0]
        XCTAssertEqual(outer.name, "Outer")
        XCTAssertEqual(outer.qualifiedName, "Outer")
        XCTAssertNil(outer.parentID)
        
        let inner = symbols[1]
        XCTAssertEqual(inner.name, "Inner")
        XCTAssertEqual(inner.qualifiedName, "Outer.Inner")
        XCTAssertEqual(inner.parentID, outer.id)
    }
    
    func testNestedMethod() {
        let source = """
        struct MyStruct {
            func myMethod() {}
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 2)
        
        let structSymbol = symbols[0]
        let methodSymbol = symbols[1]
        
        XCTAssertEqual(methodSymbol.qualifiedName, "MyStruct.myMethod")
        XCTAssertEqual(methodSymbol.parentID, structSymbol.id)
    }
    
    func testDeeplyNestedSymbol() {
        let source = """
        class Level1 {
            struct Level2 {
                enum Level3 {
                    case value
                }
            }
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 4)
        
        XCTAssertEqual(symbols[0].qualifiedName, "Level1")
        XCTAssertEqual(symbols[1].qualifiedName, "Level1.Level2")
        XCTAssertEqual(symbols[2].qualifiedName, "Level1.Level2.Level3")
        XCTAssertEqual(symbols[3].qualifiedName, "Level1.Level2.Level3.value")
        
        // Verify parent chain
        XCTAssertNil(symbols[0].parentID)
        XCTAssertEqual(symbols[1].parentID, symbols[0].id)
        XCTAssertEqual(symbols[2].parentID, symbols[1].id)
        XCTAssertEqual(symbols[3].parentID, symbols[2].id)
    }
    
    // MARK: - Extension Tests
    
    func testExtension() {
        let source = """
        extension String {
            func customMethod() {}
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[0].name, "String")
        XCTAssertEqual(symbols[0].kind, .extension)
        XCTAssertEqual(symbols[1].name, "customMethod")
        XCTAssertEqual(symbols[1].qualifiedName, "String.customMethod")
    }
    
    // MARK: - Special Members Tests
    
    func testInitializer() {
        let source = """
        struct MyStruct {
            init() {}
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[1].name, "init")
        XCTAssertEqual(symbols[1].kind, .initializer)
        XCTAssertEqual(symbols[1].qualifiedName, "MyStruct.init")
    }
    
    func testDeinitializer() {
        let source = """
        class MyClass {
            deinit {}
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[1].name, "deinit")
        XCTAssertEqual(symbols[1].kind, .deinitializer)
    }
    
    func testSubscript() {
        let source = """
        struct MyStruct {
            subscript(index: Int) -> Int { return 0 }
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[1].name, "subscript")
        XCTAssertEqual(symbols[1].kind, .subscript)
    }
    
    func testTypeAlias() {
        let source = """
        struct MyStruct {
            typealias MyInt = Int
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[1].name, "MyInt")
        XCTAssertEqual(symbols[1].kind, .typeAlias)
    }
    
    func testAssociatedType() {
        let source = """
        protocol MyProtocol {
            associatedtype Element
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[1].name, "Element")
        XCTAssertEqual(symbols[1].kind, .associatedType)
    }
    
    // MARK: - Module Name Tests
    
    func testModuleNameInID() {
        let source = """
        class TestClass {}
        """
        
        let symbols = collectSymbols(from: source, moduleName: "CustomModule")
        
        XCTAssertEqual(symbols[0].id.moduleName, "CustomModule")
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityCollection() {
        let source = """
        public class PublicClass {}
        internal struct InternalStruct {}
        private enum PrivateEnum {}
        fileprivate protocol FileprivateProtocol {}
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 4)
        XCTAssertEqual(symbols[0].accessibility, .public)
        XCTAssertEqual(symbols[1].accessibility, .internal)
        XCTAssertEqual(symbols[2].accessibility, .private)
        XCTAssertEqual(symbols[3].accessibility, .fileprivate)
    }
    
    // MARK: - Attributes Tests
    
    func testAttributesCollection() {
        let source = """
        @available(iOS 13, *)
        @MainActor
        class MyClass {}
        """
        
        let symbols = collectSymbols(from: source)
        
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].attributes.count, 2)
        XCTAssertTrue(symbols[0].attributes.contains { $0.name == "available" })
        XCTAssertTrue(symbols[0].attributes.contains { $0.name == "MainActor" })
    }
    
    // MARK: - Complex Scenario Tests
    
    func testComplexNestedStructure() {
        let source = """
        class Container {
            struct Item {
                var value: Int
                
                func transform() {}
            }
            
            enum Status {
                case active
                case inactive
            }
            
            func process() {}
        }
        """
        
        let symbols = collectSymbols(from: source)
        
        // Container, Item, value, transform, Status, active, inactive, process
        XCTAssertEqual(symbols.count, 8)
        
        // Verify qualified names
        let names = symbols.map { $0.qualifiedName }
        XCTAssertTrue(names.contains("Container"))
        XCTAssertTrue(names.contains("Container.Item"))
        XCTAssertTrue(names.contains("Container.Item.value"))
        XCTAssertTrue(names.contains("Container.Item.transform"))
        XCTAssertTrue(names.contains("Container.Status"))
        XCTAssertTrue(names.contains("Container.Status.active"))
        XCTAssertTrue(names.contains("Container.Status.inactive"))
        XCTAssertTrue(names.contains("Container.process"))
    }
}
