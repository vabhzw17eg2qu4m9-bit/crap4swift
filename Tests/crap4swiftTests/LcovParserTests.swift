// LCOV parsing and per-method attribution.

import Testing
import Foundation
@testable import crap4swiftCore

struct LcovParserTests {
    @Test func parsesDataLines() {
        let text = """
        SF:Sources/Foo.swift
        DA:1,5
        DA:3,0
        end_of_record
        """
        let records = LcovParser.parse(text)
        #expect(records["Sources/Foo.swift"]?.lines == [1: 5, 3: 0])
    }

    @Test func parsesFunctionRecords() {
        let text = """
        SF:Sources/Foo.swift
        FN:2,6,covered()
        FNDA:3,covered()
        FN:10,12,missed()
        FNDA:0,missed()
        end_of_record
        """
        let record = LcovParser.parse(text)["Sources/Foo.swift"]
        #expect(record?.fnStart == ["covered()": 2, "missed()": 10])
        #expect(record?.fnHits == ["covered()": 3, "missed()": 0])
    }

    @Test func repeatedRecordSumsHitsPerLine() {
        let text = """
        SF:Sources/Foo.swift
        DA:1,5
        end_of_record
        SF:Sources/Foo.swift
        DA:1,2
        DA:4,1
        end_of_record
        """
        let record = LcovParser.parse(text)["Sources/Foo.swift"]
        #expect(record?.lines == [1: 7, 4: 1])
    }

    @Test func ignoresUnknownRecords() {
        let text = """
        SF:Sources/Foo.swift
        BRDA:1,0,0,5
        LF:2
        LH:1
        end_of_record
        """
        let record = LcovParser.parse(text)["Sources/Foo.swift"]
        #expect(record?.lines.isEmpty == true)
    }

    @Test func carriageReturnsAreStripped() {
        let records = LcovParser.parse("SF:Sources/Foo.swift\r\nDA:1,1\r\nend_of_record\r\n")
        #expect(records["Sources/Foo.swift"]?.lines == [1: 1])
    }

    @Test func emptyInputHasNoRecords() {
        #expect(LcovParser.parse("").isEmpty)
    }

    @Test func coverageFromDaLinesInRange() {
        let record = LcovParser.parse("SF:F.swift\nDA:1,1\nDA:2,0\nDA:9,1\nend_of_record")["F.swift"]
        #expect(coverageForMethod(record: record, startLine: 1, endLine: 2) == 0.5)
        // DA outside the range does not count.
        #expect(coverageForMethod(record: record, startLine: 9, endLine: 9) == 1.0)
    }

    @Test func coverageFallsBackToFunctionRecords() {
        let record = LcovParser.parse(
            "SF:F.swift\nFN:1,1,covered()\nFNDA:2,covered()\nFN:5,5,missed()\nFNDA:0,missed()\nend_of_record"
        )["F.swift"]
        #expect(coverageForMethod(record: record, startLine: 1, endLine: 1) == 1.0)
        #expect(coverageForMethod(record: record, startLine: 5, endLine: 5) == 0.0)
    }

    @Test func coverageWithoutRecordIsNil() {
        #expect(coverageForMethod(record: nil, startLine: 1, endLine: 2) == nil)
        let record = LcovParser.parse("SF:F.swift\nDA:9,0\nend_of_record")["F.swift"]
        // Lines exist but none in range, and no FN at the start line.
        #expect(coverageForMethod(record: record, startLine: 1, endLine: 2) == nil)
    }

    @Test func mergeSumsAndKeepsFunctionRecords() {
        var base = LcovRecord(path: "F.swift")
        base.lines = [1: 1]
        let other = LcovParser.parse("SF:F.swift\nDA:1,4\nDA:2,0\nFN:3,4,f()\nFNDA:1,f()\nend_of_record")["F.swift"]!
        base.merge(other)
        #expect(base.lines == [1: 5, 2: 0])
        #expect(base.fnStart == ["f()": 3])
        #expect(base.fnHits == ["f()": 1])
    }

    @Test func fieldValuesSplitOnCommas() {
        #expect(LcovParser.fieldValues(afterPrefix: "DA:", in: "DA:1,2") == ["1", "2"])
    }
}

private func writeFixture(_ text: String) -> String {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("crap4swift-lcov-\(UUID().uuidString).info")
    try? text.data(using: .utf8)!.write(to: url)
    return url.path
}

struct CoverageLoadingTests {
    @Test func missingCoverageThrows() {
        #expect(throws: CoverageError.self) {
            _ = try Analyzer.loadCoverage(path: "/nonexistent/crap4swift/coverage.info", projectRoot: "/tmp")
        }
    }

    @Test func recordFreeCoverageThrows() {
        let path = writeFixture("")
        #expect(throws: CoverageError.self) {
            _ = try Analyzer.loadCoverage(path: path, projectRoot: "/tmp")
        }
    }

    @Test func absolutePathsAreRelativized() {
        let root = NSTemporaryDirectory() + "crap4swift-root-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: root + "/Sources", withIntermediateDirectories: true)
        let path = writeFixture("SF:\(root)/Sources/Foo.swift\nDA:1,1\nend_of_record")
        let records = try! Analyzer.loadCoverage(path: path, projectRoot: root)
        #expect(records["Sources/Foo.swift"] != nil)
        #expect(records["Sources/Foo.swift"]?.lines == [1: 1])
        try? FileManager.default.removeItem(atPath: root)
    }

    @Test func pathsOutsideRootKeepWrittenForm() {
        let path = writeFixture("SF:/Elsewhere/Foo.swift\nDA:1,1\nend_of_record")
        let records = try! Analyzer.loadCoverage(path: path, projectRoot: "/tmp")
        #expect(records["/Elsewhere/Foo.swift"] != nil)
    }

    @Test func stripRootHelpers() {
        #expect(Analyzer.stripRoot("/a/b/Sources/F.swift", projectRoot: "/a/b") == "Sources/F.swift")
        #expect(Analyzer.stripRoot("Sources/F.swift", projectRoot: "/a/b") == "Sources/F.swift")
        #expect(Analyzer.stripRoot("/elsewhere/F.swift", projectRoot: "/a/b") == "/elsewhere/F.swift")
        #expect(Analyzer.stripRoot("/a/b/F.swift", projectRoot: "/a/b/") == "F.swift")
    }
}
