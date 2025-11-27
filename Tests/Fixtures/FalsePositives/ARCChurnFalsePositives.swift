// This file contains examples of code patterns that should NOT trigger ARC churn warnings
// These are false positives that were previously flagged incorrectly

import Foundation

// MARK: - Iterator Expressions Should Not Be Flagged

/// sorted() in for-in iterator runs ONCE, not per iteration
func iteratorSorted(items: [String]) {
    // This should NOT be flagged - sorted() is called ONCE to create the sequence
    for item in items.sorted() {
        print(item)
    }
}

/// filter() in for-in iterator runs ONCE, not per iteration
func iteratorFilter(items: [Int]) {
    // This should NOT be flagged - filter() is called ONCE to create the sequence
    for item in items.filter({ $0 > 0 }) {
        print(item)
    }
}

/// map() in for-in iterator runs ONCE, not per iteration
func iteratorMap(items: [Int]) {
    // This should NOT be flagged - map() is called ONCE to create the sequence
    for item in items.map({ String($0) }) {
        print(item)
    }
}

/// Chained operations in for-in iterator run ONCE
func iteratorChained(items: [Int]) {
    // This should NOT be flagged - the whole chain runs ONCE
    for item in items.filter({ $0 > 0 }).sorted().map({ String($0) }) {
        print(item)
    }
}

// MARK: - While Loop Conditions Should Not Be Flagged (in context)

/// Iterator.next() in while condition - this runs per iteration but is unavoidable
func whileIterator(items: [String]) {
    var iterator = items.makeIterator()
    
    // The condition is evaluated per iteration, but this is how iterators work
    while let item = iterator.next() {
        print(item)
    }
}

// MARK: - Operations INSIDE Loop Body SHOULD Be Flagged

/// sorted() inside loop body runs PER ITERATION - this is bad
func bodySorted(items: [String]) {
    for _ in 0..<10 {
        // This SHOULD be flagged - sorted() called 10 times
        let sorted = items.sorted()
        print(sorted.count)
    }
}

/// filter() inside loop body runs PER ITERATION - this is bad
func bodyFilter(items: [Int]) {
    for i in 0..<10 {
        // This SHOULD be flagged - filter() called 10 times
        let filtered = items.filter { $0 > i }
        print(filtered.count)
    }
}

/// map() inside loop body runs PER ITERATION - this is bad
func bodyMap(items: [Int]) {
    for i in 0..<10 {
        // This SHOULD be flagged - map() called 10 times
        let mapped = items.map { $0 + i }
        print(mapped.count)
    }
}

// MARK: - Repeat-While Loop Patterns

/// Condition in repeat-while is at the end, but still runs per iteration
func repeatWhilePattern() {
    var count = 0
    repeat {
        count += 1
    } while count < 10
    print(count)
}
