// CRAP formula, report formatting, and analysis orchestration.

import Testing
import Foundation
@testable import crap4swiftCore

struct CrapScoreTests {
    @Test func formulaValues() {
        #expect(CrapScore.score(cc: 2, coverage: 1.0) == 2.0)
        #expect(CrapScore.score(cc: 5, coverage: 0.0) == 30.0)
        #expect(CrapScore.score(cc: 1, coverage: 0.0) == 2.0)
    }

    @Test func nilCoverageIsNil() {
        #expect(CrapScore.score(cc: 3, coverage: nil) == nil)
    }

    @Test func thresholdBoundary() {
        // CC 8 fully covered: CRAP 8.0 — at the threshold, not above.
        #expect(CrapScore.score(cc: 8, coverage: 1.0)! == 8.0)
        #expect(!Report.exceedsThreshold(max: 8.0, threshold: 8.0))
        #expect(Report.exceedsThreshold(max: 8.1, threshold: 8.0))
    }
}

private func metric(
    name: String,
    file: String = "f.swift",
    line: Int = 1,
    cc: Int,
    coverage: Double?
) -> MethodMetric {
    let crap = CrapScore.score(cc: cc, coverage: coverage)
    return MethodMetric(
        methodName: name, file: file, startLine: line,
        complexity: cc, coverage: coverage, crapScore: crap
    )
}

struct ReportTests {
    @Test func tableShape() {
        let metrics = [
            metric(name: "risky", file: "src/b.swift", line: 2, cc: 5, coverage: 0.0),
            metric(name: "fine", file: "src/a.swift", line: 1, cc: 2, coverage: 1.0),
        ]
        let report = Report.format(metrics, threshold: 8.0)
        #expect(report.hasPrefix("CRAP Report\n===========\n"))
        #expect(report.contains("Method"))
        #expect(report.contains("Max CRAP: 30.0 (threshold 8.0) — FAILED"))
        // Sorted by CRAP descending.
        let riskyIndex = report.range(of: "risky")!
        let fineIndex = report.range(of: "fine")!
        #expect(riskyIndex.lowerBound < fineIndex.lowerBound)
        #expect(report.contains("src/b.swift"))
    }

    @Test func passedVerdict() {
        let report = Report.format([metric(name: "f", cc: 2, coverage: 1.0)], threshold: 8.0)
        #expect(report.contains("Max CRAP: 2.0 (threshold 8.0) — passed"))
    }

    @Test func naRowsLastAndExcludedFromMax() {
        let metrics = [
            metric(name: "unknown", cc: 9, coverage: nil),
            metric(name: "known", cc: 5, coverage: 0.0),
        ]
        let report = Report.format(metrics, threshold: 8.0)
        // N/A is excluded from the maximum, so 30.0 passes while 90.0 would not.
        #expect(report.contains("Max CRAP: 30.0 (threshold 8.0) — FAILED"))
        let unknownIndex = report.range(of: "unknown")!
        let knownIndex = report.range(of: "known")!
        #expect(unknownIndex.lowerBound > knownIndex.lowerBound)
        #expect(report.contains("N/A"))
    }

    @Test func allNaReportPasses() {
        let report = Report.format([metric(name: "f", cc: 9, coverage: nil)], threshold: 8.0)
        #expect(report.contains("Max CRAP: 0.0 (threshold 8.0) — passed"))
    }

    @Test func parseFailureLine() {
        let report = Report.format([], threshold: 8.0, parseFailures: ["a.swift"])
        #expect(report.contains("Parse failures: 1 file(s) — see warnings above."))
        let clean = Report.format([], threshold: 8.0)
        #expect(!clean.contains("Parse failures"))
    }

    @Test func emptyReportPasses() {
        let report = Report.format([], threshold: 8.0)
        #expect(report.contains("Max CRAP: 0.0 (threshold 8.0) — passed"))
    }

