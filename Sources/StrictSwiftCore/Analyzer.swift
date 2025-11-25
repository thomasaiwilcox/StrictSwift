import Foundation
import SystemPackage

/// Main analyzer that orchestrates StrictSwift analysis
public final class Analyzer: Sendable {
    private let configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    /// Analyze the given paths for violations
    public func analyze(paths: [String]) async throws -> [Violation] {
        // Find all Swift files
        let swiftFiles = try findSwiftFiles(in: paths)

        // Parse source files
        let sourceFiles = try await parseFiles(swiftFiles)

        // Analyze with rule engine
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let context = AnalysisContext(configuration: configuration, projectRoot: projectRoot)

        // Add all source files to context
        for file in sourceFiles {
            context.addSourceFile(file)
        }

        // Filter files based on include/exclude patterns
        let filteredFiles = sourceFiles.filter { file in
            context.isIncluded(file.path)
        }

        // Run analysis
        let ruleEngine = await RuleEngine()
        let violations = await ruleEngine.analyze(filteredFiles, in: context, configuration: configuration)

        // Apply baseline filtering if configured
        if let baseline = configuration.baseline {
            return filterWithBaseline(violations, baseline: baseline, projectRoot: projectRoot)
        }

        return violations
    }

    /// Find all Swift files in the given paths
    private func findSwiftFiles(in paths: [String]) throws -> [URL] {
        var allFiles: [URL] = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false

            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Recursively find Swift files
                    allFiles.append(contentsOf: try findSwiftFilesInDirectory(url))
                } else if url.pathExtension == "swift" {
                    allFiles.append(url)
                }
            }
        }

        return allFiles.removingDuplicates()
    }

    /// Find all Swift files in a directory recursively
    private func findSwiftFilesInDirectory(_ directory: URL) throws -> [URL] {
        var files: [URL] = []

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let directoryEnumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys
        ) else {
            return files
        }

        for case let fileURL as URL in directoryEnumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))

            if resourceValues.isDirectory == true {
                // Skip .build and other hidden directories
                let name = resourceValues.name ?? ""
                if name.hasPrefix(".") || name == "build" || name == "DerivedData" {
                    directoryEnumerator.skipDescendants()
                }
            } else if fileURL.pathExtension == "swift" {
                files.append(fileURL)
            }
        }

        return files
    }

    /// Parse Swift files into SourceFile objects
    private func parseFiles(_ urls: [URL]) async throws -> [SourceFile] {
        return try await withThrowingTaskGroup(of: SourceFile.self, returning: [SourceFile].self) { group in
            var files: [SourceFile] = []

            for url in urls {
                group.addTask {
                    return try SourceFile(url: url)
                }
            }

            while let file = try await group.next() {
                files.append(file)
            }

            return files
        }
    }

    /// Filter violations using baseline
    private func filterWithBaseline(
        _ violations: [Violation],
        baseline: BaselineConfiguration,
        projectRoot: URL
    ) -> [Violation] {
        // Check if baseline has expired
        if baseline.isExpired {
            let expiryDescription = baseline.expires?.description ?? "unknown date"
            StrictSwiftLogger.warning("Baseline expired on \(expiryDescription)")
            return violations
        }

        // Create set of baseline fingerprints for fast lookup
        let baselineFingerprints = Set(baseline.violations)

        // Filter out violations that are in the baseline
        return violations.filter { violation in
            let fingerprint = ViolationFingerprint(violation: violation, projectRoot: projectRoot)
            return !baselineFingerprints.contains(fingerprint)
        }
    }
}

/// Extension for removing duplicates
private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}