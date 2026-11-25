// CRAP (Change Risk Anti-Patterns) metric formula.
//
//   CRAP = CC^2 * (1 - coverage)^3 + CC
//
// where CC is the cyclomatic complexity (integer >= 1) and `coverage` is a
// fraction in [0, 1]. When coverage is unknown, the score is nil and is
// reported as "N/A".

public enum CrapScore {
    /// Compute the CRAP score for a single method.
    /// - Parameters:
    ///   - cc: cyclomatic complexity (>= 1)
    ///   - coverage: statement-coverage fraction in [0, 1], or nil
    /// - Returns: CRAP score, or nil when coverage is unknown.
    public static func score(cc: Int, coverage: Double?) -> Double? {
        guard let coverage = coverage else { return nil }
        let complexity = Double(cc)
        let uncovered = 1.0 - coverage
        return complexity * complexity * uncovered * uncovered * uncovered + complexity
    }
}
