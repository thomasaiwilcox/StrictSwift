import Foundation
import SwiftSyntax
import SwiftParser

/// Tracks memory allocations and performance patterns
public final class AllocationTracker {
    /// Represents a memory allocation
    public struct Allocation: Codable, Hashable, Sendable {
        public let id: String
        public let type: String
        public let location: Location
        public let allocationType: AllocationType
        public let context: AllocationContext
        public let isRepeated: Bool
        public let loopContext: String?

        public init(
            id: String,
            type: String,
            location: Location,
            allocationType: AllocationType,
            context: AllocationContext,
            isRepeated: Bool = false,
            loopContext: String? = nil
        ) {
            self.id = id
            self.type = type
            self.location = location
            self.allocationType = allocationType
            self.context = context
            self.isRepeated = isRepeated
            self.loopContext = loopContext
        }
    }

    /// Types of allocations
    public enum AllocationType: String, Codable, CaseIterable, Sendable {
        case classAllocation = "class"
        case structAllocation = "struct"
        case array = "array"
        case dictionary = "dictionary"
        case closure = "closure"
        case string = "string"
        case data = "data"
        case custom = "custom"

        public var cost: AllocationCost {
            switch self {
            case .classAllocation:
                return .high
            case .array, .dictionary, .string, .data:
                return .medium
            case .structAllocation, .closure, .custom:
                return .low
            }
        }
    }

    /// Allocation cost levels
    public enum AllocationCost: String, Codable, CaseIterable, Sendable {
        case low = "low"
        case medium = "medium"
        case high = "high"
    }

    /// Allocation context
    public enum AllocationContext: String, Codable, CaseIterable, Sendable {
        case variable = "variable"
        case functionCall = "function_call"
        case returnStatement = "return"
        case parameter = "parameter"
        case property = "property"
        case closure = "closure"
        case loop = "loop"
        case conditional = "conditional"
    }

    /// Performance metrics for allocations
    public struct AllocationMetrics: Codable, Sendable {
        public let totalAllocations: Int
        public let repeatedAllocations: Int
        public let highCostAllocations: Int
        public let allocationTypes: [AllocationType: Int]
        public let allocationContexts: [AllocationContext: Int]
        public let hotspots: [AllocationHotspot]

        public init(
            totalAllocations: Int = 0,
            repeatedAllocations: Int = 0,
            highCostAllocations: Int = 0,
            allocationTypes: [AllocationType: Int] = [:],
            allocationContexts: [AllocationContext: Int] = [:],
            hotspots: [AllocationHotspot] = []
        ) {
            self.totalAllocations = totalAllocations
            self.repeatedAllocations = repeatedAllocations
            self.highCostAllocations = highCostAllocations
            self.allocationTypes = allocationTypes
            self.allocationContexts = allocationContexts
            self.hotspots = hotspots
        }
    }

    /// Performance hotspot
    public struct AllocationHotspot: Codable, Hashable, Sendable {
        public let location: Location
        public let allocationCount: Int
        public let estimatedImpact: PerformanceImpact

        public init(location: Location, allocationCount: Int, estimatedImpact: PerformanceImpact) {
            self.location = location
            self.allocationCount = allocationCount
            self.estimatedImpact = estimatedImpact
        }
    }