    @Test func paddingHelpers() {
        #expect(Report.padLeft("x", 3) == "  x")
        #expect(Report.padRight("x", 3) == "x  ")
        #expect(Report.padLeft("xxxx", 3) == "xxxx")
        #expect(Report.formatCoverage(0.5) == "50.0%")
        #expect(Report.formatCoverage(nil) == "N/A")
        #expect(Report.formatCrap(1.25) == "1.3")
    }

    @Test func sortingTiesBreakByFileThenLine() {
        let sorted = Analyzer.sortedForReport([
            metric(name: "b", file: "z.swift", line: 5, cc: 1, coverage: 1.0),
            metric(name: "a", file: "a.swift", line: 9, cc: 1, coverage: 1.0),
            metric(name: "c", file: "a.swift", line: 2, cc: 1, coverage: 1.0),
            metric(name: "na", file: "a.swift", line: 1, cc: 1, coverage: nil),
        ])
        #expect(sorted.map { $0.methodName } == ["c", "a", "b", "na"])
    }
}

struct AnalyzerTests {
    private func writeSource(_ source: String) -> String {
        let path = NSTemporaryDirectory() + "crap4swift-src-\(UUID().uuidString).swift"
        try? source.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test func analyzesCoverageAndCrap() {
        let source = """
        func covered() { return 1 }
        func uncovered() { if true { } }
        """
        let file = writeSource(source)
        let lineOf = { (marker: String) -> Int in
            source.split(separator: "\n").firstIndex { $0.contains(marker) }! + 1
        }
        let lcov = """
        SF:\(file)
        DA:\(lineOf("covered")),2
        DA:\(lineOf("if true")),0
        end_of_record
        """
        let coveragePath = writeSource(lcov)
        let records = try! Analyzer.loadCoverage(path: coveragePath, projectRoot: "/tmp")
        let (metrics, failures) = Analyzer.analyze(
            sourceFiles: [file],
            coverageRecords: Analyzer.relativized(records, projectRoot: FileManager.default.currentDirectoryPath),
            strict: false,
            diffLines: nil
        )
        #expect(failures.isEmpty)
        #expect(metrics.count == 2)
        let covered = metrics.first { $0.methodName == "covered()" }!
        let uncovered = metrics.first { $0.methodName == "uncovered()" }!
        #expect(covered.complexity == 1)
        #expect(covered.coverage == 1.0)
        #expect(uncovered.complexity == 2)
        #expect(uncovered.coverage == 0.0)
        #expect(uncovered.crapScore == 6.0)
        try? FileManager.default.removeItem(atPath: file)
        try? FileManager.default.removeItem(atPath: coveragePath)
    }

    @Test func strictTreatsMissingEntryAsUncovered() {
        let file = writeSource("func f() { return 1 }")
        let records: [String: LcovRecord] = [:]
        let relaxed = Analyzer.analyze(sourceFiles: [file], coverageRecords: records, strict: false, diffLines: nil)
        let strict = Analyzer.analyze(sourceFiles: [file], coverageRecords: records, strict: true, diffLines: nil)
        #expect(relaxed.metrics[0].coverage == nil)
        #expect(strict.metrics[0].coverage == 0.0)
        #expect(strict.metrics[0].crapScore == 2.0)
        try? FileManager.default.removeItem(atPath: file)
    }

    @Test func diffSelectionRestrictsToChangedFunctions() {
        let source = """
        func untouched() { return 1 }
        func touched() { return 2 }
        """
        let file = writeSource(source)
        let touchedLine = source.split(separator: "\n").firstIndex { $0.hasPrefix("func touched") }! + 1
        let selected = Analyzer.analyze(
            sourceFiles: [file],
            coverageRecords: [:],
            strict: false,
            diffLines: [Analyzer.relativePath(file): [touchedLine]]
        )
        #expect(selected.metrics.map { $0.methodName } == ["touched()"])
        // A file with no changed lines contributes nothing.
        let none = Analyzer.analyze(
            sourceFiles: [file],
            coverageRecords: [:],
            strict: false,
            diffLines: ["other.swift": [1]]
        )
        #expect(none.metrics.isEmpty)
        try? FileManager.default.removeItem(atPath: file)
    }

    @Test func parseFailureIsReported() {
        let missing = NSTemporaryDirectory() + "crap4swift-missing-\(UUID().uuidString).swift"
        let (metrics, failures) = Analyzer.analyze(sourceFiles: [missing], coverageRecords: [:], strict: false, diffLines: nil)
        #expect(metrics.isEmpty)
        #expect(failures.count == 1)
    }
}

struct SourceFileTests {
    @Test func expandFindsSwiftFilesRecursively() {
        let root = NSTemporaryDirectory() + "crap4swift-expand-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: root + "/Sources/Sub", withIntermediateDirectories: true)
        try? Data("func a() {}".utf8).write(to: URL(fileURLWithPath: root + "/Sources/A.swift"))
        try? Data("struct B {}".utf8).write(to: URL(fileURLWithPath: root + "/Sources/Sub/B.swift"))
        try? Data("let x = 1".utf8).write(to: URL(fileURLWithPath: root + "/Sources/notes.txt"))
        let files = SourceFiles.expand([root + "/Sources"])
        #expect(files.count == 2)
        #expect(files.contains { $0.hasSuffix("A.swift") })
        #expect(files.contains { $0.hasSuffix("B.swift") })
        try? FileManager.default.removeItem(atPath: root)
    }

