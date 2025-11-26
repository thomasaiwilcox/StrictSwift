import Foundation
import SwiftSyntax

/// Detects dead (unreachable) code using whole-program analysis
public final class DeadCodeRule: Rule, Sendable {
    public var id: String { "dead-code" }
    public var name: String { "Dead Code Detection" }
    public var description: String { "Identifies unused functions, types, and properties across the codebase" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }
    
    /// Configuration for the analyzer
    private let analyzerConfiguration: DeadCodeConfiguration
    
    /// Minimum confidence level to report (filters out low confidence by default)
    private let minimumConfidence: DeadCodeConfidence
    
    public init(configuration: DeadCodeConfiguration = .libraryDefault, minimumConfidence: DeadCodeConfidence = .low) {
        self.analyzerConfiguration = configuration
        self.minimumConfidence = minimumConfidence
    }
    
    public convenience init() {
        self.init(configuration: .libraryDefault, minimumConfidence: .low)
    }

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        // Dead code analysis requires all files - we only run on the first file
        // and analyze the entire project, then filter violations for this file
        let allFiles = context.allSourceFiles
        guard !allFiles.isEmpty else {
            return []
        }
        
        // Only perform analysis once, on the first file
        guard sourceFile.url == allFiles.first?.url else {
            return []
        }
        
        // Get rule configuration from context
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        guard context.configuration.shouldAnalyze(ruleId: id, file: sourceFile.url.path) else { return [] }
        guard ruleConfig.enabled else { return [] }
        
        // Build DeadCodeConfiguration from parameters or use default
        let deadCodeConfig = buildConfiguration(from: ruleConfig, context: context)
        
        // Get minimum confidence from config (default: low = report all)
        let minConfidenceString = ruleConfig.parameter("minimumConfidence", defaultValue: "low")
        let minConfidence = DeadCodeConfidence(rawValue: minConfidenceString) ?? minimumConfidence
        
        // Use the shared global reference graph (lazily built on first access)
        let graph = context.globalGraph()
        
        // Run dead code analysis
        let analyzer = DeadCodeAnalyzer(graph: graph, configuration: deadCodeConfig)
        let result = analyzer.analyze()
        
