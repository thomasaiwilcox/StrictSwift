import XCTest
@testable import StrictSwiftCore
import SwiftParser
import SwiftSyntax

/// Tests for Phase 3 Reference Collection
final class ReferenceCollectorTests: XCTestCase {
    
    private func collectReferences(from source: String, moduleName: String = "TestModule") -> [SymbolReference] {
        let url = URL(fileURLWithPath: "/test.swift")
        let tree = Parser.parse(source: source)
        let collector = ReferenceCollector(fileURL: url, tree: tree, moduleName: moduleName)
        collector.walk(tree)
        return collector.references
    }
    
    // MARK: - Function Call Tests
    
    func testSimpleFunctionCall() {
        let source = """
        func caller() {
            targetFunction()
        }
        """
        
        let refs = collectReferences(from: source)
        let functionCallRefs = refs.filter { $0.kind == .functionCall }
        
        XCTAssertTrue(functionCallRefs.contains { $0.referencedName == "targetFunction" })
    }
    
    func testMethodCall() {
        let source = """
        func test() {
            object.doSomething()
        }
        """
        
        let refs = collectReferences(from: source)
        let functionCallRefs = refs.filter { $0.kind == .functionCall }
        
        XCTAssertTrue(functionCallRefs.contains { $0.referencedName == "doSomething" })
    }
    
    func testChainedMethodCalls() {
        let source = """
        func test() {
            object.first().second().third()
        }
        """
        
        let refs = collectReferences(from: source)
        let functionCallRefs = refs.filter { $0.kind == .functionCall }
        
        let names = functionCallRefs.map { $0.referencedName }
        XCTAssertTrue(names.contains("first"))
        XCTAssertTrue(names.contains("second"))
        XCTAssertTrue(names.contains("third"))
    }
    
    func testStaticMethodCall() {
        let source = """
        func test() {
            MyType.staticMethod()
        }
        """
        
        let refs = collectReferences(from: source)
        let functionCallRefs = refs.filter { $0.kind == .functionCall }
        
        XCTAssertTrue(functionCallRefs.contains { 
            $0.referencedName == "staticMethod" && $0.inferredBaseType == "MyType"
        })
    }
    
    // MARK: - Initializer Tests
    
    func testInitializerCall() {
        let source = """
        func test() {
            let x = MyClass()
        }
        """
        
        let refs = collectReferences(from: source)
        let initRefs = refs.filter { $0.kind == .initializer }
        
        XCTAssertTrue(initRefs.contains { $0.referencedName == "MyClass" })
    }
    
    func testInitializerWithArguments() {
        let source = """
        func test() {
            let point = Point(x: 10, y: 20)
        }
        """
        
        let refs = collectReferences(from: source)
        let initRefs = refs.filter { $0.kind == .initializer }
        
        XCTAssertTrue(initRefs.contains { $0.referencedName == "Point" })
    }
    
    // MARK: - Property Access Tests
    
    func testPropertyAccess() {
        let source = """
        func test() {
            let x = object.property
        }
        """
        
        let refs = collectReferences(from: source)
        let propertyRefs = refs.filter { $0.kind == .propertyAccess || $0.kind == .enumCase }
        
        XCTAssertTrue(propertyRefs.contains { $0.referencedName == "property" })
    }
    
    func testChainedPropertyAccess() {
        let source = """
        func test() {
            let x = object.first.second.third
        }
        """
        
        let refs = collectReferences(from: source)
        let propertyRefs = refs.filter { $0.kind == .propertyAccess || $0.kind == .enumCase }
        
        let names = propertyRefs.map { $0.referencedName }
        XCTAssertTrue(names.contains("first"))
        XCTAssertTrue(names.contains("second"))
        XCTAssertTrue(names.contains("third"))
    }
    
    // MARK: - Enum Case Tests
    
    func testEnumCaseAccess() {
        let source = """
        func test() {
            let status = Status.active
        }
        """
        
        let refs = collectReferences(from: source)
        let enumRefs = refs.filter { $0.kind == .enumCase }
        
        XCTAssertTrue(enumRefs.contains { 
            $0.referencedName == "active" && $0.inferredBaseType == "Status"
        })
    }
    
    func testEnumCaseInSwitch() {
        let source = """
        func test(_ status: Status) {
            switch status {
            case .active:
                break
            case .inactive:
                break
            }
        }
        """
        
        let refs = collectReferences(from: source)
        let enumRefs = refs.filter { $0.kind == .enumCase || $0.kind == .propertyAccess }
        
        let names = enumRefs.map { $0.referencedName }
        XCTAssertTrue(names.contains("active"))
        XCTAssertTrue(names.contains("inactive"))
    }
    
