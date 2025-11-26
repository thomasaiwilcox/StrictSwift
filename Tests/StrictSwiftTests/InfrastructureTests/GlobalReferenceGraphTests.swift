import XCTest
import SwiftSyntax
import SwiftParser
@testable import StrictSwiftCore

final class GlobalReferenceGraphTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private func createSymbol(
        name: String,
        qualifiedName: String,
        kind: SymbolKind,
        moduleName: String = "TestModule",
        file: String = "/test.swift",
        line: Int = 1,
        column: Int = 1,
        parentID: SymbolID? = nil
    ) -> Symbol {
        let location = Location(file: URL(fileURLWithPath: file), line: line, column: column)
        let id = SymbolID.create(moduleName: moduleName, qualifiedName: qualifiedName, kind: kind, filePath: file, line: line)
        return Symbol(
            id: id,
            name: name,
            qualifiedName: qualifiedName,
            kind: kind,
            location: location,
            accessibility: .internal,
            attributes: [],
            parentID: parentID
        )
    }
    
    private func createReference(
        name: String,
        kind: ReferenceKind,
        file: String = "/test.swift",
        line: Int = 1,
        column: Int = 1,
        scopeContext: String = "",
        inferredBaseType: String? = nil
    ) -> SymbolReference {
        let location = Location(file: URL(fileURLWithPath: file), line: line, column: column)
        return SymbolReference(
            referencedName: name,
            fullExpression: name,
            kind: kind,
            location: location,
            scopeContext: scopeContext,
            inferredBaseType: inferredBaseType
        )
    }
    
    private func createSourceFile(
        url: URL,
        source: String,
        moduleName: String = "TestModule"
    ) -> SourceFile {
        return SourceFile(url: url, source: source, moduleName: moduleName)
    }
    
    // MARK: - Symbol Registration Tests
    
    func testRegisterSymbol() {
        let graph = GlobalReferenceGraph()
        let symbol = createSymbol(name: "MyClass", qualifiedName: "MyClass", kind: .class)
        
        graph.registerSymbol(symbol)
        
        XCTAssertEqual(graph.symbolCount, 1)
        XCTAssertNotNil(graph.symbol(for: symbol.id))
        XCTAssertEqual(graph.symbol(for: symbol.id)?.name, "MyClass")
    }
    
    func testSymbolsByName() {
        let graph = GlobalReferenceGraph()
        let symbol1 = createSymbol(name: "Config", qualifiedName: "ModuleA.Config", kind: .struct, file: "/a.swift")
        let symbol2 = createSymbol(name: "Config", qualifiedName: "ModuleB.Config", kind: .struct, file: "/b.swift")
        
        graph.registerSymbol(symbol1)
        graph.registerSymbol(symbol2)
        
        let configs = graph.symbols(named: "Config")
        XCTAssertEqual(configs.count, 2)
    }
    
    func testSymbolsByQualifiedName() {
        let graph = GlobalReferenceGraph()
        let symbol = createSymbol(name: "Config", qualifiedName: "ModuleA.Config", kind: .struct)
        
        graph.registerSymbol(symbol)
        
        let results = graph.symbols(qualifiedName: "ModuleA.Config")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Config")
        
        let empty = graph.symbols(qualifiedName: "NonExistent.Config")
        XCTAssertTrue(empty.isEmpty)
    }
    
    func testSymbolsInScope() {
        let graph = GlobalReferenceGraph()
        let classSymbol = createSymbol(name: "MyClass", qualifiedName: "MyClass", kind: .class, line: 1)
        let method1 = createSymbol(name: "method1", qualifiedName: "MyClass.method1", kind: .function, line: 2)
        let method2 = createSymbol(name: "method2", qualifiedName: "MyClass.method2", kind: .function, line: 3)
        let otherFunc = createSymbol(name: "otherFunc", qualifiedName: "otherFunc", kind: .function, line: 4)
        
        graph.registerSymbol(classSymbol)
        graph.registerSymbol(method1)
        graph.registerSymbol(method2)
        graph.registerSymbol(otherFunc)
        
        let inClassScope = graph.symbolsInScope("MyClass")
        XCTAssertEqual(inClassScope.count, 3) // class + 2 methods
        XCTAssertTrue(inClassScope.contains { $0.name == "method1" })
        XCTAssertTrue(inClassScope.contains { $0.name == "method2" })
    }
    
    func testSymbolsInFile() {
        let graph = GlobalReferenceGraph()
        let file1 = URL(fileURLWithPath: "/file1.swift")
        let file2 = URL(fileURLWithPath: "/file2.swift")
        
        let symbol1 = createSymbol(name: "A", qualifiedName: "A", kind: .class, file: "/file1.swift")
        let symbol2 = createSymbol(name: "B", qualifiedName: "B", kind: .class, file: "/file1.swift", line: 2)
        let symbol3 = createSymbol(name: "C", qualifiedName: "C", kind: .class, file: "/file2.swift")
        
        graph.registerSymbol(symbol1)
        graph.registerSymbol(symbol2)
        graph.registerSymbol(symbol3)
        
        let file1Symbols = graph.symbols(inFile: file1)
        XCTAssertEqual(file1Symbols.count, 2)
        
        let file2Symbols = graph.symbols(inFile: file2)
        XCTAssertEqual(file2Symbols.count, 1)
    }
    
    // MARK: - Edge Management Tests
    
    func testAddEdge() {
        let graph = GlobalReferenceGraph()
        let classA = createSymbol(name: "A", qualifiedName: "A", kind: .class, line: 1)
        let classB = createSymbol(name: "B", qualifiedName: "B", kind: .class, line: 2)
        
        graph.registerSymbol(classA)
        graph.registerSymbol(classB)
        graph.addEdge(from: classA.id, to: classB.id)
        
        XCTAssertEqual(graph.edgeCount, 1)
        XCTAssertTrue(graph.getReferences(classA.id).contains(classB.id))
        XCTAssertTrue(graph.getReferencedBy(classB.id).contains(classA.id))
    }
    
    func testBidirectionalEdges() {
        let graph = GlobalReferenceGraph()
        let classA = createSymbol(name: "A", qualifiedName: "A", kind: .class, line: 1)
        let classB = createSymbol(name: "B", qualifiedName: "B", kind: .class, line: 2)
        
        graph.registerSymbol(classA)
        graph.registerSymbol(classB)
        graph.addEdge(from: classA.id, to: classB.id)
        graph.addEdge(from: classB.id, to: classA.id)
        
        XCTAssertEqual(graph.edgeCount, 2)
        XCTAssertTrue(graph.getReferences(classA.id).contains(classB.id))
        XCTAssertTrue(graph.getReferences(classB.id).contains(classA.id))
    }
    
    // MARK: - Protocol Conformance Tests
    
    func testProtocolConformance() {
        let graph = GlobalReferenceGraph()
        
        let protocolSymbol = createSymbol(name: "MyProtocol", qualifiedName: "MyProtocol", kind: .protocol, line: 1)
        let classSymbol = createSymbol(name: "MyClass", qualifiedName: "MyClass", kind: .class, line: 5)
        
        graph.registerSymbol(protocolSymbol)
        graph.registerSymbol(classSymbol)
        graph.addProtocolConformance(type: classSymbol.id, protocol: protocolSymbol.id)
        
        let conformedProtocols = graph.getConformedProtocols(classSymbol.id)
        XCTAssertEqual(conformedProtocols.count, 1)
        XCTAssertTrue(conformedProtocols.contains(protocolSymbol.id))
    }
    
    func testProtocolImplementation() {
        let graph = GlobalReferenceGraph()
        
        let protocolSymbol = createSymbol(name: "MyProtocol", qualifiedName: "MyProtocol", kind: .protocol, line: 1)
        let protocolMethod = createSymbol(
            name: "doSomething",
            qualifiedName: "MyProtocol.doSomething",
            kind: .function,
            line: 2,
            parentID: protocolSymbol.id
        )
        
        let classSymbol = createSymbol(name: "MyClass", qualifiedName: "MyClass", kind: .class, line: 5)
        let classMethod = createSymbol(
            name: "doSomething",
            qualifiedName: "MyClass.doSomething",
            kind: .function,
            line: 6,
            parentID: classSymbol.id
        )
        
        graph.registerSymbol(protocolSymbol)
        graph.registerSymbol(protocolMethod)
        graph.registerSymbol(classSymbol)
        graph.registerSymbol(classMethod)
        
        graph.addProtocolImplementation(protocolMethod: protocolMethod.id, implementingMethod: classMethod.id)
        
        let implementations = graph.getImplementingMethods(protocolMethod.id)
        XCTAssertEqual(implementations.count, 1)
        XCTAssertTrue(implementations.contains(classMethod.id))
    }
    
    func testGetProtocolRequirements() {
        let graph = GlobalReferenceGraph()
        
        let protocolSymbol = createSymbol(name: "MyProtocol", qualifiedName: "MyProtocol", kind: .protocol, line: 1)
        let method1 = createSymbol(
            name: "method1",
            qualifiedName: "MyProtocol.method1",
            kind: .function,
            line: 2,
            parentID: protocolSymbol.id
        )
        let property1 = createSymbol(
            name: "value",
            qualifiedName: "MyProtocol.value",
            kind: .variable,
            line: 3,
            parentID: protocolSymbol.id
        )
        
        graph.registerSymbol(protocolSymbol)
        graph.registerSymbol(method1)
        graph.registerSymbol(property1)
        
        let requirements = graph.getProtocolRequirements(protocolSymbol.id)
        XCTAssertEqual(requirements.count, 2)
        XCTAssertTrue(requirements.contains { $0.name == "method1" })
        XCTAssertTrue(requirements.contains { $0.name == "value" })
    }
    
    // MARK: - Associated Type Tests
    
    func testAssociatedTypeBinding() {
        let graph = GlobalReferenceGraph()
        
        let intType = createSymbol(name: "Int", qualifiedName: "Int", kind: .struct, line: 1)
        let conformingType = createSymbol(name: "IntContainer", qualifiedName: "IntContainer", kind: .struct, line: 5)
        
        graph.registerSymbol(intType)
        graph.registerSymbol(conformingType)
        
        graph.addAssociatedTypeBinding(
            conformingType: conformingType.id,
            associatedTypeName: "Element",
            concreteType: intType.id
        )
        
        let binding = graph.getAssociatedTypeBinding(conformingType.id, associatedType: "Element")
        XCTAssertEqual(binding, intType.id)
        
        let noBinding = graph.getAssociatedTypeBinding(conformingType.id, associatedType: "NonExistent")
        XCTAssertNil(noBinding)
    }
    
    // MARK: - Conditional Conformance Tests
    
    func testConditionalConformance() {
        let graph = GlobalReferenceGraph()
        
        let arrayType = createSymbol(name: "Array", qualifiedName: "Array", kind: .struct, line: 1)
        graph.registerSymbol(arrayType)
        
        let conformance = ConditionalConformance(
            conformingTypeID: arrayType.id,
            protocolName: "Equatable",
            requirements: [.conformance(typeParam: "Element", protocolName: "Equatable")],
            location: Location(file: URL(fileURLWithPath: "/test.swift"), line: 10, column: 1)
        )
        
        graph.addConditionalConformance(conformance)
        
        let conformances = graph.getConditionalConformances(arrayType.id)
        XCTAssertEqual(conformances.count, 1)
        XCTAssertEqual(conformances.first?.protocolName, "Equatable")
        XCTAssertEqual(conformances.first?.requirements.count, 1)
    }
    
    func testWhereRequirementEquality() {
        let req1 = WhereRequirement.conformance(typeParam: "T", protocolName: "Equatable")
        let req2 = WhereRequirement.conformance(typeParam: "T", protocolName: "Equatable")
        let req3 = WhereRequirement.sameType(typeParam: "T", concreteType: "Int")
        
        XCTAssertEqual(req1, req2)
        XCTAssertNotEqual(req1, req3)
    }
    
    // MARK: - Reference Resolution Tests
    
    func testResolveReferenceByName() {
        let graph = GlobalReferenceGraph()
        let url = URL(fileURLWithPath: "/test.swift")
        
        let classSymbol = createSymbol(name: "MyClass", qualifiedName: "MyClass", kind: .class)
        graph.registerSymbol(classSymbol)
        
        let file = SourceFile(url: url, source: "", moduleName: "TestModule")
        
        let ref = createReference(name: "MyClass", kind: .typeReference)
        let resolved = graph.resolveReference(ref, fromFile: file)
        
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first, classSymbol.id)
    }
    
    func testResolveReferenceKindCompatibility() {
        let graph = GlobalReferenceGraph()
        let url = URL(fileURLWithPath: "/test.swift")
        
        let classSymbol = createSymbol(name: "Thing", qualifiedName: "Thing", kind: .class, line: 1)
        let funcSymbol = createSymbol(name: "Thing", qualifiedName: "thing", kind: .function, line: 2)
        
        graph.registerSymbol(classSymbol)
        graph.registerSymbol(funcSymbol)
        
        let file = SourceFile(url: url, source: "", moduleName: "TestModule")
        
        // Type reference should match class
        let typeRef = createReference(name: "Thing", kind: .typeReference)
        let typeResolved = graph.resolveReference(typeRef, fromFile: file)
        XCTAssertTrue(typeResolved.contains(classSymbol.id))
        
        // Function call should match function
        let funcRef = createReference(name: "Thing", kind: .functionCall)
        let funcResolved = graph.resolveReference(funcRef, fromFile: file)
        XCTAssertTrue(funcResolved.contains(funcSymbol.id))
    }
    
    func testResolveReferenceWithInferredBaseType() {
        let graph = GlobalReferenceGraph()
        let url = URL(fileURLWithPath: "/test.swift")
        
        let classA = createSymbol(name: "MyClass", qualifiedName: "MyClass", kind: .class, line: 1)
        let methodA = createSymbol(name: "doWork", qualifiedName: "MyClass.doWork", kind: .function, line: 2)
        let methodB = createSymbol(name: "doWork", qualifiedName: "OtherClass.doWork", kind: .function, line: 3)
        
        graph.registerSymbol(classA)
        graph.registerSymbol(methodA)
        graph.registerSymbol(methodB)
        
        let file = SourceFile(url: url, source: "", moduleName: "TestModule")
        
        // Reference with inferred base type should prefer matching type
        let ref = createReference(name: "doWork", kind: .functionCall, inferredBaseType: "MyClass")
        let resolved = graph.resolveReference(ref, fromFile: file)
        
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first, methodA.id)
    }
    
    func testUnresolvedReference() {
        let graph = GlobalReferenceGraph()
        let url = URL(fileURLWithPath: "/test.swift")
        
        let source = """
        class MyClass {
            func test() {
                nonExistentFunction()
            }
        }
        """
        
        let file = createSourceFile(url: url, source: source)
        graph.build(from: [file])
        
        // There should be unresolved references
        XCTAssertFalse(graph.unresolvedReferences.isEmpty)
    }
    
    // MARK: - Graph Construction Tests
    
    func testBuildFromSourceFiles() {
        let graph = GlobalReferenceGraph()
        let url = URL(fileURLWithPath: "/test.swift")
        
        let source = """
        class MyClass {
            var value: Int = 0
            func getValue() -> Int {
                return value
            }
        }
        """
        
        let file = createSourceFile(url: url, source: source)
        graph.build(from: [file])
        
        XCTAssertGreaterThan(graph.symbolCount, 0)
        
        // Check that class is registered
        let classes = graph.symbols(named: "MyClass")
        XCTAssertEqual(classes.count, 1)
        
        // Check that method is registered
        let methods = graph.symbols(named: "getValue")
        XCTAssertEqual(methods.count, 1)
    }
    
    func testBuildWithProtocolConformance() {
        let graph = GlobalReferenceGraph()
        let url = URL(fileURLWithPath: "/test.swift")
        
        let source = """
        protocol Greeter {
            func greet()
        }
        
        class Person: Greeter {
            func greet() {
                print("Hello")
            }
        }
        """
        
        let file = createSourceFile(url: url, source: source)
        graph.build(from: [file])
        
        // Find the protocol and class
        let protocols = graph.symbols(named: "Greeter")
        let classes = graph.symbols(named: "Person")
        
        XCTAssertEqual(protocols.count, 1)
        XCTAssertEqual(classes.count, 1)
        
        // Check conformance relationship
        if let personClass = classes.first {
            let conformed = graph.getConformedProtocols(personClass.id)
            XCTAssertGreaterThan(conformed.count, 0)
        }
    }
    
    // MARK: - Incremental Update Tests
    
    func testAddFile() {
        let graph = GlobalReferenceGraph()
        let url = URL(fileURLWithPath: "/test.swift")
        
        let source = """
        class NewClass {
            func newMethod() {}
        }
        """
        
        let file = createSourceFile(url: url, source: source)
        
        XCTAssertEqual(graph.symbolCount, 0)
        
        graph.addFile(file)
        
        XCTAssertGreaterThan(graph.symbolCount, 0)
        XCTAssertEqual(graph.symbols(named: "NewClass").count, 1)
    }
    
    func testRemoveFile() {
        let graph = GlobalReferenceGraph()
        let url = URL(fileURLWithPath: "/test.swift")
        
        let source = """
        class ToRemove {
            func method() {}
        }
        """
        
        let file = createSourceFile(url: url, source: source)
        graph.addFile(file)
        
        XCTAssertEqual(graph.symbols(named: "ToRemove").count, 1)
        
        graph.removeFile(url)
        
        XCTAssertEqual(graph.symbols(named: "ToRemove").count, 0)
        XCTAssertEqual(graph.symbols(inFile: url).count, 0)
    }
    
    func testUpdateFile() {
        let graph = GlobalReferenceGraph()
        let url = URL(fileURLWithPath: "/test.swift")
        
        // Original file
        let source1 = """
        class OriginalClass {}
        """
        let file1 = createSourceFile(url: url, source: source1)
        graph.addFile(file1)
        
        XCTAssertEqual(graph.symbols(named: "OriginalClass").count, 1)
        XCTAssertEqual(graph.symbols(named: "UpdatedClass").count, 0)
        
        // Updated file
        let source2 = """
        class UpdatedClass {}
        """
        let file2 = createSourceFile(url: url, source: source2)
        graph.updateFile(file2)
        
        XCTAssertEqual(graph.symbols(named: "OriginalClass").count, 0)
        XCTAssertEqual(graph.symbols(named: "UpdatedClass").count, 1)
    }
    
    func testClear() {
        let graph = GlobalReferenceGraph()
        let url = URL(fileURLWithPath: "/test.swift")
        
        let source = """
        class MyClass {}
        """
        
        let file = createSourceFile(url: url, source: source)
        graph.addFile(file)
        
        XCTAssertGreaterThan(graph.symbolCount, 0)
        
        graph.clear()
        
        XCTAssertEqual(graph.symbolCount, 0)
        XCTAssertEqual(graph.edgeCount, 0)
    }
    
    // MARK: - Statistics Tests
    
    func testSymbolCount() {
        let graph = GlobalReferenceGraph()
        
        XCTAssertEqual(graph.symbolCount, 0)
        
        let symbol = createSymbol(name: "A", qualifiedName: "A", kind: .class)
        graph.registerSymbol(symbol)
        
        XCTAssertEqual(graph.symbolCount, 1)
    }
    
    func testEdgeCount() {
        let graph = GlobalReferenceGraph()
        
        XCTAssertEqual(graph.edgeCount, 0)
        
        let a = createSymbol(name: "A", qualifiedName: "A", kind: .class, line: 1)
        let b = createSymbol(name: "B", qualifiedName: "B", kind: .class, line: 2)
        let c = createSymbol(name: "C", qualifiedName: "C", kind: .class, line: 3)
        
        graph.registerSymbol(a)
        graph.registerSymbol(b)
        graph.registerSymbol(c)
        
        graph.addEdge(from: a.id, to: b.id)
        graph.addEdge(from: a.id, to: c.id)
        graph.addEdge(from: b.id, to: c.id)
        
        XCTAssertEqual(graph.edgeCount, 3)
    }
}
