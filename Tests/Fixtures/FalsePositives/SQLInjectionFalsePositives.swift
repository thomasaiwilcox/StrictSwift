// This file contains examples of code patterns that should NOT trigger SQL injection warnings
// These are false positives that were previously flagged incorrectly

import Foundation

// MARK: - Swift Keywords That Look Like SQL

/// Using .union() method on Sets - NOT SQL
func setOperations() {
    let set1: Set<Int> = [1, 2, 3]
    let set2: Set<Int> = [4, 5, 6]
    
    // This should NOT be flagged - .union() is a Swift Set method, not SQL UNION
    let combined = "Combined: \(set1.union(set2))"
    print(combined)
}

/// Using 'update' in property names or method names - NOT SQL
struct UpdateTracker {
    var lastUpdate: Date = Date()
    var updateCount: Int = 0
    
    // This should NOT be flagged - 'update' is a common property name
    func logUpdate() {
        print("Last update: \(lastUpdate), count: \(updateCount)")
    }
}

/// Using 'select' in property names - NOT SQL  
struct SelectableItem {
    var isSelected: Bool = false
    var selectedItems: [String] = []
    
    // This should NOT be flagged - 'selected' is a common UI pattern
    func showSelection() {
        print("Selected: \(isSelected), items: \(selectedItems)")
    }
}

/// Using 'create' in method names - NOT SQL
class Factory {
    // This should NOT be flagged - 'create' is a factory pattern
    func createWidget(name: String) -> String {
        return "Created: \(name)"
    }
}

/// Using 'delete' in method or variable names - NOT SQL
struct DeleteOperation {
    var deleteCount: Int = 0
    
    // This should NOT be flagged - 'delete' is a common operation name
    func performDelete(item: String) {
        print("Deleting: \(item), total: \(deleteCount)")
    }
}

// MARK: - Real SQL Should Still Be Detected

/// This SHOULD be flagged - it's actual SQL with interpolation
func realSQLInjection(userId: String) {
    // Real SQL: has both keyword (SELECT) AND clause (FROM) with interpolation
    let unsafeQuery = "SELECT * FROM users WHERE id = '\(userId)'"
    print(unsafeQuery)
}

/// This SHOULD be flagged - INSERT INTO with interpolation
func insertInjection(name: String) {
    let unsafeInsert = "INSERT INTO users (name) VALUES ('\(name)')"
    print(unsafeInsert)
}

/// This SHOULD be flagged - UPDATE SET with interpolation
func updateInjection(id: String, name: String) {
    let unsafeUpdate = "UPDATE users SET name = '\(name)' WHERE id = \(id)"
    print(unsafeUpdate)
}