        // Convert dead symbols to violations, filtering by confidence
        return result.deadSymbolsWithConfidence
            .filter { $0.confidence >= minConfidence }
            .map { deadInfo in
                createViolation(for: deadInfo.symbol, confidence: deadInfo.confidence, result: result)
            }
    }
    
    /// Build DeadCodeConfiguration from rule-specific parameters
    private func buildConfiguration(from ruleConfig: RuleSpecificConfiguration, context: AnalysisContext) -> DeadCodeConfiguration {
        // Convert ConfigurationValue parameters to [String: Any]
        var params: [String: Any] = [:]
        
        // Extract mode - if not specified, try to auto-detect
        if let mode = ruleConfig.parameters["mode"] {
            params["mode"] = mode.stringValue
        } else {
            // Auto-detect mode based on project structure
            let detectedMode = detectProjectMode(from: context)
            params["mode"] = detectedMode.rawValue
        }
        
        // Extract boolean parameters
        if let treatPublicAsEntryPoint = ruleConfig.parameters["treatPublicAsEntryPoint"],
           let boolValue = treatPublicAsEntryPoint.boolValue {
            params["treatPublicAsEntryPoint"] = boolValue
        }
        if let treatOpenAsEntryPoint = ruleConfig.parameters["treatOpenAsEntryPoint"],
           let boolValue = treatOpenAsEntryPoint.boolValue {
            params["treatOpenAsEntryPoint"] = boolValue
        }
        
        // Extract array parameters (convert ConfigurationValue arrays to String arrays)
        if let ignoredPrefixes = ruleConfig.parameters["ignoredPrefixes"],
           let arrayValue = ignoredPrefixes.arrayValue {
            params["ignoredPrefixes"] = arrayValue.map { $0.stringValue }
        }
        if let ignoredPatterns = ruleConfig.parameters["ignoredPatterns"],
           let arrayValue = ignoredPatterns.arrayValue {
            params["ignoredPatterns"] = arrayValue.map { $0.stringValue }
        }
        if let entryPointAttributes = ruleConfig.parameters["entryPointAttributes"],
           let arrayValue = entryPointAttributes.arrayValue {
            params["entryPointAttributes"] = arrayValue.map { $0.stringValue }
        }
        if let entryPointFilePatterns = ruleConfig.parameters["entryPointFilePatterns"],
           let arrayValue = entryPointFilePatterns.arrayValue {
            params["entryPointFilePatterns"] = arrayValue.map { $0.stringValue }
        }
        
        return DeadCodeConfiguration.from(parameters: params)
    }
    
    /// Detect project mode based on project structure
    private func detectProjectMode(from context: AnalysisContext) -> DeadCodeMode {
        let allFiles = context.allSourceFiles
        
        // Check for @main attribute in any file
        let hasMainAttribute = allFiles.contains { file in
            file.symbols.contains { symbol in
                symbol.attributes.contains { $0.name == "main" }
            }
        }
        
        // Check for main.swift
        let hasMainSwift = allFiles.contains { file in
            file.url.lastPathComponent == "main.swift"
        }
        
        // Check for Package.swift to determine if it's an SPM package
        let projectRoot = context.projectRoot
        let packageSwiftURL = projectRoot.appendingPathComponent("Package.swift")
        let hasPackageSwift = FileManager.default.fileExists(atPath: packageSwiftURL.path)
        
        if hasPackageSwift {
            // For SPM packages, check Package.swift content for target types
            if let packageContent = try? String(contentsOf: packageSwiftURL, encoding: .utf8) {
                let hasLibraryTarget = packageContent.contains(".library(") || packageContent.contains(".library (")
                let hasExecutableTarget = packageContent.contains(".executableTarget(") || packageContent.contains(".executableTarget (")
                
                if hasLibraryTarget && hasExecutableTarget {
                    return .hybrid
                } else if hasExecutableTarget {
                    return .executable
                } else if hasLibraryTarget {
                    return .library
                }
            }
        }
        
        // Fall back to detection based on entry points
        if hasMainAttribute || hasMainSwift {
            return .executable
        }
        
        // Default to library mode (safer, fewer false positives)
        return .library
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
    
    // MARK: - Violation Creation
    
    private func createViolation(for symbol: Symbol, confidence: DeadCodeConfidence, result: DeadCodeResult) -> Violation {
        let symbolKindDescription = describeSymbolKind(symbol.kind)
        let confidenceLabel = confidenceDescription(confidence)
        let message = "\(symbolKindDescription) '\(symbol.name)' appears to be unused (\(confidenceLabel) confidence)"
        
        var builder = ViolationBuilder(
            ruleId: id,
            category: category,
            location: symbol.location
        )
        .severity(severityForConfidence(confidence))
        .message(message)
        .addContext(key: "symbolId", value: symbol.id.id)
        .addContext(key: "symbolKind", value: symbol.kind.rawValue)
        .addContext(key: "qualifiedName", value: symbol.qualifiedName)
        .addContext(key: "accessibility", value: symbol.accessibility.rawValue)
        .addContext(key: "confidence", value: confidence.rawValue)
        
        // Add suggested fix based on symbol kind
        builder = builder.suggestFix(suggestedFixFor(symbol, confidence: confidence))
        
        // Add structured fix for removal
        if let structuredFix = createStructuredFix(for: symbol, confidence: confidence) {
            builder = builder.addStructuredFix(structuredFix)
        }
        
        return builder.build()
    }
    
    private func confidenceDescription(_ confidence: DeadCodeConfidence) -> String {
        switch confidence {
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        }
    }
    
    private func describeSymbolKind(_ kind: SymbolKind) -> String {
        switch kind {
        case .class: return "Class"
        case .struct: return "Struct"
        case .enum: return "Enum"
        case .protocol: return "Protocol"
        case .actor: return "Actor"
        case .function: return "Function"
        case .variable: return "Property"
        case .initializer: return "Initializer"
        case .typeAlias: return "Type alias"
        case .case: return "Enum case"
        case .subscript: return "Subscript"
        case .operator: return "Operator"
        case .precedenceGroup: return "Precedence group"
        case .macro: return "Macro"
        case .extension: return "Extension"
        case .deinitializer: return "Deinitializer"
        case .associatedType: return "Associated type"
        }
    }
    
    private func severityForConfidence(_ confidence: DeadCodeConfidence) -> DiagnosticSeverity {
        switch confidence {
        case .high:
            return .warning
        case .medium:
            return .warning
        case .low:
            return .hint
        }
    }
    
    private func suggestedFixFor(_ symbol: Symbol, confidence: DeadCodeConfidence) -> String {
        let confidenceNote = confidence == .low ? " (verify external usage before removing)" : ""
        
        switch symbol.kind {
        case .function:
            return "Remove unused function '\(symbol.name)' or mark it with @available(*, deprecated)\(confidenceNote)"
        case .class, .struct, .enum, .actor:
            return "Remove unused type '\(symbol.name)' or consider if it's needed for future use\(confidenceNote)"
        case .variable:
            return "Remove unused property '\(symbol.name)'\(confidenceNote)"
        case .initializer:
            return "Remove unused initializer or consider if a public factory method is needed\(confidenceNote)"
        case .protocol:
            return "Remove unused protocol '\(symbol.name)' or implement conforming types\(confidenceNote)"
        case .case:
            return "Remove unused enum case '\(symbol.name)'\(confidenceNote)"
        default:
            return "Consider removing unused \(symbol.kind.rawValue) '\(symbol.name)'\(confidenceNote)"
        }
    }
    
    // MARK: - Structured Fixes
    
    private func createStructuredFix(for symbol: Symbol, confidence: DeadCodeConfidence) -> StructuredFix? {
        // Only provide structured fixes for high/medium confidence
        guard confidence >= .medium else { return nil }
        
        let symbolKindDescription = describeSymbolKind(symbol.kind).lowercased()
        let title = "Remove unused \(symbolKindDescription) '\(symbol.name)'"
        
        // Create a text edit to mark the location
        // Note: Full removal requires knowing the extent of the declaration.
        // For now, we create a marker edit. A more sophisticated
        // approach would parse to find the full declaration extent.
        let range = SourceRange(
            startLine: symbol.location.line,
            startColumn: symbol.location.column,
            endLine: symbol.location.line,
            endColumn: symbol.location.column,
            file: symbol.location.file.path
        )
        
        let edit = TextEdit(range: range, newText: "")
        
        return StructuredFix(
            title: title,
            kind: .removeCode,
            edits: [edit],
            isPreferred: confidence == .high,
            confidence: confidence == .high ? .suggested : .experimental,
            description: "Remove the unused \(symbolKindDescription) declaration",
            ruleId: id
        )
    }
}
