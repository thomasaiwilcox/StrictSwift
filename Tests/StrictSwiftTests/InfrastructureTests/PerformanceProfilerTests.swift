import XCTest
@testable import StrictSwiftCore

final class PerformanceProfilerTests: XCTestCase {

    func testPerformanceProfilerBasicOperations() throws {
        let profiler = PerformanceProfiler()

        // Test starting and ending operations
        let operationId = profiler.startOperation("TestOperation")
        XCTAssertNotNil(operationId)
        XCTAssertFalse(operationId.isEmpty)

        // Simulate some work
        Thread.sleep(forTimeInterval: 0.1)

        let metrics = profiler.endOperation(operationId, fileCount: 10, linesAnalyzed: 1000, violationsFound: 5)
        XCTAssertNotNil(metrics)

        XCTAssertEqual(metrics?.operationName, "TestOperation")
        XCTAssertEqual(metrics?.fileCount, 10)
        XCTAssertEqual(metrics?.linesAnalyzed, 1000)
        XCTAssertEqual(metrics?.violationsFound, 5)
        XCTAssertGreaterThan(metrics?.duration ?? 0, 0.05) // Should be at least 0.05 seconds
        XCTAssertEqual(metrics?.filesPerSecond, 10 / (metrics?.duration ?? 1), accuracy: 1.0)
        XCTAssertEqual(metrics?.linesPerSecond, 1000 / (metrics?.duration ?? 1), accuracy: 1.0)
    }

    func testPerformanceProfilerMultipleOperations() throws {
        let profiler = PerformanceProfiler()

        let operationIds = (1...5).map { "Operation\($0)" }

        // Start multiple operations
        let startedIds = operationIds.map { profiler.startOperation($0) }
        XCTAssertEqual(startedIds.count, 5)

        // End operations with different metrics
        for (index, id) in startedIds.enumerated() {
            Thread.sleep(forTimeInterval: 0.02)
            _ = profiler.endOperation(id, fileCount: index + 1, linesAnalyzed: (index + 1) * 100, violationsFound: index)
        }

        let allMetrics = profiler.allMetrics
        XCTAssertEqual(allMetrics.count, 5)

        // Verify each operation has the correct metrics
        for (index, metrics) in allMetrics.enumerated() {
            XCTAssertEqual(metrics.fileCount, index + 1)
            XCTAssertEqual(metrics.linesAnalyzed, (index + 1) * 100)
            XCTAssertEqual(metrics.violationsFound, index)
        }
    }

    func testPerformanceProfilerMetricsForOperation() throws {
        let profiler = PerformanceProfiler()

        let operationId1 = profiler.startOperation("OperationA")
        let operationId2 = profiler.startOperation("OperationB")
        let operationId3 = profiler.startOperation("OperationA") // Same name as first

        Thread.sleep(forTimeInterval: 0.05)
        _ = profiler.endOperation(operationId1, violationsFound: 1)

        Thread.sleep(forTimeInterval: 0.03)
        _ = profiler.endOperation(operationId2, violationsFound: 2)

        Thread.sleep(forTimeInterval: 0.04)
        _ = profiler.endOperation(operationId3, violationsFound: 3)

        let operationAMetrics = profiler.metrics(for: "OperationA")
        let operationBMetrics = profiler.metrics(for: "OperationB")

        XCTAssertEqual(operationAMetrics.count, 2) // Two operations with name "OperationA"
        XCTAssertEqual(operationBMetrics.count, 1)  // One operation with name "OperationB"

        let totalViolationsA = operationAMetrics.map(\.violationsFound).reduce(0, +)
        let totalViolationsB = operationBMetrics.map(\.violationsFound).reduce(0, +)

        XCTAssertEqual(totalViolationsA, 4) // 1 + 3
        XCTAssertEqual(totalViolationsB, 2) // 2
    }

    func testPerformanceProfilerAverageMetrics() throws {
        let profiler = PerformanceProfiler()

        // Create operations with different performance characteristics
        let operations = [
            ("FastOperation", 0.01, 5, 100, 2),
            ("MediumOperation", 0.05, 10, 500, 5),
            ("SlowOperation", 0.1, 20, 1000, 10)
        ]

        for (index, operation) in operations.enumerated() {
            let operationId = profiler.startOperation(operation.0)
            Thread.sleep(forTimeInterval: operation.1)
            _ = profiler.endOperation(operationId, fileCount: operation.2, linesAnalyzed: operation.3, violationsFound: operation.4)
        }

        let averageMetrics = profiler.averageMetrics
        XCTAssertNotNil(averageMetrics)

        // Check average calculations
        let avgFileCount = operations.map { $0.2 }.reduce(0, +) / operations.count
        let avgLinesAnalyzed = operations.map { $0.3 }.reduce(0, +) / operations.count
        let avgViolationsFound = operations.map { $0.4 }.reduce(0, +) / operations.count

        XCTAssertEqual(averageMetrics?.fileCount, avgFileCount)
        XCTAssertEqual(averageMetrics?.linesAnalyzed, avgLinesAnalyzed)
        XCTAssertEqual(averageMetrics?.violationsFound, avgViolationsFound)
    }

