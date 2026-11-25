# Changelog

## 0.1.0

Initial release: the CRAP core (analyze command, LCOV coverage input,
threshold 8.0).

- CLI: `crap4swift [<path>...] [--changed] [--coverage <path>] [--threshold <num>]
  [--exclude <glob>]... [--strict] [--diff-base <ref>] [--help]`, identical to the
  crap4 family (defaults: paths `Sources/`, coverage `coverage/lcov.info`,
  threshold 8.0).
- Methods: every `func`, `init` and `subscript` declaration with a body;
  closures count toward the enclosing method, nested named funcs are their
  own entries.
- Complexity rules and report/exit-code contract ported from `crap4js` v0.34.0.
- Self-hosting `Quality` workflow (macos-15): tests with coverage, LCOV
  conversion, release build, `crap4swift Sources --threshold 8.0`.

### SwiftSyntax version

The manifest starts at `.upToNextMinor(from: "600.0.1")` as specified.

- Local toolchain Swift 6.4 (`swiftlang-6.4.0.34.1`), swift-syntax
  600.0.1: builds and tests pass. No fallback release needed.
- CI (`macos-15`): swift-syntax 600.0.1 builds with the runner's default
  Xcode toolchain (Swift 6.x); the workflow pins nothing beyond the
  runner default.
