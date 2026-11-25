// Orchestrates file selection, parsing + coverage attribution to produce
// [MethodMetric], plus the small helpers the selection needs: source-file
// discovery, git-changed files, `--diff-base` changed-line parsing, and
// glob matching.

import Foundation

public struct MethodMetric {
    public let methodName: String
    /// Project-relative path.
    public let file: String
    public let startLine: Int
    public let complexity: Int
    /// Fraction [0, 1], or nil (N/A).
    public let coverage: Double?
    public let crapScore: Double?
}

/// A coverage-input problem; the CLI maps it to exit 1. Unit-test coverage
/// is required — a CRAP score without coverage is meaningless.
public struct CoverageError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

public enum Analyzer {
    /// Analyze Swift files, combining complexity and coverage.
    /// `strict` treats a selected file with no coverage entry as 0.0% covered
    /// instead of N/A. `diffLines` (a `gitDiffLines` result) restricts the
    /// report to the functions whose line range intersects a changed line.
    public static func analyze(
        sourceFiles: [String],
        coverageRecords: [String: LcovRecord],
        strict: Bool,
        diffLines: [String: Set<Int>]?
    ) -> (metrics: [MethodMetric], parseFailures: [String]) {
        var metrics: [MethodMetric] = []
        var parseFailures: [String] = []
        for file in sourceFiles {
            let rel = relativePath(file)
            let allMethods = extractMethods(file: file, rel: rel, failures: &parseFailures)
            let methods = inDiffSelection(allMethods, diffLines: diffLines, rel: rel)
            if diffLines != nil && methods.isEmpty { continue }
            let fileCoverage = coverageRecords[rel]
            let uncovered = strict && coverageRecords[rel] == nil
            metrics.append(
                contentsOf: methods.map { descriptor in
                    metric(
                        descriptor,
                        file: rel,
                        record: fileCoverage,
                        uncovered: uncovered
                    )
                }
            )
        }
        return (sortedForReport(metrics), parseFailures)
    }

    /// Diff-scoped runs keep only the functions whose line range intersects
    /// an added/changed line; a file absent from the diff selects nothing.
    /// Without `diffLines` every method is kept.
    static func inDiffSelection(
        _ methods: [MethodDescriptor],
        diffLines: [String: Set<Int>]?,
        rel: String
    ) -> [MethodDescriptor] {
        guard let diffLines = diffLines else { return methods }
        guard let changed = diffLines[rel], !changed.isEmpty else { return [] }
        return methods.filter { descriptor in
            changed.contains { $0 >= descriptor.startLine && $0 <= descriptor.endLine }
        }
    }

    /// Load and relativize an lcov coverage file. A missing, unparseable or
    /// record-free file throws (fail-closed).
    public static func loadCoverage(path: String, projectRoot: String) throws -> [String: LcovRecord] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CoverageError(message: "coverage file not found at \(path)")
        }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw CoverageError(message: "failed to read coverage file \(path)")
        }
        let records = LcovParser.parse(text)
        guard !records.isEmpty else {
            throw CoverageError(message: "coverage file has no records for this project: \(path)")
        }
        return relativized(records, projectRoot: projectRoot)
    }

    /// `SF:` paths keyed project-relative; entries outside the root keep
    /// their written path (they can never match a selected source file).
    static func relativized(
        _ records: [String: LcovRecord],
        projectRoot: String
    ) -> [String: LcovRecord] {
        var result: [String: LcovRecord] = [:]
        for (path, record) in records {
            result[stripRoot(path, projectRoot: projectRoot)] = record
        }
        return result
    }

    static func stripRoot(_ path: String, projectRoot: String) -> String {
        guard path.hasPrefix("/") else { return path }
        let root = projectRoot.hasSuffix("/") ? String(projectRoot.dropLast()) : projectRoot
        if path.hasPrefix(root + "/") {
            return String(path.dropFirst(root.count + 1))
        }
        return path
    }

    static func relativePath(_ path: String) -> String {
        stripRoot(path, projectRoot: FileManager.default.currentDirectoryPath)
    }

    static func extractMethods(
        file: String,
        rel: String,
        failures: inout [String]
    ) -> [MethodDescriptor] {
        guard let source = try? String(contentsOfFile: file, encoding: .utf8) else {
            reportWarning("failed to read \(rel)")
            failures.append(rel)
            return []
        }
        return MethodExtractor.extract(source: source, fileName: rel)
    }

    static func metric(
        _ descriptor: MethodDescriptor,
        file: String,
        record: LcovRecord?,
        uncovered: Bool
    ) -> MethodMetric {
        let coverage = uncovered
            ? 0.0
            : coverageForMethod(record: record, startLine: descriptor.startLine, endLine: descriptor.endLine)
        let complexity = MethodExtractor.complexity(of: descriptor)
        return MethodMetric(
            methodName: descriptor.name,
            file: file,
            startLine: descriptor.startLine,
            complexity: complexity,
            coverage: coverage,
            crapScore: CrapScore.score(cc: complexity, coverage: coverage)
        )
    }

    static func reportWarning(_ message: String) {
        FileHandle.standardError.write(Data("Warning: \(message)\n".utf8))
    }

    /// Sort for the report: CRAP descending; N/A last; ties by file then
    /// start line.
    public static func sortedForReport(_ metrics: [MethodMetric]) -> [MethodMetric] {
        metrics.sorted { a, b in
            switch (a.crapScore, b.crapScore) {
            case (nil, nil):
                return tie(a, b)
            case (nil, _):
                return false
            case (_, nil):
                return true
            case (let aScore?, let bScore?):
                if aScore != bScore { return aScore > bScore }
                return tie(a, b)
            }
        }
    }

    static func tie(_ a: MethodMetric, _ b: MethodMetric) -> Bool {
        if a.file != b.file { return a.file < b.file }
        return a.startLine < b.startLine
    }

}

