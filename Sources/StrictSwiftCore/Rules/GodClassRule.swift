import Foundation
import SwiftSyntax

/// Detects classes that violate Single Responsibility Principle
public final class GodClassRule: Rule {
    public var id: String { "god_class" }
    public var name: String { "God Class" }
    public var description: String { "Detects classes that have too many responsibilities" }
    public var category: RuleCategory { .architecture }
    public var defaultSeverity: DiagnosticSeverity { .warning }
    public var enabledByDefault: Bool { true }

    // Default configuration thresholds (can be overridden via configuration)
    private let defaultMaxMethods: Int = 15
    private let defaultMaxProperties: Int = 10
    private let defaultMaxLines: Int = 200
    private let defaultMaxDependencies: Int = 8

    public init() {}

    public func analyze(_ sourceFile: SourceFile, in context: AnalysisContext) async -> [Violation] {
        var violations: [Violation] = []
        let source = sourceFile.source()
        
        // Get configuration for this rule
        let ruleConfig = context.configuration.configuration(for: id, file: sourceFile.url.path)
        let maxMethods = ruleConfig.parameter("maxMethods", defaultValue: defaultMaxMethods)
        let maxProperties = ruleConfig.parameter("maxProperties", defaultValue: defaultMaxProperties)
        let maxLines = ruleConfig.parameter("maxLines", defaultValue: defaultMaxLines)
        let maxDependencies = ruleConfig.parameter("maxDependencies", defaultValue: defaultMaxDependencies)

        // Use text-based analysis for the whole file
        violations = analyzeSourceCode(source, sourceFile: sourceFile, maxMethods: maxMethods, maxProperties: maxProperties, maxLines: maxLines, maxDependencies: maxDependencies)

        return violations
    }

    private func analyzeSourceCode(_ source: String, sourceFile: SourceFile, maxMethods: Int, maxProperties: Int, maxLines: Int, maxDependencies: Int) -> [Violation] {
        var violations: [Violation] = []

        // Find all class declarations using a simpler pattern - match just the class declaration line
        let classPattern = #"class\s+([A-Za-z][A-Za-z0-9]*)\s*\{"#

        do {
            let regex = try NSRegularExpression(pattern: classPattern, options: [.dotMatchesLineSeparators])
            let matches = regex.matches(in: source, range: NSRange(location: 0, length: source.utf16.count))

            for match in matches {
                let range = match.range
                if range.location != NSNotFound && range.length > 0 {
                    let start = source.index(source.startIndex, offsetBy: range.location)
                    let end = source.index(start, offsetBy: range.length)
                    let classDeclaration = String(source[start..<end])

                    // Find the class name and extract the entire class content from the full source
                    if let violation = analyzeClassFromDeclaration(classDeclaration, sourceFile: sourceFile, fullSource: source, maxMethods: maxMethods, maxProperties: maxProperties, maxLines: maxLines, maxDependencies: maxDependencies) {
                        violations.append(violation)
                    }
                }
            }
        } catch {
            // Log regex failure for debugging
            StrictSwiftLogger.warning("GodClassRule regex failed: \(error.localizedDescription)")
        }

        return violations
    }

    private func analyzeClassFromDeclaration(_ classDeclaration: String, sourceFile: SourceFile, fullSource: String, maxMethods: Int, maxProperties: Int, maxLines: Int, maxDependencies: Int) -> Violation? {
        // Extract class name from declaration
        let pattern = "class\\s+([A-Za-z][A-Za-z0-9]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: classDeclaration, range: NSRange(location: 0, length: classDeclaration.utf16.count)) else {
            return nil
        }

        let nameRange = match.range(at: 1)
        let start = classDeclaration.index(classDeclaration.startIndex, offsetBy: nameRange.location)
        let end = classDeclaration.index(start, offsetBy: nameRange.length)
        let className = String(classDeclaration[start..<end])

        // Find the class in the full source and extract the entire content
        let fullLines = fullSource.components(separatedBy: .newlines)
        var classLineNumber = 1
        var foundClassStart = false
        var braceCount = 0
        var classLines: [String] = []

        for (index, line) in fullLines.enumerated() {
            if line.contains("class ") && line.contains(className) {
                classLineNumber = index + 1
                foundClassStart = true
            }

            if foundClassStart {
                classLines.append(line)

                // Count braces to find the end of the class
                braceCount += line.components(separatedBy: "{").count - 1
                braceCount -= line.components(separatedBy: "}").count - 1

                if braceCount <= 0 {
                    break
                }
            }
        }

        guard !classLines.isEmpty else { return nil }

        // Count methods, properties, and dependencies
        var methodCount = 0
        var propertyCount = 0
        var dependencies: Set<String> = []

        for line in classLines {
            // Count methods
            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("func ") {
                methodCount += 1
            }

            // Count properties
            if (line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("let ") ||
                line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("var ")) &&
               !line.contains("func ") {
                propertyCount += 1

                // Extract dependencies from property types
                if line.contains(":") {
                    if let colonRange = line.range(of: ":") {
                        let afterColon = line[colonRange.upperBound...]
                        let components = afterColon.trimmingCharacters(in: .whitespaces)
                            .components(separatedBy: .whitespaces)
                            .filter { !$0.isEmpty }
                        if let typeName = components.first {
                            let cleanType = typeName.components(separatedBy: "=").first ?? typeName
                            let finalType = cleanType.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !finalType.isEmpty {
                                dependencies.insert(finalType)
                            }
                        }
                    }
                }
            }
        }

        // Check thresholds and create violations
        var violationsList: [String] = []

        if methodCount > maxMethods {
            violationsList.append("excessive methods: \(methodCount) > \(maxMethods)")
        }

        if propertyCount > maxProperties {
            violationsList.append("excessive properties: \(propertyCount) > \(maxProperties)")
        }

        if dependencies.count > maxDependencies {
            violationsList.append("excessive dependencies: \(dependencies.count) > \(maxDependencies)")
        }

        if !violationsList.isEmpty {
            let location = Location(
                file: sourceFile.url,
                line: classLineNumber,
                column: 1
            )

            return ViolationBuilder(
                ruleId: "god_class",
                category: .architecture,
                location: location
            )
            .message("Class '\(className)' has too many responsibilities: \(violationsList.joined(separator: ", "))")
            .suggestFix("Consider breaking '\(className)' into smaller classes with single responsibilities")
            .severity(.warning)
            .build()
        }

        return nil
    }

    public func shouldAnalyze(_ sourceFile: SourceFile) -> Bool {
        return sourceFile.url.pathExtension == "swift"
    }
}