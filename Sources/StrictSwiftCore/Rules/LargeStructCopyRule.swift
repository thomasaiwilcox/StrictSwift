import Foundation
import SwiftSyntax
import SwiftParser

/// Rule that detects expensive struct copies and suggests performance optimizations
/// SAFETY: @unchecked Sendable is safe because allocationTracker is created in init()
/// and the analyze() method creates fresh analyzers per call for thread safety.
public final class LargeStructCopyRule: Rule, @unchecked Sendable {
    public var id: String { "large_struct_copy" }
    public var name: String { "Large Struct Copy" }
    public var description: String { "Detects expensive struct copies and suggests performance optimizations" }
    public var category: RuleCategory { .performance }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    // Infrastructure components for thread safety
    private let allocationTracker: AllocationTracker

    public init() {
        self.allocationTracker = AllocationTracker()
    }

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []

        // Get configuration
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }

        // Get configuration parameters
        // Default threshold is 128 bytes - structs under this size are typically
        // efficiently handled by the Swift compiler via registers or stack copies
        let maxStructSize = ruleConfig.parameter("maxStructSize", defaultValue: 128)
        let checkLoopStructCopies = ruleConfig.parameter("checkLoopStructCopies", defaultValue: true)
        let checkParameterStructCopies = ruleConfig.parameter("checkParameterStructCopies", defaultValue: true)
        let checkReturnValueStructCopies = ruleConfig.parameter("checkReturnValueStructCopies", defaultValue: true)
        let checkPropertyStructCopies = ruleConfig.parameter("checkPropertyStructCopies", defaultValue: true)

        // Perform struct copy analysis
        let source = sourceFile.source()
        let tree = Parser.parse(source: source)

        let copyAnalyzer = StructCopyAnalyzer(
            sourceFile: sourceFile,
            ruleConfig: ruleConfig,
            maxStructSize: maxStructSize,
            checkLoopStructCopies: checkLoopStructCopies,
            checkParameterStructCopies: checkParameterStructCopies,
            checkReturnValueStructCopies: checkReturnValueStructCopies,
            checkPropertyStructCopies: checkPropertyStructCopies
        )
        copyAnalyzer.walk(tree)

        violations.append(contentsOf: copyAnalyzer.violations)

        return violations
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}

/// Syntax analyzer for struct copy violations
private class StructCopyAnalyzer: SyntaxAnyVisitor {
    private let sourceFile: SourceFile
    private let ruleConfig: RuleSpecificConfiguration
    private let maxStructSize: Int
    private let checkLoopStructCopies: Bool
    private let checkParameterStructCopies: Bool
    private let checkReturnValueStructCopies: Bool
    private let checkPropertyStructCopies: Bool

    var violations: [Violation] = []
    private var inLoop: Bool = false
    private var currentFunction: String?
    private var structDefinitions: [String: StructInfo] = [:]

    init(
        sourceFile: SourceFile,
        ruleConfig: RuleSpecificConfiguration,
        maxStructSize: Int,
        checkLoopStructCopies: Bool,
        checkParameterStructCopies: Bool,
        checkReturnValueStructCopies: Bool,
        checkPropertyStructCopies: Bool
    ) {
        self.sourceFile = sourceFile
        self.ruleConfig = ruleConfig
        self.maxStructSize = maxStructSize
        self.checkLoopStructCopies = checkLoopStructCopies
        self.checkParameterStructCopies = checkParameterStructCopies
        self.checkReturnValueStructCopies = checkReturnValueStructCopies
        self.checkPropertyStructCopies = checkPropertyStructCopies
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Struct Definition Analysis

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let structName = node.name.text
        let structInfo = analyzeStructDefinition(node)
        structDefinitions[structName] = structInfo

        return .skipChildren
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
        defer { inLoop = false }
        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        inLoop = true
        defer { inLoop = false }
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        inLoop = true
        defer { inLoop = false }
        return .visitChildren
    }

    // MARK: - Struct Copy Analysis

    override func visit(_ node: FunctionParameterClauseSyntax) -> SyntaxVisitorContinueKind {
        if checkParameterStructCopies {
            for parameter in node.parameters {
                analyzeParameterStructCopy(parameter, location: node.position)
            }
        }
        return .skipChildren
    }

    override func visit(_ node: ReturnStmtSyntax) -> SyntaxVisitorContinueKind {
        if checkReturnValueStructCopies, let expression = node.expression {
            analyzeReturnStructCopy(expression, location: node.position)
        }
        return .skipChildren
    }

