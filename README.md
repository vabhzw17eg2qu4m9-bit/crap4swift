# crap4swift

**CRAP (Change Risk Anti-Patterns) metric for Swift.**

`crap4swift` computes the CRAP score for every method in a Swift project by
combining **cyclomatic complexity** (parsed from source via
[SwiftSyntax](https://github.com/swiftlang/swift-syntax)) with **line
coverage** (parsed from an LCOV tracefile, as produced by
`swift test --enable-code-coverage` + `llvm-cov export -format=lcov`).
It is a port of the crap4 family core (`crap4js`, `crap4dart`). The CLI,
formula, complexity rules, report format, and exit codes are identical
across the ports.

## The CRAP formula

```
CRAP = CC^2 * (1 - coverage)^3 + CC
```

- `CC` — cyclomatic complexity (integer ≥ 1)
- `coverage` — line-coverage fraction in `[0.0, 1.0]`
- When coverage is unknown, CRAP is `nil` (reported as `N/A`).

A function with high complexity **and** low coverage scores badly; the same
function with high coverage scores well. CRAP flags code that is risky to
change because it is both hard to understand and under-tested.

## Install

Use SwiftPM (this package builds an executable and the `crap4swiftCore`
library):

```bash
git clone https://github.com/vabhzw17eg2qu4m9-bit/crap4swift.git
cd crap4swift
swift build -c release
.build/release/crap4swift --help
```

## CLI usage

```
crap4swift [<path>...]    Analyze all .swift files under the paths (default: Sources/).
crap4swift --changed      Analyze git-changed source files (mutually exclusive with paths).
crap4swift --help         Print the usage text and exit 0.
crap4swift --coverage <p> LCOV tracefile (default: coverage/lcov.info).
                          A missing or record-free coverage file fails the run
                          (exit 1): unit-test coverage is required — a CRAP
                          score without coverage is meaningless.
crap4swift --threshold <n>  Override the CRAP threshold (default: 8.0).
crap4swift --exclude GLOB Skip files whose project-relative path matches GLOB
                          (repeatable; `*` stays in one path segment, `**`
                          crosses segments, `?` matches one character).
crap4swift --strict       Files with no coverage entry count as 0.0% covered
                          instead of N/A; explicit paths must exist.
crap4swift --diff-base REF  Analyze only functions whose line range intersects
                          lines changed vs git ref REF (mutually exclusive
                          with --changed).
```

### Example

```bash
swift test --enable-code-coverage
# ... profdata merge + lcov export (see Coverage format) ...
.build/release/crap4swift Sources --coverage coverage/coverage.lcov --threshold 8.0
```

Output:

```
CRAP Report
===========
Method                         File                                   CC    Cov%     CRAP
----------------------------------------------------------------------------------------
risky                          Sources/Widgets/Parser.swift            5    0.0%     30.0
addPositive                    Sources/Widgets/Math.swift              2  100.0%      2.0

Max CRAP: 30.0 (threshold 8.0) — FAILED
```

## Exit codes

| Code | Meaning |
|------|---------|
| `0`  | Success (empty selection, or max numeric CRAP ≤ threshold). |
| `1`  | CLI usage error (unknown flag, bad threshold, `--changed` + paths, `--diff-base` + `--changed`, git failure, missing/unparseable/record-free coverage, or — under `--strict` — a missing explicit path). |
| `2`  | CRAP threshold exceeded (max numeric CRAP > threshold). |

## Coverage format

`crap4swift` reads the **LCOV tracefile** format only. Produce it from a
coverage run:

```bash
swift test --enable-code-coverage
find .build -name "*.profraw" -print0 | xargs -0 xcrun llvm-profdata merge -sparse -o Coverage.profdata
TESTBIN="$(find .build -name "*.xctest" -type d | head -1)"
mkdir -p coverage
xcrun llvm-cov export -format=lcov -instr-profile Coverage.profdata \
  "$TESTBIN/Contents/MacOS/$(basename "$TESTBIN" .xctest)" > coverage/coverage.lcov
```

Record types: `SF:` opens a per-file record, `DA:<line>,<hits>` is one
executable line, `FN:<start>,<end>,<name>` and `FNDA:<hits>,<name>` are
function records, `end_of_record` closes the record. Two `SF:` records for
one file sum their hits per line.

Per-method attribution: the `DA:` lines inside the method's
`[startLine, endLine]` range give `covered / total`. When the record has
`FN:` and `FNDA:` for the method start line and no `DA:` line inside the
range, coverage is `1.0` (hit count > 0) or `0.0` otherwise. With no record
for the file (or no usable lines), coverage and CRAP are `N/A`. `SF:` paths
are relativized against the working directory, so absolute and relative
spellings both match.

## Complexity rules

Base 1; +1 for each:

- `if` statement or `if` expression (`else if` counts as its own `if`)
- `guard`
- `for`
- `while`
- `repeat`
- `catch` clause of a `do` block
- `case` item of a `switch` (`default` included)
- ternary `? :`
- `&&`, `||`, `??` operator

Methods: every `func`, `init` and `subscript` declaration with a body.
Closures count toward the enclosing method; a nested named `func` is its
own entry. Names are `Type.function(parameterLabels)`, `Type.init`,
`Type.subscript`; free functions carry no type prefix.

## Development

```bash
swift build
swift test
swift test --enable-code-coverage   # coverage for the gate below
```

This repository is self-hosting: the `Quality` workflow runs `crap4swift`
on `Sources/` with the coverage of the unit tests at threshold 8.0.
Locally:

```bash
swift test --enable-code-coverage
find .build -name "*.profraw" -print0 | xargs -0 xcrun llvm-profdata merge -sparse -o Coverage.profdata
TESTBIN="$(find .build -name "*.xctest" -type d | head -1)"
mkdir -p coverage
xcrun llvm-cov export -format=lcov -instr-profile Coverage.profdata \
  "$TESTBIN/Contents/MacOS/$(basename "$TESTBIN" .xctest)" > coverage/coverage.lcov
swift build -c release
.build/release/crap4swift Sources --coverage coverage/coverage.lcov --threshold 8.0
```

## License

MIT