    // MARK: - Identifier Reference Tests
    
    func testIdentifierReference() {
        let source = """
        func test() {
            let x = someVariable
        }
        """
        
        let refs = collectReferences(from: source)
        let identifierRefs = refs.filter { $0.kind == .identifier }
        
        XCTAssertTrue(identifierRefs.contains { $0.referencedName == "someVariable" })
    }
    
    func testSelfNotRecorded() {
        let source = """
        class MyClass {
            func test() {
                self.doSomething()
            }
        }
        """
        
        let refs = collectReferences(from: source)
        
        // 'self' should not be recorded as an identifier reference
        XCTAssertFalse(refs.contains { $0.referencedName == "self" })
    }
    
    func testSuperNotRecorded() {
        let source = """
        class SubClass: SuperClass {
            override func test() {
                super.test()
            }
        }
        """
        
        let refs = collectReferences(from: source)
        
        // 'super' should not be recorded as an identifier reference
        XCTAssertFalse(refs.contains { $0.referencedName == "super" })
    }
    
    // MARK: - Type Reference Tests
    
    func testTypeAnnotation() {
        let source = """
        let x: MyCustomType = getValue()
        """
        
        let refs = collectReferences(from: source)
        let typeRefs = refs.filter { $0.kind == .typeReference }
        
        XCTAssertTrue(typeRefs.contains { $0.referencedName == "MyCustomType" })
    }
    
    func testParameterType() {
        let source = """
        func process(item: CustomItem) {}
        """
        
        let refs = collectReferences(from: source)
        let typeRefs = refs.filter { $0.kind == .typeReference }
        
        XCTAssertTrue(typeRefs.contains { $0.referencedName == "CustomItem" })
    }
    
    func testReturnType() {
        let source = """
        func create() -> CustomResult {
            fatalError()
        }
        """
        
        let refs = collectReferences(from: source)
        let typeRefs = refs.filter { $0.kind == .typeReference }
        
        XCTAssertTrue(typeRefs.contains { $0.referencedName == "CustomResult" })
    }
    
    func testBuiltInTypesExcluded() {
        let source = """
        let a: Int = 1
        let b: String = "hello"
        let c: Bool = true
        let d: Double = 1.0
        """
        
        let refs = collectReferences(from: source)
        let typeRefs = refs.filter { $0.kind == .typeReference }
        
        // Built-in types should be excluded
        XCTAssertFalse(typeRefs.contains { $0.referencedName == "Int" })
        XCTAssertFalse(typeRefs.contains { $0.referencedName == "String" })
        XCTAssertFalse(typeRefs.contains { $0.referencedName == "Bool" })
        XCTAssertFalse(typeRefs.contains { $0.referencedName == "Double" })
    }
    
    func testOptionalType() {
        let source = """
        let x: MyType? = nil
        """
        
        let refs = collectReferences(from: source)
        let typeRefs = refs.filter { $0.kind == .typeReference }
        
        XCTAssertTrue(typeRefs.contains { $0.referencedName == "MyType" })
    }
    
    // MARK: - Generic Type Tests
    
    func testGenericTypeArgument() {
        let source = """
        let items: Container<CustomItem> = Container()
        """
        
        let refs = collectReferences(from: source)
        
        // Container should be a type reference
        let typeRefs = refs.filter { $0.kind == .typeReference }
        XCTAssertTrue(typeRefs.contains { $0.referencedName == "Container" })
        
        // CustomItem should be a generic argument
        let genericRefs = refs.filter { $0.kind == .genericArgument }
        XCTAssertTrue(genericRefs.contains { $0.referencedName == "CustomItem" })
    }
    
    func testBuiltInGenericsExcluded() {
        let source = """
        let items: Array<Int> = []
        """
        
        let refs = collectReferences(from: source)
        
        // Array and Int are built-in, should be excluded
        XCTAssertFalse(refs.contains { $0.referencedName == "Array" })
        XCTAssertFalse(refs.contains { $0.referencedName == "Int" })
    }
    
    // MARK: - Inheritance Tests
    
    func testInheritance() {
        let source = """
        class SubClass: BaseClass {}
        """
        
        let refs = collectReferences(from: source)
        let conformanceRefs = refs.filter { $0.kind == .conformance }
        
        XCTAssertTrue(conformanceRefs.contains { $0.referencedName == "BaseClass" })
    }
    
    func testProtocolConformance() {
        let source = """
        struct MyStruct: MyProtocol {}
        """
        
        let refs = collectReferences(from: source)
        let conformanceRefs = refs.filter { $0.kind == .conformance }
        
        XCTAssertTrue(conformanceRefs.contains { $0.referencedName == "MyProtocol" })
    }
    
