import Foundation

/// Performance metrics for analysis operations
public struct PerformanceMetrics: Sendable, Codable {
    public let operationName: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let duration: TimeInterval
    public let memoryUsage: MemoryUsage
    public let fileCount: Int
    public let linesAnalyzed: Int
    public let violationsFound: Int

    public init(
        operationName: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        memoryUsage: MemoryUsage,
        fileCount: Int = 0,
        linesAnalyzed: Int = 0,
        violationsFound: Int = 0
    ) {
        self.operationName = operationName
        self.startTime = startTime
        self.endTime = endTime
        self.duration = endTime - startTime
        self.memoryUsage = memoryUsage
        self.fileCount = fileCount
        self.linesAnalyzed = linesAnalyzed
        self.violationsFound = violationsFound
    }

    /// Performance in files per second
    public var filesPerSecond: Double {
        guard duration > 0 else { return 0 }
        return Double(fileCount) / duration
    }

    /// Performance in lines per second
    public var linesPerSecond: Double {
        guard duration > 0 else { return 0 }
        return Double(linesAnalyzed) / duration
    }

    /// Efficiency score (violations found per second)
    public var efficiency: Double {
        guard duration > 0 else { return 0 }
        return Double(violationsFound) / duration
    }
}

/// Memory usage information
public struct MemoryUsage: Sendable, Codable {
    public let usedMemory: UInt64  // in bytes
    public let peakMemory: UInt64  // in bytes
    public let systemMemory: UInt64 // total system memory

    public init(usedMemory: UInt64, peakMemory: UInt64, systemMemory: UInt64) {
        self.usedMemory = usedMemory
        self.peakMemory = peakMemory
        self.systemMemory = systemMemory
    }

    /// Memory usage as percentage of system memory
    public var memoryPercentage: Double {
        guard systemMemory > 0 else { return 0 }
        return Double(usedMemory) / Double(systemMemory) * 100
    }

    /// Memory usage in MB
    public var usedMemoryMB: Double {
        return Double(usedMemory) / (1024 * 1024)
    }

    /// Peak memory usage in MB
    public var peakMemoryMB: Double {
        return Double(peakMemory) / (1024 * 1024)
    }
}

/// Performance profiler for analysis operations
public final class PerformanceProfiler: @unchecked Sendable {
    private var metrics: [PerformanceMetrics] = []
    private var currentOperations: [String: OperationContext] = [:]
    private let lock = NSLock()
    private let startTime: TimeInterval

    public init() {
        self.startTime = Date().timeIntervalSince1970
    }

    /// Start profiling an operation
    public func startOperation(_ name: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        let operationId = UUID().uuidString
        let context = OperationContext(
            id: operationId,
            name: name,
            startTime: Date().timeIntervalSince1970,
            startMemory: getCurrentMemoryUsage()
        )

        currentOperations[operationId] = context
        return operationId
    }

    /// End profiling an operation
    public func endOperation(_ operationId: String, fileCount: Int = 0, linesAnalyzed: Int = 0, violationsFound: Int = 0) -> PerformanceMetrics? {
        lock.lock()
        defer { lock.unlock() }

        guard let context = currentOperations[operationId] else { return nil }

        let endTime = Date().timeIntervalSince1970
        let endMemory = getCurrentMemoryUsage()

        let metrics = PerformanceMetrics(
            operationName: context.name,
            startTime: context.startTime,
            endTime: endTime,
            memoryUsage: MemoryUsage(
                usedMemory: endMemory.current,
                peakMemory: max(context.startMemory.current, endMemory.current),
                systemMemory: endMemory.system
            ),
            fileCount: fileCount,
            linesAnalyzed: linesAnalyzed,
            violationsFound: violationsFound
        )

        self.metrics.append(metrics)
        currentOperations.removeValue(forKey: operationId)

        return metrics
    }

    /// Get all recorded metrics
    public var allMetrics: [PerformanceMetrics] {
        lock.lock()
        defer { lock.unlock() }
        return metrics
    }

    /// Get metrics for a specific operation name
    public func metrics(for operationName: String) -> [PerformanceMetrics] {
        lock.lock()
        defer { lock.unlock() }
        return metrics.filter { $0.operationName == operationName }
    }