    func testPerformanceProfilerLatestMetrics() throws {
        let profiler = PerformanceProfiler()

        let firstId = profiler.startOperation("FirstOperation")
        Thread.sleep(forTimeInterval: 0.01)
        _ = profiler.endOperation(firstId, violationsFound: 1)

        let latestMetrics = profiler.latestMetrics
        XCTAssertNotNil(latestMetrics)
        XCTAssertEqual(latestMetrics?.operationName, "FirstOperation")

        let secondId = profiler.startOperation("SecondOperation")
        Thread.sleep(forTimeInterval: 0.02)
        _ = profiler.endOperation(secondId, violationsFound: 2)

        let updatedLatestMetrics = profiler.latestMetrics
        XCTAssertNotNil(updatedLatestMetrics)
        XCTAssertEqual(updatedLatestMetrics?.operationName, "SecondOperation")
        XCTAssertEqual(updatedLatestMetrics?.violationsFound, 2)

        XCTAssertNotEqual(latestMetrics?.operationName, updatedLatestMetrics?.operationName)
    }

    func testPerformanceProfilerSummary() throws {
        let profiler = PerformanceProfiler()

        // Add some sample operations
        let operationId = profiler.startOperation("SampleAnalysis")
        Thread.sleep(forTimeInterval: 0.05)
        _ = profiler.endOperation(operationId, fileCount: 15, linesAnalyzed: 1500, violationsFound: 8)

        let summary = profiler.performanceSummary

        XCTAssertTrue(summary.contains("Performance Summary"))
        XCTAssertTrue(summary.contains("Total Files Analyzed: 15"))
        XCTAssertTrue(summary.contains("Total Lines Analyzed: 1500"))
        XCTAssertTrue(summary.contains("Total Violations Found: 8"))
        XCTAssertTrue(summary.contains("Operations Completed: 1"))
        XCTAssertTrue(summary.contains("SampleAnalysis"))
    }

    func testPerformanceProfilerJSONExport() throws {
        let profiler = PerformanceProfiler()

        let operationId = profiler.startOperation("ExportTest")
        Thread.sleep(forTimeInterval: 0.01)
        _ = profiler.endOperation(operationId, fileCount: 5, linesAnalyzed: 500, violationsFound: 3)

        let jsonData = profiler.exportToJSON()
        XCTAssertNotNil(jsonData)

        // Verify JSON can be decoded back
        do {
            let decoder = JSONDecoder()
            let decodedMetrics = try decoder.decode([PerformanceMetrics].self, from: jsonData!)
            XCTAssertEqual(decodedMetrics.count, 1)
            XCTAssertEqual(decodedMetrics.first?.operationName, "ExportTest")
            XCTAssertEqual(decodedMetrics.first?.fileCount, 5)
        } catch {
            XCTFail("Failed to decode JSON: \(error)")
        }
    }

    func testPerformanceProfilerClear() throws {
        let profiler = PerformanceProfiler()

        // Add some operations
        let operationId1 = profiler.startOperation("Test1")
        let operationId2 = profiler.startOperation("Test2")
        _ = profiler.endOperation(operationId1)
        _ = profiler.endOperation(operationId2)

        XCTAssertEqual(profiler.allMetrics.count, 2)
        XCTAssertEqual(profiler.latestMetrics?.operationName, "Test2")

        // Clear all metrics
        profiler.clear()

        XCTAssertEqual(profiler.allMetrics.count, 0)
        XCTAssertNil(profiler.latestMetrics)
        XCTAssertEqual(profiler.averageMetrics?.operationName, "Average")
    }

    func testPerformanceProfilerRecommendations() throws {
        let profiler = PerformanceProfiler()

        // Test with good performance (no recommendations should be critical)
        let fastId = profiler.startOperation("FastOperation")
        _ = profiler.endOperation(fastId, fileCount: 50, linesAnalyzed: 5000, violationsFound: 25)

        let goodRecommendations = profiler.performanceRecommendations
        XCTAssertTrue(goodRecommendations.contains("Performance is within acceptable ranges"))

        // Clear and test with slow performance
        profiler.clear()

        let slowId = profiler.startOperation("SlowOperation")
        Thread.sleep(forTimeInterval: 0.1) // Simulate slow operation
        _ = profiler.endOperation(slowId, fileCount: 2, linesAnalyzed: 100, violationsFound: 1)

        let slowRecommendations = profiler.performanceRecommendations
        XCTAssertTrue(slowRecommendations.count > 0)
        XCTAssertTrue(slowRecommendations.contains { $0.contains("longer than 5 seconds") || $0.contains("optimizing") })
    }

