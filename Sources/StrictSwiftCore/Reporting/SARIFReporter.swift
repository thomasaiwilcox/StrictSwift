import Foundation

/// SARIF 2.1.0 formatted reporter for GitHub Code Scanning and other SARIF-compatible tools
/// See: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
public struct SARIFReporter: Reporter {
    private let pretty: Bool
    private let includeRules: Bool
    
    public init(pretty: Bool = true, includeRules: Bool = true) {
        self.pretty = pretty
        self.includeRules = includeRules
    }
    
    public func generateReport(_ violations: [Violation]) throws -> String {
        return try generateReport(violations, metadata: nil, analysisWarnings: [])
    }
    
    public func generateReport(_ violations: [Violation], metadata: AnalysisMetadata?) throws -> String {
        return try generateReport(violations, metadata: metadata, analysisWarnings: [])
    }
    
    public func generateReport(_ violations: [Violation], metadata: AnalysisMetadata?, analysisWarnings: [String]) throws -> String {
        // Collect unique rules from violations
        let uniqueRuleIds = Set(violations.map { $0.ruleId })
        let rules = includeRules ? uniqueRuleIds.sorted().map { ruleId -> SARIFRule in
            let category = violations.first(where: { $0.ruleId == ruleId })?.category ?? .safety
            return SARIFRule(
                id: ruleId,
                name: ruleId.replacingOccurrences(of: "_", with: " ").capitalized,
                shortDescription: SARIFMessage(text: "StrictSwift rule: \(ruleId)"),
                fullDescription: nil,
                helpUri: "https://github.com/thomasaiwilcox/StrictSwift#\(ruleId)",
                properties: SARIFRuleProperties(
                    category: category.rawValue,
                    tags: [category.rawValue, "swift"]
                )
            )
        } : nil
        
        let results = violations.map { violation -> SARIFResult in
            SARIFResult(
                ruleId: violation.ruleId,
                ruleIndex: rules?.firstIndex(where: { $0.id == violation.ruleId }),
                level: sarifLevel(from: violation.severity),
                message: SARIFMessage(text: violation.message),
                locations: [sarifLocation(from: violation.location)],
                relatedLocations: violation.relatedLocations.isEmpty ? nil :
                    violation.relatedLocations.enumerated().map { index, loc in
                        SARIFRelatedLocation(
                            id: index,
                            physicalLocation: sarifPhysicalLocation(from: loc),
                            message: nil
                        )
                    },
                fixes: violation.structuredFixes.isEmpty ? nil :
                    violation.structuredFixes.map { fix in
                        SARIFFix(
                            description: SARIFMessage(text: fix.title),
                            artifactChanges: fix.edits.map { edit in
                                SARIFArtifactChange(
                                    artifactLocation: SARIFArtifactLocation(
                                        uri: edit.range.file,
                                        uriBaseId: "%SRCROOT%"
                                    ),
                                    replacements: [
                                        SARIFReplacement(
                                            deletedRegion: SARIFRegion(
                                                startLine: edit.range.startLine,
                                                startColumn: edit.range.startColumn,
                                                endLine: edit.range.endLine,
                                                endColumn: edit.range.endColumn
                                            ),
                                            insertedContent: SARIFArtifactContent(text: edit.newText)
                                        )
                                    ]
                                )
                            }
                        )
                    },
                fingerprints: ["stableId": violation.stableId],
                properties: violation.context.isEmpty ? nil : SARIFResultProperties(
                    additionalContext: violation.context
                )
            )
        }
        
        // Build invocation properties, handling nil metadata gracefully
        let invocationProperties: SARIFInvocationProperties?
        if let meta = metadata {
            invocationProperties = SARIFInvocationProperties(
                analysisMode: meta.semanticMode.rawValue,
                modeSource: meta.modeSource
            )
        } else {
            // No metadata provided - omit properties rather than crash
            invocationProperties = nil
        }
        
        // Convert analysis warnings to SARIF notifications
        let notifications: [SARIFNotification]? = analysisWarnings.isEmpty ? nil :
            analysisWarnings.map { warning in
                SARIFNotification(level: "warning", message: SARIFMessage(text: warning))
            }
        
        let run = SARIFRun(
            tool: SARIFTool(
                driver: SARIFToolComponent(
                    name: "StrictSwift",
                    informationUri: "https://github.com/thomasaiwilcox/StrictSwift",
                    version: "1.0.0",
                    semanticVersion: "1.0.0",
                    rules: rules
                )
            ),
            results: results,
            invocations: [
                SARIFInvocation(
                    executionSuccessful: true,
                    endTimeUtc: ISO8601DateFormatter().string(from: Date()),
                    toolExecutionNotifications: notifications,
                    properties: invocationProperties
                )
            ]
        )
        
        let sarif = SARIFLog(
            schema: "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
            version: "2.1.0",
            runs: [run]
        )
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .custom { codingPath in
            let key = codingPath.last!.stringValue
            // Convert $schema to proper key
            if key == "schema" {
                return SARIFCodingKey(stringValue: "$schema")!
            }
            return SARIFCodingKey(stringValue: key)!
        }
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        
        let data = try encoder.encode(sarif)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    // MARK: - Helpers
    
    private func sarifLevel(from severity: DiagnosticSeverity) -> String {
        switch severity {
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .info, .hint:
            return "note"
        }
    }
    
    private func sarifLocation(from location: Location) -> SARIFLocation {
        SARIFLocation(
            physicalLocation: sarifPhysicalLocation(from: location)
        )
    }
    
    private func sarifPhysicalLocation(from location: Location) -> SARIFPhysicalLocation {
        SARIFPhysicalLocation(
            artifactLocation: SARIFArtifactLocation(
                uri: location.file.path,
                uriBaseId: "%SRCROOT%"
            ),
            region: SARIFRegion(
                startLine: location.line,
                startColumn: location.column,
                endLine: location.line,
                endColumn: location.column
            )
        )
    }
    
    // MARK: - SARIF 2.1.0 Data Structures
    
    private struct SARIFCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }
        
        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
    