public enum SourceFiles {
    /// Expand files and directories into .swift files (directories walked
    /// recursively), sorted, project-relative paths preserved.
    public static func expand(_ paths: [String]) -> [String] {
        let fileManager = FileManager.default
        var result: [String] = []
        for path in paths {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                result.append(contentsOf: swiftFiles(under: path))
            } else if path.hasSuffix(".swift") {
                result.append(path)
            }
        }
        return result.sorted()
    }

    static func swiftFiles(under path: String) -> [String] {
        let enumerator = FileManager.default.enumerator(atPath: path)
        var result: [String] = []
        while let entry = enumerator?.nextObject() as? String {
            if entry.hasSuffix(".swift") {
                result.append(path.hasSuffix("/") ? path + entry : path + "/" + entry)
            }
        }
        return result
    }

    /// Git-changed (added/modified/renamed/untracked) files from
    /// `git status --porcelain`; deletions and unchanged files are excluded.
    public static func changed(cwd: String) throws -> [String] {
        let result = runProcess("/usr/bin/git", ["status", "--porcelain"], cwd: cwd)
        guard result.status == 0 else {
            throw CoverageError(message: "git status failed: \(result.stderr)")
        }
        return result.stdout.split(whereSeparator: \.isNewline)
            .compactMap { changedPath(fromLine: String($0)) }
    }

    static func changedPath(fromLine line: String) -> String? {
        guard line.count > 3 else { return nil }
        let status = String(line.prefix(2))
        if status.contains("D") || status == "  " { return nil }
        let path = String(line.dropFirst(3))
        if let arrow = path.range(of: " -> ") {
            return String(path[arrow.upperBound...])
        }
        return path
    }

    static func runProcess(
        _ launchPath: String,
        _ arguments: [String],
        cwd: String
    ) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try? process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: data, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

public enum DiffLines {
    /// Parses unified diff output (with `--unified=0` hunks) into a map of
    /// project-relative new path -> set of added/changed 1-based lines.
    public static func parse(_ raw: String) -> [String: Set<Int>] {
        var added: [String: Set<Int>] = [:]
        var current: String?
        for line in raw.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if text.hasPrefix("+++ ") {
                current = newPath(fromHeader: String(text.dropFirst(4)))
            } else if text.hasPrefix("@@ ") {
                addHunk(text, to: &added, file: current)
            }
        }
        return added
    }

    /// `git diff --unified=0 <ref> -- <paths...>`; git failure throws.
    public static func gitLines(
        ref: String,
        paths: [String],
        cwd: String
    ) throws -> [String: Set<Int>] {
        let result = SourceFiles.runProcess("/usr/bin/git", ["diff", "--unified=0", ref, "--"] + paths, cwd: cwd)
        guard result.status == 0 else {
            throw CoverageError(message: "git diff \(ref) failed: \(result.stderr)")
        }
        return parse(result.stdout)
    }

    static func newPath(fromHeader header: String) -> String? {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        if trimmed == "/dev/null" { return nil }
        if trimmed.hasPrefix("b/") { return String(trimmed.dropFirst(2)) }
        return trimmed
    }

    /// `@@ -l,c +l,c @@` — adds the new-file line range (count defaults to 1).
    static func addHunk(_ line: String, to added: inout [String: Set<Int>], file: String?) {
        guard let file = file, let plus = line.range(of: "+") else { return }
        let tail = String(line[plus.upperBound...])
        let fields = tail.prefix(while: { $0.isNumber || $0 == "," }).split(separator: ",")
        guard let start = Int(fields[0]) else { return }
        let count = fields.count > 1 ? Int(fields[1]) ?? 1 : 1
        let lines = Set((start..<(start + max(count, 1))).filter { $0 > 0 })
        added[file, default: []].formUnion(lines)
    }
}

public enum Glob {
    /// Shell-style glob: `*` within a path segment, `**` across segments,
    /// `?` a single non-separator character. Full-path match, anchored.
    public static func matches(pattern: String, path: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: regexSource(pattern)) else {
            return false
        }
        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    public static func anyMatches(patterns: [String], path: String) -> Bool {
        patterns.contains { matches(pattern: $0, path: path) }
    }

    static func regexSource(_ pattern: String) -> String {
        var out = "^"
        let characters = Array(pattern)
        var index = 0
        while index < characters.count {
            index = append(characters, at: index, into: &out)
        }
        return out + "$"
    }

    static func append(_ characters: [Character], at index: Int, into out: inout String) -> Int {
        let char = characters[index]
        if char == "*", index + 1 < characters.count, characters[index + 1] == "*" {
            out += ".*"
            return index + 2
        }
        if char == "*" {
            out += "[^/]*"
            return index + 1
        }
        if char == "?" {
            out += "[^/]"
            return index + 1
        }
        out += NSRegularExpression.escapedPattern(for: String(char))
        return index + 1
    }
}
