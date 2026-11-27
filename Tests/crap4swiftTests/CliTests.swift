// CLI exit-code contract, exercised through Process on the built
// `crap4swift` executable: --help exits 0; an unknown flag exits 1; a
// missing or record-free coverage file exits 1; an uncovered method with
// complexity 9 exits 2; a covered selection exits 0.

import Testing
import Foundation
@testable import crap4swiftCore

struct CliTests {
    /// Path of the `crap4swift` executable: `swift test` runs with the
    /// package root as the working directory.
    static let executablePath: String = {
        let cwd = FileManager.default.currentDirectoryPath
        let debug = cwd + "/.build/debug/crap4swift"
        if FileManager.default.isExecutableFile(atPath: debug) { return debug }
        let release = cwd + "/.build/release/crap4swift"
        if FileManager.default.isExecutableFile(atPath: release) { return release }
        return debug
    }()

    private func run(_ arguments: [String], cwd: String? = nil) -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.executablePath)
        process.arguments = arguments
        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            Issue.record("failed to launch \(Self.executablePath): \(error)")
            return (-1, "", "")
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private func makeFixtureDir(
        source: String,
        coverage: String?,
        fileName: String = "Widget.swift"
    ) -> String {
        let dir = NSTemporaryDirectory() + "crap4swift-cli-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir + "/Sources", withIntermediateDirectories: true)
        try? source.data(using: .utf8)!.write(to: URL(fileURLWithPath: dir + "/Sources/" + fileName))
        if let coverage = coverage {
            try? FileManager.default.createDirectory(atPath: dir + "/coverage", withIntermediateDirectories: true)
            try? coverage.data(using: .utf8)!.write(to: URL(fileURLWithPath: dir + "/coverage/lcov.info"))
        }
        return dir
    }

    @Test func helpExitsZero() {
        let (status, stdout, _) = run(["--help"])
        #expect(status == 0)
        #expect(stdout.contains("Usage:"))
        #expect(stdout.contains("CRAP = CC^2 * (1 - coverage)^3 + CC"))
    }

    @Test func unknownFlagExitsOne() {
        let (status, _, stderr) = run(["--nonsense"])
        #expect(status == 1)
        #expect(stderr.contains("unknown flag: --nonsense"))
    }

    @Test func missingValueForFlagExitsOne() {
        let (status, _, stderr) = run(["--threshold"])
        #expect(status == 1)
        #expect(stderr.contains("missing value for --threshold"))
    }

    @Test func invalidThresholdExitsOne() {
        let (status, _, stderr) = run(["--threshold", "fast"])
        #expect(status == 1)
        #expect(stderr.contains("invalid threshold: fast"))
    }

    @Test func changedWithPathExitsOne() {
        let (status, _, stderr) = run(["--changed", "Sources"])
        #expect(status == 1)
        #expect(stderr.contains("mutually exclusive"))
    }

    @Test func diffBaseWithChangedExitsOne() {
        let (status, _, stderr) = run(["--changed", "--diff-base", "main"])
        #expect(status == 1)
        #expect(stderr.contains("mutually exclusive"))
    }

    @Test func missingCoverageFileExitsOne() {
        let dir = makeFixtureDir(source: "func f() { return 1 }", coverage: nil)
        let (status, _, stderr) = run(["--coverage", "coverage/missing.lcov"], cwd: dir)
        #expect(status == 1)
        #expect(stderr.contains("coverage file not found"))
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func recordFreeCoverageFileExitsOne() {
        // An empty tracefile parses to zero records — fail-closed.
        let dir = makeFixtureDir(source: "func f() { return 1 }", coverage: "")
        let (status, _, stderr) = run([], cwd: dir)
        #expect(status == 1)
        #expect(stderr.contains("has no records"))
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func uncoveredComplexityNineExitsTwo() {
        // `risky` has CC 9 (base 1 + 8 ifs) and no coverage -> CRAP 90.0.
        let branches = (1...8).map { "if \($0) > 100 { }" }.joined(separator: "\n")
        let source = "func risky() {\n\(branches)\n}\nfunc safe() { return 1 }"
        // A DA line inside risky()'s range with zero hits: 0.0% coverage.
        let coverage = "SF:Sources/Widget.swift\nDA:2,0\nend_of_record"
        let dir = makeFixtureDir(source: source, coverage: coverage)
        let (status, stdout, _) = run([], cwd: dir)
        #expect(status == 2)
        #expect(stdout.contains("Max CRAP: 90.0 (threshold 8.0) — FAILED"))
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func coveredSelectionExitsZero() {
        let source = "func safe() {\nreturn 1\n}"
        let coverage = "SF:Sources/Widget.swift\nDA:1,1\nDA:2,1\nend_of_record"
        let dir = makeFixtureDir(source: source, coverage: coverage)
        let (status, stdout, _) = run([], cwd: dir)
        #expect(status == 0)
        #expect(stdout.contains("Max CRAP: 1.0 (threshold 8.0) — passed"))
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func thresholdAtBoundaryPasses() {
        // CC 8 fully covered: CRAP 8.0 — not above the threshold.
        let branches = (1...7).map { "if \($0) > 100 { }" }.joined(separator: "\n")
        let source = "func eight() {\n\(branches)\n}"
        let coverage = "SF:Sources/Widget.swift\nDA:1,1\nDA:2,1\nDA:3,1\nend_of_record"
        let dir = makeFixtureDir(source: source, coverage: coverage)
        let (status, stdout, _) = run([], cwd: dir)
        #expect(status == 0)
        #expect(stdout.contains("Max CRAP: 8.0 (threshold 8.0) — passed"))
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func strictFailsOnMissingExplicitPath() {
        let (status, _, stderr) = run(["--strict", "NoSuchDir"], cwd: NSTemporaryDirectory())
        #expect(status == 1)
        #expect(stderr.contains("path does not exist: NoSuchDir"))
    }

    @Test func excludeGlobDropsFiles() {
        let source = "func risky() {\nif true { }\nif false { }\nif true { }\nif false { }\nif true { }\nif false { }\nif true { }\nif false { }\n}"
        let coverage = "SF:Sources/Widget.swift\nDA:9,1\nend_of_record"
        let dir = makeFixtureDir(source: source, coverage: coverage)
        let (status, stdout, _) = run(["--exclude", "Sources/**"], cwd: dir)
        #expect(status == 0)
        #expect(stdout.contains("Max CRAP: 0.0 (threshold 8.0) — passed"))
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func changedSelectsUntrackedFiles() {
        let dir = NSTemporaryDirectory() + "crap4swift-git-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir + "/Sources", withIntermediateDirectories: true)
        try? Data("func risky() {\nif true { }\nif false { }\nif true { }\nif false { }\nif true { }\nif false { }\nif true { }\nif false { }\n}".utf8)
            .write(to: URL(fileURLWithPath: dir + "/Sources/New.swift"))
        let git = { (arguments: [String]) -> Int32 in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        #expect(git(["init", "--quiet"]) == 0)
        let result = run(["--changed", "--coverage", "coverage/none.lcov"], cwd: dir)
        // `--changed` finds the untracked file, then the missing coverage gates.
        #expect(result.0 == 1)
        #expect(result.2.contains("coverage file not found"))
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test func diffBaseRunsGitAndGatesOnCoverage() {
        let dir = NSTemporaryDirectory() + "crap4swift-diff-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir + "/Sources", withIntermediateDirectories: true)
        try? Data("func f() { return 1 }".utf8).write(to: URL(fileURLWithPath: dir + "/Sources/A.swift"))
        let git = { (arguments: [String]) -> Int32 in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        _ = git(["init", "--quiet"])
        _ = git(["-c", "user.name=t", "-c", "user.email=t@t.local", "add", "-A"])
        _ = git(["-c", "user.name=t", "-c", "user.email=t@t.local", "commit", "--quiet", "--allow-empty", "-m", "init"])
        // Unknown ref -> usage error (exit 1).
        let unknown = run(["--diff-base", "does-not-exist"], cwd: dir)
        #expect(unknown.0 == 1)
        #expect(unknown.2.contains("git diff does-not-exist failed"))
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: parser units (direct, no process)

    private func parsed(_ argv: [String]) -> Options? {
        if case .ok(let options) = Cli.parse(argv) { return options }
        return nil
    }

    @Test func parseDefaults() {
        let options = parsed([])!
        #expect(options.paths.isEmpty)
        #expect(options.coverage == Cli.defaultCoverage)
        #expect(options.threshold == Cli.defaultThreshold)
        #expect(!options.changed)
        #expect(!options.strict)
        #expect(options.diffBase == nil)
        #expect(options.excludes.isEmpty)
    }

    @Test func parseExplicitValues() {
        let options = parsed([
            "Lib", "--coverage=other.info", "--threshold", "10",
            "--exclude", "a/**", "--exclude", "b/**", "--strict", "--diff-base", "main",
        ])!
        #expect(options.paths == ["Lib"])
        #expect(options.coverage == "other.info")
        #expect(options.threshold == 10.0)
        #expect(options.excludes == ["a/**", "b/**"])
        #expect(options.strict)
        #expect(options.diffBase == "main")
    }

    @Test func parseFailures() {
        if case .failure = Cli.parse(["--nope"]) {} else { Issue.record("unknown flag must fail") }
        if case .failure = Cli.parse(["--threshold"]) {} else { Issue.record("missing value must fail") }
        if case .failure = Cli.parse(["--threshold", "x"]) {} else { Issue.record("bad threshold must fail") }
        if case .failure = Cli.parse(["--changed", "src"]) {} else { Issue.record("changed+path must fail") }
        if case .failure = Cli.parse(["--changed", "--diff-base", "main"]) {} else { Issue.record("changed+base must fail") }
        if case .help = Cli.parse(["--help"]) {} else { Issue.record("help must match") }
    }
}
