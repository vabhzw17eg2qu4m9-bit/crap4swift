// crap4swift CLI: argument parsing, exit-code plumbing.
//
//   crap4swift [<path>...] [--changed] [--coverage <path>] [--threshold <num>]
//              [--exclude <glob>]... [--strict] [--diff-base <ref>] [--help]
//
// Exit codes: 0 pass; 1 usage error or missing/empty coverage; 2 max CRAP
// above the threshold.

import Foundation

public struct Options {
    public var paths: [String] = []
    public var changed = false
    public var coverage = Cli.defaultCoverage
    public var threshold = Cli.defaultThreshold
    public var excludes: [String] = []
    public var strict = false
    public var diffBase: String?
}

public enum Cli {
    public static let exitPass: Int32 = 0
    public static let exitUsage: Int32 = 1
    public static let exitThreshold: Int32 = 2

    public static let defaultThreshold = 8.0
    public static let defaultCoverage = "coverage/lcov.info"
    public static let defaultPaths = ["Sources/"]

    /// Run the CLI; `out`/`err` are injectable for tests.
    @discardableResult
    public static func main(
        _ argv: [String],
        out: @escaping (String) -> Void = writeStdout,
        err: @escaping (String) -> Void = writeStderr
    ) -> Int32 {
        switch parse(argv) {
        case .help:
            out(usage)
            return exitPass
        case .failure(let message):
            err("crap4swift: \(message)\nRun `crap4swift --help` for usage.\n")
            return exitUsage
        case .ok(let options):
            return run(options, out: out, err: err)
        }
    }

    // MARK: - Argument parsing

    enum ParseOutcome {
        case ok(Options)
        case help
        case failure(String)
    }

    enum ConsumeResult {
        case advance(Int)
        case bad(String)

        var accepted: Bool {
            if case .advance = self { return true }
            return false
        }
    }

    static let valueFlags: Set<String> = ["--coverage", "--threshold", "--diff-base", "--exclude"]
    static let booleanFlags: Set<String> = ["--changed", "--strict", "--help"]

    static func parse(_ argv: [String]) -> ParseOutcome {
        if argv.contains("--help") { return .help }
        var options = Options()
        var index = 0
        while index < argv.count {
            switch consume(argv, at: index, into: &options) {
            case .advance(let step):
                index += step
            case .bad(let message):
                return .failure(message)
            }
        }
        if let problem = validate(options) { return .failure(problem) }
        return .ok(options)
    }

    /// Consume one argument; returns the consumed count or a usage error.
    static func consume(_ argv: [String], at index: Int, into options: inout Options) -> ConsumeResult {
        let arg = argv[index]
        guard arg.hasPrefix("--") else {
            options.paths.append(arg)
            return .advance(1)
        }
        let name = flagName(arg)
        guard valueFlags.contains(name) || booleanFlags.contains(name) else {
            return .bad("unknown flag: \(name)")
        }
        if let boolean = applyBoolean(name, into: &options) { return boolean }
        guard let value = flagValue(name: name, arg: arg, argv: argv, index: index) else {
            return .bad("missing value for \(name)")
        }
        let applied = applyValue(name, value, into: &options)
        // An inline `--flag=value` consumes one argument, a separate
        // `--flag value` consumes two.
        if arg.contains("=") && applied.accepted { return .advance(1) }
        return applied
    }

    /// Boolean flags; `nil` when the flag takes a value.
    static func applyBoolean(
        _ name: String,
        into options: inout Options
    ) -> ConsumeResult? {
        if name == "--changed" { options.changed = true; return .advance(1) }
        if name == "--strict" { options.strict = true; return .advance(1) }
        return nil
    }

    /// `--flag value` / `--flag=value` -> flag name.
    static func flagName(_ arg: String) -> String {
        let equal = arg.firstIndex(of: "=") ?? arg.endIndex
        return String(arg[arg.startIndex..<equal])
    }

    static func flagValue(name: String, arg: String, argv: [String], index: Int) -> String? {
        if let equal = arg.firstIndex(of: "=") {
            return String(arg[arg.index(after: equal)...])
        }
        guard index + 1 < argv.count else { return nil }
        return argv[index + 1]
    }

    static func applyValue(
        _ name: String,
        _ value: String,
        into options: inout Options
    ) -> ConsumeResult {
        switch name {
        case "--coverage":
            options.coverage = value
        case "--exclude":
            options.excludes.append(value)
        case "--diff-base":
            options.diffBase = value
        case "--threshold":
            guard let threshold = Double(value) else {
                return .bad("invalid threshold: \(value)")
            }
            options.threshold = threshold
        default:
            break
        }
        return .advance(2)
    }