    func testPerformanceProfilerEfficiencyMetrics() throws {
        let profiler = PerformanceProfiler()

        let operationId = profiler.startOperation("EfficiencyTest")
        Thread.sleep(forTimeInterval: 0.1)
        _ = profiler.endOperation(operationId, fileCount: 20, linesAnalyzed: 2000, violationsFound: 10)

        let metrics = profiler.latestMetrics
        XCTAssertNotNil(metrics)

        // Test efficiency calculation
        XCTAssertEqual(metrics?.efficiency, 10.0 / 0.1) // 10 violations in 0.1 second = 100 violations/second
        XCTAssertEqual(metrics?.filesPerSecond, 20.0 / 0.1) // 20 files in 0.1 second = 200 files/second
        XCTAssertEqual(metrics?.linesPerSecond, 2000.0 / 0.1) // 2000 lines in 0.1 second = 20000 lines/second
    }

    func testPerformanceProfilerMemoryUsage() throws {
        let profiler = PerformanceProfiler()

        let operationId = profiler.startOperation("MemoryTest")
        // Simulate some memory allocation
        let dataArray = Array(0..<10000).map { String($0) }
        _ = profiler.endOperation(operationId, fileCount: 5, linesAnalyzed: 500, violationsFound: 2)

        let metrics = profiler.latestMetrics
        XCTAssertNotNil(metrics)

        // Check memory usage metrics
        XCTAssertGreaterThan(metrics?.memoryUsage.usedMemoryMB ?? 0, 0)
        XCTAssertGreaterThan(metrics?.memoryUsage.systemMemory ?? 0, 0)
        XCTAssertGreaterThanOrEqual(metrics?.memoryUsage.peakMemoryMB ?? 0, metrics?.memoryUsage.usedMemoryMB ?? 0)

        // Memory usage should be reasonable (less than 100MB for this test)
        XCTAssertLessThan(metrics?.memoryUsage.usedMemoryMB ?? 0, 100)
        _ = dataArray // Prevent compiler optimization
    }

    func testProfiledOperationConvenienceClass() throws {
        let profiler = PerformanceProfiler()

        // Test the convenience wrapper class
        let operation = ProfiledOperation(profiler: profiler, operationName: "ConvenienceTest")

        operation.update(fileCount: 10, linesAnalyzed: 1000, violationsFound: 5)

        Thread.sleep(forTimeInterval: 0.05)

        let metrics = operation.end()
        XCTAssertNotNil(metrics)

        XCTAssertEqual(metrics?.operationName, "ConvenienceTest")
        XCTAssertEqual(metrics?.fileCount, 10)
        XCTAssertEqual(metrics?.linesAnalyzed, 1000)
        XCTAssertEqual(metrics?.violationsFound, 5)
    }

    func testPerformanceProfilerConcurrencySafety() throws {
        let profiler = PerformanceProfiler()
        let expectation = XCTestExpectation(description: "Concurrent profiling operations complete")
        let numberOfOperations = 10

        DispatchQueue.concurrentPerform(iterations: numberOfOperations) { index in
            let operationId = profiler.startOperation("ConcurrentOperation\(index)")
            Thread.sleep(forTimeInterval: 0.01)
            _ = profiler.endOperation(operationId, fileCount: 1, linesAnalyzed: 100, violationsFound: index)

            if index == numberOfOperations - 1 {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Verify all operations were recorded
        XCTAssertEqual(profiler.allMetrics.count, numberOfOperations)

        // Verify no operations have the same ID
        let operationIds = Set(profiler.allMetrics.map { "\($0.operationName)-\($0.startTime)" })
        XCTAssertEqual(operationIds.count, numberOfOperations)
    }

    func testPerformanceMetricsProperties() throws {
        let metrics = PerformanceMetrics(
            operationName: "TestOperation",
            startTime: Date().timeIntervalSince1970,
            endTime: Date().timeIntervalSince1970 + 0.5,
            memoryUsage: MemoryUsage(usedMemory: 50 * 1024 * 1024, peakMemory: 60 * 1024 * 1024, systemMemory: 8 * 1024 * 1024 * 1024),
            fileCount: 100,
            linesAnalyzed: 10000,
            violationsFound: 25
        )

        XCTAssertEqual(metrics.duration, 0.5)
        XCTAssertEqual(metrics.filesPerSecond, 200)
        XCTAssertEqual(metrics.linesPerSecond, 20000)
        XCTAssertEqual(metrics.efficiency, 50)

        XCTAssertEqual(metrics.memoryUsage.usedMemoryMB, 50, accuracy: 0.1)
        XCTAssertEqual(metrics.memoryUsage.peakMemoryMB, 60, accuracy: 0.1)
        XCTAssertEqual(metrics.memoryUsage.memoryPercentage, 50 / (8 * 1024), accuracy: 0.001)
    }

    func testMemoryUsageCalculations() throws {
        let memoryUsage = MemoryUsage(
            usedMemory: 100 * 1024 * 1024, // 100 MB
            peakMemory: 150 * 1024 * 1024, // 150 MB
            systemMemory: 4 * 1024 * 1024 * 1024 // 4 GB
        )

        XCTAssertEqual(memoryUsage.usedMemoryMB, 100, accuracy: 0.1)
        XCTAssertEqual(memoryUsage.peakMemoryMB, 150, accuracy: 0.1)
        XCTAssertEqual(memoryUsage.memoryPercentage, 100 / 4096, accuracy: 0.001)
    }
}