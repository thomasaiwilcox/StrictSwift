// This file contains examples of code patterns that should NOT trigger exclusive access warnings
// These are false positives that were previously flagged incorrectly

import Foundation

// MARK: - Function Calls Should Not Be Flagged

class Analyzer {
    func process(file: SourceFile) {
        // This should NOT be flagged - analyze() is a method call, not storage access
        let result = analyze(file)
        print(result)
    }
    
    func analyze(_ file: SourceFile) -> String {
        return "Analyzed: \(file.name)"
    }
}

struct SourceFile {
    let name: String
}

// MARK: - Initializers Should Not Be Flagged

func processSymbols() {
    // This should NOT be flagged - Set<SymbolID>() is an initializer, not storage access
    var symbols: Set<String> = Set<String>()
    symbols.insert("test")
    print(symbols)
}

func createCollections() {
    // This should NOT be flagged - Array/Dictionary initializers
    let items = Array<Int>()
    let dict = Dictionary<String, Int>()
    print(items.count, dict.count)
}

// MARK: - Expression Results Should Not Be Flagged

func regexOperations() {
    let pattern = "test"
    let item = "test string"
    
    // This should NOT be flagged - NSRegularExpression() is an initializer
    if let regex = try? NSRegularExpression(pattern: pattern) {
        let range = NSRange(location: 0, length: item.utf16.count)
        let match = regex.firstMatch(in: item, range: range)
        print(match as Any)
    }
}

// MARK: - Async Calls Should Not Be Flagged

actor GraphState {
    private var references: [String] = []
    
    func getAllReferences() -> [String] {
        return references
    }
}

func processGraph(graphState: GraphState) async {
    // This should NOT be flagged - await graphState.getAllReferences() is a method call
    let refs = await graphState.getAllReferences()
    print(refs)
}

// MARK: - Method Chains Should Not Be Flagged

func sourceOperations(sourceFile: SourceFile) {
    // This should NOT be flagged - sourceFile.name is a property read, not exclusive access
    let name = sourceFile.name
    print(name)
}

// MARK: - Real Exclusive Access SHOULD Be Flagged

class Counter {
    var value: Int = 0
    
    func increment() {
        // Real concurrent writes in closures that may execute concurrently
        DispatchQueue.global().async { [self] in
            self.value += 1  // This COULD be flagged if there's concurrent access
        }
        
        DispatchQueue.global().async { [self] in
            self.value += 1  // This COULD be flagged if there's concurrent access
        }
    }
}