    /// Flag combination rules (crap4 family parity).
    static func validate(_ options: Options) -> String? {
        if options.changed && !options.paths.isEmpty {
            return "--changed is mutually exclusive with explicit paths"
        }
        if options.diffBase != nil && options.changed {
            return "--diff-base is mutually exclusive with --changed"
        }
        return nil
    }

    // MARK: - Run

    static func run(
        _ options: Options,
        out: (String) -> Void,
        err: (String) -> Void
    ) -> Int32 {
        let root = FileManager.default.currentDirectoryPath
        guard let files = selectedFiles(options, root: root, err: err) else { return exitUsage }
        var failures: [String] = []
        var diffLines: [String: Set<Int>]?
        if let diffBase = options.diffBase {
            guard let lines = try? DiffLines.gitLines(ref: diffBase, paths: files, cwd: root) else {
                err("crap4swift: git diff \(diffBase) failed (not a repository or unknown ref).\n")
                return exitUsage
            }
            diffLines = lines
        }
        let records: [String: LcovRecord]
        do {
            records = try Analyzer.loadCoverage(path: options.coverage, projectRoot: root)
        } catch let error as CoverageError {
            err(coverageFailure(error.message))
            return exitUsage
        } catch {
            err(coverageFailure("\(error)"))
            return exitUsage
        }
        let (metrics, parseFailures) = Analyzer.analyze(
            sourceFiles: files,
            coverageRecords: records,
            strict: options.strict,
            diffLines: diffLines
        )
        failures.append(contentsOf: parseFailures)
        out(Report.format(metrics, threshold: options.threshold, parseFailures: failures))
        return verdict(metrics, threshold: options.threshold)
    }

    /// Files for the run; `nil` after writing a failure message (exit 1).
    static func selectedFiles(
        _ options: Options,
        root: String,
        err: (String) -> Void
    ) -> [String]? {
        let paths = options.paths.isEmpty ? defaultPaths : options.paths
        if options.strict, let missing = firstMissingPath(paths) {
            err("crap4swift: path does not exist: \(missing)\n")
            return nil
        }
        let files: [String]
        if options.changed {
            guard let changed = try? SourceFiles.changed(cwd: root) else {
                err("crap4swift: git status failed (not a repository).\n")
                return nil
            }
            files = changed
        } else {
            files = SourceFiles.expand(paths)
        }
        return files.filter { !Glob.anyMatches(patterns: options.excludes, path: relative($0, root: root)) }
    }

    static func firstMissingPath(_ paths: [String]) -> String? {
        paths.first { !FileManager.default.fileExists(atPath: $0) }
    }

    static func relative(_ path: String, root: String) -> String {
        path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }

    static func verdict(_ metrics: [MethodMetric], threshold: Double) -> Int32 {
        Report.exceedsThreshold(max: Report.maxCrap(in: metrics), threshold: threshold)
            ? exitThreshold
            : exitPass
    }

    static func coverageFailure(_ message: String) -> String {
        "crap4swift: \(message). Unit-test coverage is required — generate it with "
            + "`swift test --enable-code-coverage` and the lcov conversion of README.md.\n"
    }

    public static func writeStdout(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    public static func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    // MARK: - Usage

    public static let usage = """
        crap4swift — CRAP metric for Swift (cyclomatic complexity x coverage)

        Usage:
          crap4swift [<path>...]            Analyze all .swift files under the paths (default: Sources/).
          crap4swift --changed              Analyze git-changed source files (mutually exclusive with paths).
          crap4swift --coverage <path>      LCOV tracefile (default: coverage/lcov.info); a missing or
                                            record-free coverage file fails the run — unit-test
                                            coverage is required.
          crap4swift --threshold <num>      Override the CRAP threshold (default: 8.0).
          crap4swift --exclude <glob>       Skip files whose project-relative path matches the glob
                                            (repeatable; `*` stays in one path segment, `**` crosses them).
          crap4swift --strict               Files with no coverage entry count as 0.0% covered (not N/A);
                                            explicit paths must exist.
          crap4swift --diff-base <ref>      Analyze only functions whose line range intersects lines
                                            changed vs git ref (mutually exclusive with --changed).
          crap4swift --help                 Print this help and exit 0.

        Exit codes: 0 pass; 1 usage error or missing/empty coverage; 2 max CRAP above threshold.

        CRAP = CC^2 * (1 - coverage)^3 + CC
        """
}
