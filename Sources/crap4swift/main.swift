import crap4swiftCore
import Foundation

// crap4swift CLI entry point. Exit codes: 0 pass, 1 usage error or
// missing/empty coverage, 2 max CRAP above threshold.
exit(Cli.main(Array(CommandLine.arguments.dropFirst())))