    override func visit(_ node: AssignmentExprSyntax) -> SyntaxVisitorContinueKind {
        if checkPropertyStructCopies {
            analyzeAssignmentStructCopy(node, location: node.position)
        }
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let bindings = node.bindings.first else { return .skipChildren }

        if let initializer = bindings.initializer {
            analyzeVariableStructCopy(initializer.value, location: node.position)
        }

        return .skipChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let calledFunction = node.calledExpression.trimmedDescription
        analyzeFunctionCallStructCopy(calledFunction, arguments: TupleExprSyntax(elements: node.arguments), location: node.position)
        return .visitChildren
    }

    // MARK: - Helper Methods

    private func analyzeStructDefinition(_ node: StructDeclSyntax) -> StructInfo {
        var propertyCount = 0
        var estimatedSize: Int = 0
        var hasLargeProperties = false
        var hasCopyOnWriteProperties = false

        // Analyze properties
        for member in node.memberBlock.members {
            if let variableDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in variableDecl.bindings {
                    propertyCount += 1

                    // Estimate size based on type
                    if let typeAnnotation = binding.typeAnnotation {
                        let typeString = typeAnnotation.type.trimmedDescription
                        estimatedSize += estimateTypeSize(typeString)

                        if isLargeType(typeString) {
                            hasLargeProperties = true
                        }

                        if isCopyOnWriteType(typeString) {
                            hasCopyOnWriteProperties = true
                        }
                    } else {
                        estimatedSize += 8 // Default assumption
                    }
                }
            }
        }