    private struct SARIFLog: Codable {
        let schema: String
        let version: String
        let runs: [SARIFRun]
        
        enum CodingKeys: String, CodingKey {
            case schema = "$schema"
            case version
            case runs
        }
    }
    
    private struct SARIFRun: Codable {
        let tool: SARIFTool
        let results: [SARIFResult]
        let invocations: [SARIFInvocation]?
    }
    
    private struct SARIFTool: Codable {
        let driver: SARIFToolComponent
    }
    
    private struct SARIFToolComponent: Codable {
        let name: String
        let informationUri: String?
        let version: String?
        let semanticVersion: String?
        let rules: [SARIFRule]?
    }
    
    private struct SARIFRule: Codable {
        let id: String
        let name: String
        let shortDescription: SARIFMessage?
        let fullDescription: SARIFMessage?
        let helpUri: String?
        let properties: SARIFRuleProperties?
    }
    
    private struct SARIFRuleProperties: Codable {
        let category: String
        let tags: [String]
    }
    
    private struct SARIFResult: Codable {
        let ruleId: String
        let ruleIndex: Int?
        let level: String
        let message: SARIFMessage
        let locations: [SARIFLocation]
        let relatedLocations: [SARIFRelatedLocation]?
        let fixes: [SARIFFix]?
        let fingerprints: [String: String]?
        let properties: SARIFResultProperties?
    }
    
    private struct SARIFResultProperties: Codable {
        let additionalContext: [String: String]
    }
    
    private struct SARIFMessage: Codable {
        let text: String
    }
    
    private struct SARIFLocation: Codable {
        let physicalLocation: SARIFPhysicalLocation
    }
    
    private struct SARIFRelatedLocation: Codable {
        let id: Int
        let physicalLocation: SARIFPhysicalLocation
        let message: SARIFMessage?
    }
    
    private struct SARIFPhysicalLocation: Codable {
        let artifactLocation: SARIFArtifactLocation
        let region: SARIFRegion
    }
    
    private struct SARIFArtifactLocation: Codable {
        let uri: String
        let uriBaseId: String?
    }
    
    private struct SARIFRegion: Codable {
        let startLine: Int
        let startColumn: Int
        let endLine: Int
        let endColumn: Int
    }
    
    private struct SARIFFix: Codable {
        let description: SARIFMessage
        let artifactChanges: [SARIFArtifactChange]
    }
    
    private struct SARIFArtifactChange: Codable {
        let artifactLocation: SARIFArtifactLocation
        let replacements: [SARIFReplacement]
    }
    
    private struct SARIFReplacement: Codable {
        let deletedRegion: SARIFRegion
        let insertedContent: SARIFArtifactContent
    }
    
    private struct SARIFArtifactContent: Codable {
        let text: String
    }
    
    private struct SARIFInvocation: Codable {
        let executionSuccessful: Bool
        let endTimeUtc: String
        let toolExecutionNotifications: [SARIFNotification]?
        let properties: SARIFInvocationProperties?
    }
    
    private struct SARIFNotification: Codable {
        let level: String
        let message: SARIFMessage
    }
    
    private struct SARIFInvocationProperties: Codable {
        let analysisMode: String?
        let modeSource: String?
    }
}
