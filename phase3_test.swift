import Foundation
import SwiftSyntax

/// Test file to verify Phase 3 functionality works
struct Phase3Test {

    // Test large struct copy detection
    struct LargeStruct {
        let data: Data
        let strings: [String]
        let numbers: [Int]
        let dictionary: [String: Any]
        let url: URL
        let date: Date
    }

    func testStructCopy() {
        // This should trigger LargeStructCopyRule
        var largeStruct = LargeStruct(
            data: Data(repeating: 0, count: 1024),
            strings: ["test1", "test2", "test3"],
            numbers: [1, 2, 3, 4, 5],
            dictionary: ["key": "value"],
            url: URL(string: "https://example.com")!,
            date: Date()
        )

        // Copy in loop - should be flagged
        for i in 0..<5 {
            let copy = largeStruct
            print("Copy \(i): \(copy)")
        }
    }

    // Test repeated allocation
    func testRepeatedAllocation() {
        // This should trigger RepeatedAllocationRule
        var result = ""

        for i in 0..<100 {
            // String concatenation in loop - should be flagged
            result += "Item \(i), "
        }

        return result
    }

    // Test escaping closure
    func testEscapingClosure() {
        // This should trigger EscapingReferenceRule
        var numbers = [1, 2, 3, 4, 5]

        let escapingClosure: () -> Void = {
            // Capturing numbers as escaping - should be analyzed
            print("Numbers: \(numbers)")
        }

        // Store closure somewhere (escapes scope)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            escapingClosure()
        }
    }

    // Test cyclomatic complexity
    func testComplexity() {
        // This should trigger CyclomaticComplexityRule
        let x = 10
        let y = 20
        let z = 30

        if x > 5 {
            if y > 10 {
                if z > 15 {
                    for i in 0..<x {
                        if i % 2 == 0 {
                            print("Even")
                        } else {
                            print("Odd")
                        }
                    }
                }
            }
        }

        switch x {
        case 1:
            print("One")
        case 2:
            print("Two")
        case 3:
            print("Three")
        default:
            print("Other")
        }
    }
}

// Test entry point
let test = Phase3Test()
test.testStructCopy()
test.testRepeatedAllocation()
test.testEscapingClosure()
test.testComplexity()

print("Phase 3 test completed - check for rule violations!")