        return StructInfo(
            name: node.name.text,
            propertyCount: propertyCount,
            estimatedSize: estimatedSize,
            hasLargeProperties: hasLargeProperties,
            hasCopyOnWriteProperties: hasCopyOnWriteProperties,
            location: node.position
        )
    }

    private func analyzeParameterStructCopy(_ parameter: FunctionParameterSyntax, location: AbsolutePosition) {
        let type = parameter.type

        let typeString = type.trimmedDescription
        let structName = extractStructName(from: typeString)

        if let structInfo = structDefinitions[structName], isLargeStruct(structInfo) {
            let locationInfo = sourceFile.location(for: location)
            let violation = ViolationBuilder(
                ruleId: "large_struct_copy",
                category: .performance,
                location: locationInfo
            )
            .message("Large struct '\(structName)' (estimated size: \(structInfo.estimatedSize) bytes) passed as parameter")
            .suggestFix("Consider using 'inout' parameter or passing by reference")
            .severity(.warning)
            .build()

            violations.append(violation)
        }
    }

    private func analyzeReturnStructCopy(_ expression: ExprSyntax, location: AbsolutePosition) {
        let expressionString = expression.trimmedDescription
        let structName = extractStructName(from: expressionString)

        if let structInfo = structDefinitions[structName], isLargeStruct(structInfo) {
            let locationInfo = sourceFile.location(for: location)
            let violation = ViolationBuilder(
                ruleId: "large_struct_copy",
                category: .performance,
                location: locationInfo
            )
            .message("Returning large struct '\(structName)' (estimated size: \(structInfo.estimatedSize) bytes) causes copy")
            .suggestFix("Consider returning a class or using 'inout' parameter for modification")
            .severity(.warning)
            .build()

            violations.append(violation)
        }
    }

    private func analyzeAssignmentStructCopy(_ assignment: AssignmentExprSyntax, location: AbsolutePosition) {
        // In SwiftSyntax 600.0.0, AssignmentExprSyntax structure has changed
        let children = assignment.children(viewMode: .sourceAccurate)
        var childArray = Array(children)

        var lhsString = ""
        var rhsString = ""

        if childArray.count >= 3 {
            // First child should be the left side (LHS)
            if let lhsExpr = childArray[0].as(ExprSyntax.self) {
                lhsString = lhsExpr.trimmedDescription
            }

            // Third child should be the right side (RHS)
            if let rhsExpr = childArray[2].as(ExprSyntax.self) {
                rhsString = rhsExpr.trimmedDescription
            }
        }

        // Check if we're copying a large struct
        let structName = extractStructName(from: rhsString)

        if let structInfo = structDefinitions[structName], isLargeStruct(structInfo) {
            if inLoop && checkLoopStructCopies {
                let locationInfo = sourceFile.location(for: location)
                let violation = ViolationBuilder(
                    ruleId: "large_struct_copy",
                    category: .performance,
                    location: locationInfo
                )
                .message("Large struct '\(structName)' copy inside loop (estimated size: \(structInfo.estimatedSize) bytes)")
                .suggestFix("Move struct creation outside loop or use class instead")
                .severity(.error)
                .build()

                violations.append(violation)
            } else {
                let locationInfo = sourceFile.location(for: location)
                let violation = ViolationBuilder(
                    ruleId: "large_struct_copy",
                    category: .performance,
                    location: locationInfo
                )
                .message("Large struct '\(structName)' copy detected (estimated size: \(structInfo.estimatedSize) bytes)")
                .suggestFix("Consider using class or copy-on-write types")
                .severity(.info)
                .build()

                violations.append(violation)
            }
        }
    }

    private func analyzeVariableStructCopy(_ expression: ExprSyntax, location: AbsolutePosition) {
        let expressionString = expression.trimmedDescription
        let structName = extractStructName(from: expressionString)

        if let structInfo = structDefinitions[structName], isLargeStruct(structInfo) {
            let locationInfo = sourceFile.location(for: location)
            let violation = ViolationBuilder(
                ruleId: "large_struct_copy",
                category: .performance,
                location: locationInfo
            )
            .message("Variable initialization creates large struct '\(structName)' copy (estimated size: \(structInfo.estimatedSize) bytes)")
            .suggestFix("Consider lazy initialization or class type")
            .severity(.info)
            .build()

            violations.append(violation)
        }
    }

    private func analyzeFunctionCallStructCopy(_ functionName: String, arguments: TupleExprSyntax?, location: AbsolutePosition) {
        guard let arguments = arguments else { return }

        // In SwiftSyntax 600.0.0, TupleExprSyntax structure has changed
        for argument in arguments.elements {
            // In SwiftSyntax 600.0.0, expression is not optional
            let expression = argument.expression
            let expressionString = expression.trimmedDescription
            let structName = extractStructName(from: expressionString)

            if let structInfo = structDefinitions[structName], isLargeStruct(structInfo) {
                let locationInfo = sourceFile.location(for: location)
                let violation = ViolationBuilder(
                    ruleId: "large_struct_copy",
                    category: .performance,
                    location: locationInfo
                )
                .message("Large struct '\(structName)' passed to function '\(functionName)' causing copy")
                .suggestFix("Consider using 'inout' parameter or redesign API")
                .severity(.warning)
                .build()

                violations.append(violation)
            }
        }
    }

    // MARK: - Analysis Helper Methods

    private func isLargeStruct(_ structInfo: StructInfo) -> Bool {
        // Only flag truly large structs - over 128 bytes or with many properties
        // Note: hasLargeProperties is NOT checked because String, Data, URL, Date
        // are all copy-on-write types in Swift and are very cheap to copy
        return structInfo.estimatedSize > maxStructSize ||
               structInfo.propertyCount > 15
    }

    private func estimateTypeSize(_ typeString: String) -> Int {
        // Basic type size estimation
        let basicSizes: [String: Int] = [
            "Int": 8, "Int8": 1, "Int16": 2, "Int32": 4, "Int64": 8,
            "UInt": 8, "UInt8": 1, "UInt16": 2, "UInt32": 4, "UInt64": 8,
            "Float": 4, "Double": 8, "Bool": 1, "Character": 1,
            "String": 16, "Data": 24, "Date": 8, "URL": 16
        ]

        for (type, size) in basicSizes {
            if typeString.contains(type) {
                return size
            }
        }

        // Array or Dictionary
        if typeString.contains("[") || typeString.contains("Array") {
            return 24 // Array header size
        }

        // Default assumption
        return 8
    }

    private func isLargeType(_ typeString: String) -> Bool {
        let largeTypes = ["Data", "String", "URL", "Date", "UIImage", "UIViewController"]
        return largeTypes.contains { typeString.contains($0) }
    }

    private func isCopyOnWriteType(_ typeString: String) -> Bool {
        let copyOnWriteTypes = ["String", "Array", "Dictionary", "Set", "Data"]
        return copyOnWriteTypes.contains { typeString.contains($0) }
    }

    private func extractStructName(from expression: String) -> String {
        // Extract potential struct name from expression
        let components = expression.components(separatedBy: " .(),")
        return components.first ?? ""
    }
}

/// Information about a struct definition
private struct StructInfo {
    let name: String
    let propertyCount: Int
    let estimatedSize: Int
    let hasLargeProperties: Bool
    let hasCopyOnWriteProperties: Bool
    let location: AbsolutePosition

    init(name: String, propertyCount: Int, estimatedSize: Int, hasLargeProperties: Bool, hasCopyOnWriteProperties: Bool, location: AbsolutePosition) {
        self.name = name
        self.propertyCount = propertyCount
        self.estimatedSize = estimatedSize
        self.hasLargeProperties = hasLargeProperties
        self.hasCopyOnWriteProperties = hasCopyOnWriteProperties
        self.location = location
    }
}