    /// Get the latest metrics
    public var latestMetrics: PerformanceMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return metrics.last
    }

    /// Get average performance metrics
    public var averageMetrics: PerformanceMetrics? {
        lock.lock()
        defer { lock.unlock() }

        guard !metrics.isEmpty else { return nil }

        let avgStartTime = metrics.map(\.startTime).reduce(0, +) / Double(metrics.count)
        let avgEndTime = metrics.map(\.endTime).reduce(0, +) / Double(metrics.count)
        let avgMemoryUsage = metrics.map(\.memoryUsage).reduce(MemoryUsage(usedMemory: 0, peakMemory: 0, systemMemory: 0), combineMemoryUsage)
        let avgFileCount = metrics.map(\.fileCount).reduce(0, +) / metrics.count
        let avgLinesAnalyzed = metrics.map(\.linesAnalyzed).reduce(0, +) / metrics.count
        let avgViolationsFound = metrics.map(\.violationsFound).reduce(0, +) / metrics.count

        return PerformanceMetrics(
            operationName: "Average",
            startTime: avgStartTime,
            endTime: avgEndTime,
            memoryUsage: avgMemoryUsage,
            fileCount: avgFileCount,
            linesAnalyzed: avgLinesAnalyzed,
            violationsFound: avgViolationsFound
        )
    }

    /// Get performance summary
    public var performanceSummary: String {
        lock.lock()
        defer { lock.unlock() }

        guard !metrics.isEmpty else {
            return "No performance metrics available"
        }

        let totalDuration = Date().timeIntervalSince1970 - startTime
        let totalFiles = metrics.map(\.fileCount).reduce(0, +)
        let totalLines = metrics.map(\.linesAnalyzed).reduce(0, +)
        let totalViolations = metrics.map(\.violationsFound).reduce(0, +)

        var summary = """
        Performance Summary:
        ===================
        Total Analysis Time: \(String(format: "%.2f", totalDuration))s
        Total Files Analyzed: \(totalFiles)
        Total Lines Analyzed: \(totalLines)
        Total Violations Found: \(totalViolations)
        Average Files/Second: \(String(format: "%.1f", Double(totalFiles) / totalDuration))
        Average Lines/Second: \(String(format: "%.0f", Double(totalLines) / totalDuration))
        Operations Completed: \(metrics.count)

        Memory Usage:
        Current: \(String(format: "%.1f", getCurrentMemoryUsage().current / (1024 * 1024))) MB
        Peak: \(String(format: "%.1f", metrics.map(\.memoryUsage.peakMemory).max() ?? 0 / (1024 * 1024))) MB

        Recent Operations:
        """

        let recentMetrics = Array(metrics.suffix(5))
        for metric in recentMetrics {
            summary += "\n- \(metric.operationName): \(String(format: "%.2f", metric.duration))s, \(metric.fileCount) files, \(metric.violationsFound) violations"
        }

        return summary
    }

    /// Export metrics to JSON
    public func exportToJSON() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            return try encoder.encode(metrics)
        } catch {
            return nil
        }
    }

    /// Clear all metrics
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        metrics.removeAll()
        currentOperations.removeAll()
    }

    /// Get performance recommendations
    public var performanceRecommendations: [String] {
        lock.lock()
        defer { lock.unlock() }

        var recommendations: [String] = []
        guard !metrics.isEmpty else { return recommendations }

        let avgDuration = metrics.map(\.duration).reduce(0, +) / Double(metrics.count)
        let avgFilesPerSecond = metrics.map(\.filesPerSecond).reduce(0, +) / Double(metrics.count)
        let maxMemory = metrics.map(\.memoryUsage.peakMemoryMB).max() ?? 0

        // Performance recommendations
        if avgDuration > 5.0 {
            recommendations.append("Analysis is taking longer than 5 seconds on average. Consider optimizing rule implementations or enabling parallel processing.")
        }

        if avgFilesPerSecond < 10 {
            recommendations.append("File processing rate is below 10 files/second. Consider optimizing file parsing and AST traversal.")
        }

        if maxMemory > 500 {
            recommendations.append("Memory usage exceeds 500MB. Consider implementing streaming analysis or reducing memory footprint.")
        }

        let slowestOperation = metrics.max { $0.duration < $1.duration }
        if let slowest = slowestOperation, slowest.duration > avgDuration * 2 {
            recommendations.append("Operation '\(slowest.operationName)' is significantly slower than average. Consider optimizing this specific rule.")
        }

        let memoryIntensiveOperation = metrics.max { $0.memoryUsage.peakMemoryMB < $1.memoryUsage.peakMemoryMB }
        if let memoryOp = memoryIntensiveOperation, memoryOp.memoryUsage.peakMemoryMB > avgDuration * 100 {
            recommendations.append("Operation '\(memoryOp.operationName)' uses excessive memory. Consider implementing memory pooling or lazy evaluation.")
        }

        if recommendations.isEmpty {
            recommendations.append("Performance is within acceptable ranges.")
        }

        return recommendations
    }

    // MARK: - Private Methods

    private func combineMemoryUsage(_ lhs: MemoryUsage, rhs: MemoryUsage) -> MemoryUsage {
        return MemoryUsage(
            usedMemory: (lhs.usedMemory + rhs.usedMemory) / 2,
            peakMemory: max(lhs.peakMemory, rhs.peakMemory),
            systemMemory: lhs.systemMemory
        )
    }

    private func getCurrentMemoryUsage() -> (current: UInt64, system: UInt64) {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let currentMemory = UInt64(info.resident_size)
            let systemMemory = ProcessInfo.processInfo.physicalMemory
            return (currentMemory, systemMemory)
        } else {
            return (0, ProcessInfo.processInfo.physicalMemory)
        }
        #else
        // On Linux and other platforms, we can't easily get per-process memory
        // Return system memory info only
        return (0, ProcessInfo.processInfo.physicalMemory)
        #endif
    }
}

/// Context for tracking ongoing operations
private struct OperationContext {
    let id: String
    let name: String
    let startTime: TimeInterval
    let startMemory: (current: UInt64, system: UInt64)
}

/// Convenience wrapper for automatic operation profiling
public class ProfiledOperation {
    private let profiler: PerformanceProfiler
    private let operationId: String
    private var fileCount: Int = 0
    private var linesAnalyzed: Int = 0
    private var violationsFound: Int = 0

    public init(profiler: PerformanceProfiler, operationName: String) {
        self.profiler = profiler
        self.operationId = profiler.startOperation(operationName)
    }

    /// Update metrics during operation
    public func update(fileCount: Int = 0, linesAnalyzed: Int = 0, violationsFound: Int = 0) {
        self.fileCount = fileCount
        self.linesAnalyzed = linesAnalyzed
        self.violationsFound = violationsFound
    }

    /// End the profiling and return metrics
    public func end() -> PerformanceMetrics? {
        return profiler.endOperation(
            operationId,
            fileCount: fileCount,
            linesAnalyzed: linesAnalyzed,
            violationsFound: violationsFound
        )
    }
}