    @Test func expandSkipsMissingPaths() {
        #expect(SourceFiles.expand(["/nonexistent/\(UUID().uuidString)"]).isEmpty)
    }

    @Test func changedPathParsesPorcelainLines() {
        #expect(SourceFiles.changedPath(fromLine: " M Sources/A.swift") == "Sources/A.swift")
        #expect(SourceFiles.changedPath(fromLine: "?? Sources/New.swift") == "Sources/New.swift")
        #expect(SourceFiles.changedPath(fromLine: "R  old.swift -> new.swift") == "new.swift")
        #expect(SourceFiles.changedPath(fromLine: "D  Sources/Gone.swift") == nil)
        #expect(SourceFiles.changedPath(fromLine: "  ") == nil)
    }

    @Test func diffParserReadsHunks() {
        let raw = """
        diff --git a/Sources/A.swift b/Sources/A.swift
        +++ b/Sources/A.swift
        @@ -10,3 +10,5 @@
        line
        diff --git a/Sources/B.swift b/Sources/B.swift
        +++ /dev/null
        @@ -1,1 +0,0 @@
        gone
        diff --git a/Sources/C.swift b/Sources/C.swift
        +++ b/Sources/C.swift
        @@ -4 +4,2 @@
        changed
        """
        let lines = DiffLines.parse(raw)
        #expect(lines["Sources/A.swift"] == [10, 11, 12, 13, 14])
        #expect(lines["Sources/B.swift"] == nil)
        #expect(lines["Sources/C.swift"] == [4, 5])
    }

    @Test func globMatching() {
        #expect(Glob.matches(pattern: "src/*.swift", path: "src/a.swift"))
        #expect(!Glob.matches(pattern: "src/*.swift", path: "src/sub/a.swift"))
        #expect(Glob.matches(pattern: "src/**", path: "src/sub/a.swift"))
        #expect(Glob.matches(pattern: "src/**", path: "src/a.swift"))
        #expect(Glob.matches(pattern: "src/?idget.swift", path: "src/widget.swift"))
        #expect(!Glob.matches(pattern: "src/?idget.swift", path: "src/wiidget.swift"))
        #expect(!Glob.matches(pattern: "src/**", path: "lib/a.swift"))
        #expect(Glob.anyMatches(patterns: ["nope", "src/**"], path: "src/a.swift"))
    }
}
