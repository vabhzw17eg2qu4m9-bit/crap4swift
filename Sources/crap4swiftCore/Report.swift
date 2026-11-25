// Tabular CRAP report formatter (identical to the crap4 family).
//
// Output shape:
//   CRAP Report
//   ===========
//   <header line of dashes>
//   <one row per method>
//   <blank line>
//   Max CRAP: <max> (threshold <t>) — FAILED|passed
//
// Sorting: numeric CRAP descending; nil (N/A) entries last; ties broken by
// (file asc, startLine asc). An all-N/A report yields max 0.0 and a
// "passed" verdict.

public enum Report {
    static let widthMethod = 30
    static let widthFile = 35
    static let widthCC = 4
    static let widthCov = 7
    static let widthCrap = 8

    /// Format the metrics array as a CRAP report string.
    public static func format(
        _ metrics: [MethodMetric],
        threshold: Double,
        parseFailures: [String] = []
    ) -> String {
        let sorted = Analyzer.sortedForReport(metrics)
        let header = padRight("Method", widthMethod)
            + " " + padRight("File", widthFile)
            + " " + padLeft("CC", widthCC)
            + " " + padLeft("Cov%", widthCov)
            + " " + padLeft("CRAP", widthCrap)
        var out = "CRAP Report\n===========\n"
        out += header + "\n"
        out += String(repeating: "-", count: header.count) + "\n"
        for metric in sorted {
            out += row(metric) + "\n"
        }
        out += "\n"
        out += summaryLine(maxCrap(in: sorted), threshold: threshold)
        out += parseFailureLine(parseFailures)
        return out
    }

    /// Max numeric CRAP; N/A entries are excluded (counted as 0).
    public static func maxCrap(in metrics: [MethodMetric]) -> Double {
        var max = 0.0
        for metric in metrics {
            if let score = metric.crapScore, score > max { max = score }
        }
        return max
    }

    /// Exit code 2 when max CRAP is strictly above the threshold.
    public static func exceedsThreshold(max: Double, threshold: Double) -> Bool {
        max > threshold
    }

    static func row(_ metric: MethodMetric) -> String {
        padRight(metric.methodName, widthMethod)
            + " " + padRight(metric.file, widthFile)
            + " " + padLeft(String(metric.complexity), widthCC)
            + " " + padLeft(formatCoverage(metric.coverage), widthCov)
            + " " + padLeft(formatCrap(metric.crapScore), widthCrap)
    }

    static func summaryLine(_ max: Double, threshold: Double) -> String {
        let verdict = exceedsThreshold(max: max, threshold: threshold) ? "FAILED" : "passed"
        return "Max CRAP: \(formatCrap(max)) (threshold \(formatCrap(threshold))) — \(verdict)\n"
    }

    static func parseFailureLine(_ parseFailures: [String]) -> String {
        guard !parseFailures.isEmpty else { return "" }
        return "Parse failures: \(parseFailures.count) file(s) — see warnings above.\n"
    }

    /// One decimal, rounded half away from zero (toFixed parity with the
    /// crap4 family).
    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", (value * 10).rounded() / 10)
    }

    static func formatCoverage(_ coverage: Double?) -> String {
        guard let coverage = coverage else { return "N/A" }
        return oneDecimal(coverage * 100) + "%"
    }

    static func formatCrap(_ score: Double?) -> String {
        guard let score = score else { return "N/A" }
        return oneDecimal(score)
    }

    static func padLeft(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
    }

    static func padRight(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