    func testMultipleConformances() {
        let source = """
        class MyClass: BaseClass, Protocol1, Protocol2 {}
        """
        
        let refs = collectReferences(from: source)
        let conformanceRefs = refs.filter { $0.kind == .conformance }
        
        let names = conformanceRefs.map { $0.referencedName }
        XCTAssertTrue(names.contains("BaseClass"))
        XCTAssertTrue(names.contains("Protocol1"))
        XCTAssertTrue(names.contains("Protocol2"))
    }
    
    // MARK: - Extension Tests
    
    func testExtensionTarget() {
        let source = """
        extension MyType {
            func newMethod() {}
        }
        """
        
        let refs = collectReferences(from: source)
        let extensionRefs = refs.filter { $0.kind == .extensionTarget }
        
        XCTAssertTrue(extensionRefs.contains { $0.referencedName == "MyType" })
    }
    
    func testExtensionWithConformance() {
        let source = """
        extension MyType: SomeProtocol {}
        """
        
        let refs = collectReferences(from: source)
        
        // MyType as extension target
        let extensionRefs = refs.filter { $0.kind == .extensionTarget }
        XCTAssertTrue(extensionRefs.contains { $0.referencedName == "MyType" })
        
        // SomeProtocol as conformance
        let conformanceRefs = refs.filter { $0.kind == .conformance }
        XCTAssertTrue(conformanceRefs.contains { $0.referencedName == "SomeProtocol" })
    }
    
    // MARK: - Scope Context Tests
    
    func testScopeContextInClass() {
        let source = """
        class MyClass {
            func myMethod() {
                targetFunction()
            }
        }
        """
        
        let refs = collectReferences(from: source)
        let targetRef = refs.first { $0.referencedName == "targetFunction" }
        
        XCTAssertNotNil(targetRef)
        XCTAssertEqual(targetRef?.scopeContext, "MyClass.myMethod")
    }
    
    func testScopeContextInNestedTypes() {
        let source = """
        class Outer {
            struct Inner {
                func innerMethod() {
                    helper()
                }
            }
        }
        """
        
        let refs = collectReferences(from: source)
        let helperRef = refs.first { $0.referencedName == "helper" }
        
        XCTAssertNotNil(helperRef)
        XCTAssertEqual(helperRef?.scopeContext, "Outer.Inner.innerMethod")
    }
    
    func testScopeContextInExtension() {
        let source = """
        extension MyType {
            func extensionMethod() {
                doWork()
            }
        }
        """
        
        let refs = collectReferences(from: source)
        let workRef = refs.first { $0.referencedName == "doWork" }
        
        XCTAssertNotNil(workRef)
        XCTAssertEqual(workRef?.scopeContext, "MyType.extensionMethod")
    }
    
    // MARK: - Complex Scenario Tests
    
    func testComplexExpression() {
        let source = """
        func process() {
            let result = Factory.create().transform(using: Helper())
        }
        """
        
        let refs = collectReferences(from: source)
        
        // Should capture: create (function), transform (function), Helper (initializer)
        let funcRefs = refs.filter { $0.kind == .functionCall }
        let initRefs = refs.filter { $0.kind == .initializer }
        
        XCTAssertTrue(funcRefs.contains { $0.referencedName == "create" })
        XCTAssertTrue(funcRefs.contains { $0.referencedName == "transform" })
        XCTAssertTrue(initRefs.contains { $0.referencedName == "Helper" })
    }
    
    func testActorReferences() {
        let source = """
        actor MyActor {
            func process() {
                Helper.doWork()
            }
        }
        """
        
        let refs = collectReferences(from: source)
        let funcRefs = refs.filter { $0.kind == .functionCall }
        
        XCTAssertTrue(funcRefs.contains { $0.referencedName == "doWork" })
    }
    
    func testClosureReferences() {
        let source = """
        func test() {
            items.map { item in
                transform(item)
            }
        }
        """
        
        let refs = collectReferences(from: source)
        let funcRefs = refs.filter { $0.kind == .functionCall }
        
        XCTAssertTrue(funcRefs.contains { $0.referencedName == "map" })
        XCTAssertTrue(funcRefs.contains { $0.referencedName == "transform" })
    }
    
    // MARK: - Reference Location Tests
    
    func testReferenceHasCorrectLocation() {
        let source = """
        func test() {
            myFunction()
        }
        """
        
        let refs = collectReferences(from: source)
        let funcRef = refs.first { $0.referencedName == "myFunction" }
        
        XCTAssertNotNil(funcRef)
        // Reference location should be where the identifier appears
        XCTAssertTrue(funcRef?.location.line ?? 0 > 0)
    }
}
