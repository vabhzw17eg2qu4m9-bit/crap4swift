// LCOV tracefile parsing (`SF:`, `FN:`, `FNDA:`, `DA:`, `end_of_record`)
// and per-method coverage attribution.
//
// DA lines inside the method range: covered / total. When the record has
// `FN:` and `FNDA:` for the method start line and no `DA:` line inside the
// range: 1.0 when the hit count is greater than 0, else 0.0. No record: nil
// (an N/A row).

public struct LcovRecord {
    public var path: String
    /// `DA:` line number -> hit count.
    public var lines: [Int: Int] = [:]
    /// `FN:` function name -> start line.
    public var fnStart: [String: Int] = [:]
    /// `FNDA:` function name -> hit count.
    public var fnHits: [String: Int] = [:]

    public init(path: String) {
        self.path = path
    }

    /// Sums hits per line when the same `SF:` path appears twice.
    public mutating func merge(_ other: LcovRecord) {
        for (line, hits) in other.lines {
            lines[line, default: 0] += hits
        }
        for (name, line) in other.fnStart {
            fnStart[name] = line
        }
        for (name, hits) in other.fnHits {
            fnHits[name] = hits
        }
    }
}

public enum LcovParser {
    /// Parse an lcov tracefile into records keyed by the `SF:` path as
    /// written. Unknown records are ignored.
    public static func parse(_ text: String) -> [String: LcovRecord] {
        var records: [String: LcovRecord] = [:]
        var current: LcovRecord?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = trimCarriageReturn(String(rawLine))
            current = traceLine(line, into: current, records: &records)
        }
        return records
    }

    /// One tracefile line: `SF:` commits the open record and opens the next,
    /// `DA:`/`FN:`/`FNDA:` accumulate, `end_of_record` commits. Returns the
    /// record open after this line.
    static func traceLine(
        _ line: String,
        into current: LcovRecord?,
        records: inout [String: LcovRecord]
    ) -> LcovRecord? {
        if line.hasPrefix("SF:") {
            commit(current, into: &records)
            return LcovRecord(path: String(line.dropFirst(3)))
        }
        if line.hasPrefix("end_of_record") {
            commit(current, into: &records)
            return nil
        }
        guard var record = current else { return current }
        if line.hasPrefix("DA:") {
            applyData(line, to: &record)
            return record
        }
        if line.hasPrefix("FNDA:") {
            applyFunctionHit(line, to: &record)
            return record
        }
        if line.hasPrefix("FN:") {
            applyFunctionStart(line, to: &record)
            return record
        }
        return record
    }

    static func commit(_ record: LcovRecord?, into records: inout [String: LcovRecord]) {
        guard let record = record else { return }
        if var existing = records[record.path] {
            existing.merge(record)
            records[record.path] = existing
        } else {
            records[record.path] = record
        }
    }

    /// `DA:<line>,<hits>[,checksum]`.
    static func applyData(_ line: String, to record: inout LcovRecord) {
        let fields = fieldValues(afterPrefix: "DA:", in: line)
        guard fields.count >= 2, let lineNumber = Int(fields[0]), let hits = Int(fields[1]) else {
            return
        }
        record.lines[lineNumber] = hits
    }

    /// `FNDA:<hits>,<name>` — names may contain commas (demangled Swift).
    static func applyFunctionHit(_ line: String, to record: inout LcovRecord) {
        let fields = fieldValues(afterPrefix: "FNDA:", in: line)
        guard fields.count >= 2, let hits = Int(fields[0]) else { return }
        record.fnHits[fields.dropFirst().joined(separator: ",")] = hits
    }

    /// `FN:<startLine>,<endLine>,<name>`.
    static func applyFunctionStart(_ line: String, to record: inout LcovRecord) {
        let fields = fieldValues(afterPrefix: "FN:", in: line)
        guard fields.count >= 3, let start = Int(fields[0]) else { return }
        record.fnStart[fields.dropFirst(2).joined(separator: ",")] = start
    }

    static func fieldValues(afterPrefix prefix: String, in line: String) -> [String] {
        String(line.dropFirst(prefix.count)).split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0) }
    }
}

/// Coverage of a method whose source spans `startLine...endLine`.
public func coverageForMethod(record: LcovRecord?, startLine: Int, endLine: Int) -> Double? {
    guard let record = record else { return nil }
    let daLines = record.lines.keys.filter { $0 >= startLine && $0 <= endLine }
    if !daLines.isEmpty {
        let covered = daLines.filter { record.lines[$0, default: 0] > 0 }.count
        return Double(covered) / Double(daLines.count)
    }
    // No DA inside the range: fall back to FN/FNDA at the method start line.
    let names = record.fnStart.filter { $1 == startLine }.keys
    for name in names {
        if let hits = record.fnHits[name] {
            return hits > 0 ? 1.0 : 0.0
        }
    }
    return nil
}

private func trimCarriageReturn(_ line: String) -> String {
    line.hasSuffix("\r") ? String(line.dropLast()) : line
}