    /// Performance impact levels
    public enum PerformanceImpact: String, Codable, CaseIterable, Sendable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
    }

    /// Analysis result
    public struct AnalysisResult: Sendable {
        public let allocations: [Allocation]
        public let metrics: AllocationMetrics
        public let recommendations: [PerformanceRecommendation]

        public init(allocations: [Allocation], metrics: AllocationMetrics, recommendations: [PerformanceRecommendation]) {
            self.allocations = allocations
            self.metrics = metrics
            self.recommendations = recommendations
        }
    }

    /// Performance recommendation
    public struct PerformanceRecommendation: Codable, Sendable {
        public let type: RecommendationType
        public let location: Location
        public let message: String
        public let suggestion: String
        public let impact: PerformanceImpact

        public init(
            type: RecommendationType,
            location: Location,
            message: String,
            suggestion: String,
            impact: PerformanceImpact
        ) {
            self.type = type
            self.location = location
            self.message = message
            self.suggestion = suggestion
            self.impact = impact
        }
    }

    /// Recommendation types
    public enum RecommendationType: String, Codable, CaseIterable, Sendable {
        case repeatedAllocation = "repeated_allocation"
        case largeStructCopy = "large_struct_copy"
        case closureCapture = "closure_capture"
        case stringConcatenation = "string_concatenation"
        case arrayGrowth = "array_growth"
        case lazyInitialization = "lazy_initialization"
    }

    // Thread safety lock
    private let lock = NSLock()
    private var allocations: [Allocation] = []
    private var allocationCounter: Int = 0

    public init() {}

    /// Analyze source files for allocation patterns
    public func analyze(_ sourceFiles: [SourceFile]) -> AnalysisResult {
        lock.withLock {
            allocations.removeAll()
            allocationCounter = 0
        }

        for sourceFile in sourceFiles {
            _ = analyze(sourceFile)
        }

        let currentAllocations = lock.withLock { allocations }
        let metrics = calculateMetrics(from: currentAllocations)
        let recommendations = generateRecommendations(from: currentAllocations, metrics: metrics)

        return AnalysisResult(
            allocations: currentAllocations,
            metrics: metrics,
            recommendations: recommendations
        )
    }

    /// Analyze a single source file
    public func analyze(_ sourceFile: SourceFile) -> AnalysisResult {
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)

        let analyzer = AllocationSyntaxAnalyzer(
            sourceFile: sourceFile,
            onAllocation: { [weak self] allocation in
                self?.lock.withLock {
                    self?.allocations.append(allocation)
                }
            }
        )
        analyzer.walk(tree)

        let currentAllocations = lock.withLock { allocations }
        let metrics = calculateMetrics(from: currentAllocations)
        let recommendations = generateRecommendations(from: currentAllocations, metrics: metrics)

        return AnalysisResult(
            allocations: currentAllocations,
            metrics: metrics,
            recommendations: recommendations
        )
    }

    /// Get allocation statistics
    public var statistics: AllocationMetrics {
        return lock.withLock {
            calculateMetrics(from: allocations)
        }
    }

    /// Clear tracking data
    public func clear() {
        lock.withLock {
            allocations.removeAll()
            allocationCounter = 0
        }
    }

    // MARK: - Private Helper Methods

    private func calculateMetrics(from allocations: [Allocation]) -> AllocationMetrics {
        let total = allocations.count
        let repeated = allocations.filter { $0.isRepeated }.count
        let highCost = allocations.filter { $0.allocationType.cost == .high }.count

        let types = Dictionary(grouping: allocations) { $0.allocationType }.mapValues { $0.count }
        let contexts = Dictionary(grouping: allocations) { $0.context }.mapValues { $0.count }

        let hotspots = findHotspots(allocations: allocations)

        return AllocationMetrics(
            totalAllocations: total,
            repeatedAllocations: repeated,
            highCostAllocations: highCost,
            allocationTypes: types,
            allocationContexts: contexts,
            hotspots: hotspots
        )
    }

    private func findHotspots(allocations: [Allocation]) -> [AllocationHotspot] {
        // Group allocations by location to find hotspots
        let locationGroups = Dictionary(grouping: allocations) { allocation in
            "\(allocation.location.file):\(allocation.location.line)"
        }

        return locationGroups.compactMap { _, allocations in
            let count = allocations.count
            guard let firstAllocation = allocations.first else { return nil }
            let location = firstAllocation.location

            let impact: PerformanceImpact
            switch count {
            case 0..<5:
                impact = .low
            case 5..<10:
                impact = .medium
            case 10..<20:
                impact = .high
            default:
                impact = .critical
            }

            return AllocationHotspot(
                location: location,
                allocationCount: count,
                estimatedImpact: impact
            )
        }.sorted { $0.allocationCount > $1.allocationCount }
    }

    private func generateRecommendations(from allocations: [Allocation], metrics: AllocationMetrics) -> [PerformanceRecommendation] {
        var recommendations: [PerformanceRecommendation] = []

        // Repeated allocations
        let repeatedAllocations = allocations.filter { $0.isRepeated }
        for allocation in repeatedAllocations {
            recommendations.append(PerformanceRecommendation(
                type: .repeatedAllocation,
                location: allocation.location,
                message: "Repeated allocation of '\(allocation.type)'",
                suggestion: "Consider pooling, reusing objects, or moving allocation outside loop",
                impact: determineImpact(allocation: allocation)
            ))
        }

        // Large struct copies (would need struct size analysis)
        for allocation in allocations.filter({ $0.allocationType == .structAllocation && $0.context == .functionCall }) {
            recommendations.append(PerformanceRecommendation(
                type: .largeStructCopy,
                location: allocation.location,
                message: "Potential large struct copy detected",
                suggestion: "Consider using classes or reference types for large data structures",
                impact: .medium
            ))
        }

        // String concatenation patterns
        let stringAllocations = allocations.filter { $0.allocationType == .string && $0.context == .loop }
        if stringAllocations.count > 3 {
            for allocation in stringAllocations.prefix(3) {
                recommendations.append(PerformanceRecommendation(
                    type: .stringConcatenation,
                    location: allocation.location,
                    message: "String allocation in loop detected",
                    suggestion: "Use StringBuilder or pre-allocate string capacity",
                    impact: .high
                ))
            }
        }

        return recommendations
    }

    private func determineImpact(allocation: Allocation) -> PerformanceImpact {
        switch (allocation.allocationType.cost, allocation.isRepeated) {
        case (.high, true):
            return .critical
        case (.high, false), (.medium, true):
            return .high
        case (.medium, false), (.low, true):
            return .medium
        case (.low, false):
            return .low
        }
    }
}

