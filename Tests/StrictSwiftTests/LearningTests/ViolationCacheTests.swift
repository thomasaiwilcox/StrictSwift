import XCTest
@testable import StrictSwiftCore

/// Tests for stable violation IDs and the violation cache
final class ViolationCacheTests: XCTestCase {
    
    // MARK: - Stable ID Tests
    
    func testStableIdConsistency() async throws {
        // Create a violation
        let violation = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .warning,
            message: "Force unwrap detected",
            location: Location(
                file: URL(fileURLWithPath: "/test/MyFile.swift"),
                line: 42,
                column: 10
            )
        )
        
        // The stable ID should be consistent
        let id1 = violation.stableId
        let id2 = violation.stableId
        XCTAssertEqual(id1, id2, "Stable ID should be consistent across calls")
    }
    
    func testStableIdFormat() async throws {
        let violation = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .warning,
            message: "Force unwrap detected",
            location: Location(
                file: URL(fileURLWithPath: "/test/MyFile.swift"),
                line: 42,
                column: 10
            )
        )
        
        let stableId = violation.stableId
        
        // Should be 16 hex characters
        XCTAssertEqual(stableId.count, 16)
        
        // Should only contain hex characters
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(stableId.unicodeScalars.allSatisfy { hexCharacters.contains($0) })
    }
    
    func testStableIdDifferentForDifferentViolations() async throws {
        let violation1 = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .warning,
            message: "Force unwrap detected",
            location: Location(
                file: URL(fileURLWithPath: "/test/MyFile.swift"),
                line: 42,
                column: 10
            )
        )
        
        // Different message should give different ID
        let violation2 = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .warning,
            message: "Another force unwrap",
            location: Location(
                file: URL(fileURLWithPath: "/test/MyFile.swift"),
                line: 42,
                column: 10
            )
        )
        
        // Different line should give different ID
        let violation3 = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .warning,
            message: "Force unwrap detected",
            location: Location(
                file: URL(fileURLWithPath: "/test/MyFile.swift"),
                line: 100,
                column: 10
            )
        )
        
        // Different rule should give different ID
        let violation4 = Violation(
            ruleId: "force_try",
            category: .safety,
            severity: .warning,
            message: "Force unwrap detected",
            location: Location(
                file: URL(fileURLWithPath: "/test/MyFile.swift"),
                line: 42,
                column: 10
            )
        )
        
        XCTAssertNotEqual(violation1.stableId, violation2.stableId)
        XCTAssertNotEqual(violation1.stableId, violation3.stableId)
        XCTAssertNotEqual(violation1.stableId, violation4.stableId)
    }
    
    func testStableIdPortableAcrossPaths() async throws {
        // The stable ID should be the same regardless of full path
        // (only uses filename, not directory)
        
        let violation1 = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .warning,
            message: "Force unwrap detected",
            location: Location(
                file: URL(fileURLWithPath: "/Users/alice/project/MyFile.swift"),
                line: 42,
                column: 10
            )
        )
        
        let violation2 = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .warning,
            message: "Force unwrap detected",
            location: Location(
                file: URL(fileURLWithPath: "/Users/bob/work/MyFile.swift"),
                line: 42,
                column: 10
            )
        )
        
        XCTAssertEqual(violation1.stableId, violation2.stableId,
                       "Stable ID should be portable across different directory paths")
    }
    
    // MARK: - Cache Tests
    
    func testCacheStoreAndLookup() async throws {
        let cache = ViolationCache.shared
        await cache.clear()
        
        let violation = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .warning,
            message: "Force unwrap detected",
            location: Location(
                file: URL(fileURLWithPath: "/test/MyFile.swift"),
                line: 42,
                column: 10
            )
        )
        
        await cache.storeViolations([violation])
        
        let retrieved = await cache.lookup(violation.stableId)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.ruleId, "force_unwrap")
        XCTAssertEqual(retrieved?.line, 42)
    }
    
    func testCacheLookupMissing() async throws {
        let cache = ViolationCache.shared
        await cache.clear()
        
        let retrieved = await cache.lookup("nonexistent_id")
        XCTAssertNil(retrieved)
    }
    
    func testCacheMultipleViolations() async throws {
        let cache = ViolationCache.shared
        await cache.clear()
        
        let violations = [
            Violation(
                ruleId: "force_unwrap",
                category: .safety,
                severity: .warning,
                message: "Force unwrap 1",
                location: Location(file: URL(fileURLWithPath: "/test/A.swift"), line: 10, column: 5)
            ),
            Violation(
                ruleId: "force_try",
                category: .safety,
                severity: .error,
                message: "Force try",
                location: Location(file: URL(fileURLWithPath: "/test/B.swift"), line: 20, column: 8)
            ),
            Violation(
                ruleId: "retain_cycle",
                category: .safety,
                severity: .warning,
                message: "Potential retain cycle",
                location: Location(file: URL(fileURLWithPath: "/test/C.swift"), line: 30, column: 1)
            )
        ]
        
        await cache.storeViolations(violations)
        
        let count = await cache.count()
        XCTAssertEqual(count, 3)
        
        // Verify each can be retrieved
        for violation in violations {
            let retrieved = await cache.lookup(violation.stableId)
            XCTAssertNotNil(retrieved, "Should find violation with id \(violation.stableId)")
            XCTAssertEqual(retrieved?.ruleId, violation.ruleId)
        }
    }
    
    func testCacheClear() async throws {
        let cache = ViolationCache.shared
        
        let violation = Violation(
            ruleId: "test_rule",
            category: .safety,
            severity: .warning,
            message: "Test",
            location: Location(file: URL(fileURLWithPath: "/test/T.swift"), line: 1, column: 1)
        )
        
        await cache.storeViolations([violation])
        let countBefore = await cache.count()
        XCTAssertGreaterThan(countBefore, 0)
        
        await cache.clear()
        
        let countAfter = await cache.count()
        XCTAssertEqual(countAfter, 0)
    }
    
    func testCachedViolationProperties() async throws {
        let cache = ViolationCache.shared
        await cache.clear()
        
        let violation = Violation(
            ruleId: "force_unwrap",
            category: .safety,
            severity: .error,
            message: "Test message",
            location: Location(
                file: URL(fileURLWithPath: "/path/to/TestFile.swift"),
                line: 99,
                column: 15
            )
        )
        
        await cache.storeViolations([violation])
        
        let cached = await cache.lookup(violation.stableId)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.stableId, violation.stableId)
        XCTAssertEqual(cached?.ruleId, "force_unwrap")
        XCTAssertEqual(cached?.category, RuleCategory.safety.rawValue)
        XCTAssertEqual(cached?.severity, DiagnosticSeverity.error.rawValue)
        XCTAssertEqual(cached?.message, "Test message")
        XCTAssertTrue(cached?.filePath.hasSuffix("TestFile.swift") ?? false)
        XCTAssertEqual(cached?.line, 99)
        XCTAssertEqual(cached?.column, 15)
    }
}