/// Syntax analyzer for tracking allocations
private class AllocationSyntaxAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let onAllocation: (AllocationTracker.Allocation) -> Void

    private var currentFunction: String?
    private var inLoop: Bool = false
    private var loopContext: String?
    private var allocationCounter: Int = 0

    init(sourceFile: SourceFile, onAllocation: @escaping (AllocationTracker.Allocation) -> Void) {
        self.sourceFile = sourceFile
        self.onAllocation = onAllocation
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Function Context

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunction = node.name.text
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        currentFunction = nil
    }

    // MARK: - Loop Context

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        inLoop = true
        loopContext = "for-in loop"
        defer {
            inLoop = false
            loopContext = nil
        }
        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        inLoop = true
        loopContext = "while loop"
        defer {
            inLoop = false
            loopContext = nil
        }
        return .visitChildren
    }

    // MARK: - Allocation Tracking

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let bindings = node.bindings.first else { return .skipChildren }

        if let initializer = bindings.initializer {
            trackAllocation(
                from: initializer.value,
                context: .variable,
                location: node.position
            )
        }

        return .skipChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        trackAllocation(
            from: node.calledExpression,
            context: .functionCall,
            location: node.position
        )
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        let allocationId = "closure_\(allocationCounter)"
        allocationCounter += 1

        let location = sourceFile.location(of: node)
        let sourceLocation = Location(
            file: sourceFile.url,
            line: location.line,
            column: location.column
        )

        let allocation = AllocationTracker.Allocation(
            id: allocationId,
            type: "Closure",
            location: sourceLocation,
            allocationType: .closure,
            context: .closure,
            isRepeated: inLoop,
            loopContext: loopContext
        )

        onAllocation(allocation)

        return .visitChildren
    }

    override func visit(_ node: ArrayExprSyntax) -> SyntaxVisitorContinueKind {
        let allocationId = "array_\(allocationCounter)"
        allocationCounter += 1

        let location = sourceFile.location(of: node)
        let sourceLocation = Location(
            file: sourceFile.url,
            line: location.line,
            column: location.column
        )

        let allocation = AllocationTracker.Allocation(
            id: allocationId,
            type: "Array",
            location: sourceLocation,
            allocationType: .array,
            context: .variable,
            isRepeated: inLoop,
            loopContext: loopContext
        )

        onAllocation(allocation)

        return .visitChildren
    }

    override func visit(_ node: DictionaryExprSyntax) -> SyntaxVisitorContinueKind {
        let allocationId = "dict_\(allocationCounter)"
        allocationCounter += 1

        let location = sourceFile.location(of: node)
        let sourceLocation = Location(
            file: sourceFile.url,
            line: location.line,
            column: location.column
        )

        let allocation = AllocationTracker.Allocation(
            id: allocationId,
            type: "Dictionary",
            location: sourceLocation,
            allocationType: .dictionary,
            context: .variable,
            isRepeated: inLoop,
            loopContext: loopContext
        )

        onAllocation(allocation)

        return .visitChildren
    }

    // MARK: - Helper Methods

    private func trackAllocation(from expression: ExprSyntax, context: AllocationTracker.AllocationContext, location: AbsolutePosition) {
        let expressionString = expression.trimmedDescription
        let allocationType = determineAllocationType(from: expressionString)

        guard allocationType != nil else { return }

        let allocationId = "alloc_\(allocationCounter)"
        allocationCounter += 1

        let loc = sourceFile.location(for: location)
        let sourceLocation = Location(
            file: sourceFile.url,
            line: loc.line,
            column: loc.column
        )
        guard let allocationType = allocationType else { return }

        let allocation = AllocationTracker.Allocation(
            id: allocationId,
            type: expressionString,
            location: sourceLocation,
            allocationType: allocationType,
            context: context,
            isRepeated: inLoop,
            loopContext: loopContext
        )

        onAllocation(allocation)
    }

    private func determineAllocationType(from expression: String) -> AllocationTracker.AllocationType? {
        // Simple heuristics for allocation type detection
        if expression.contains("String(") || expression.hasPrefix("\"") {
            return .string
        } else if expression.contains("Data(") {
            return .data
        } else if expression.contains("Array(") || expression.contains("[") {
            return .array
        } else if expression.contains("Dictionary(") || expression.contains(":") {
            return .dictionary
        } else if expression.hasPrefix("class ") || expression.contains("()") {
            return .classAllocation
        } else if expression.contains("struct ") {
            return .structAllocation
        }

        return nil
    }
}