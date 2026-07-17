import Foundation

/// Focused RFC 4180-style decoder for rival CSV files.
enum ReplayRivalCSVParser {
    static func parse(data: Data, sampleLimit: Int) throws -> [RawRivalSample] {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ReplayRivalFileParserError.unreadable
        }
        try checkReplayImportCancellation()
        return try parse(text, sampleLimit: sampleLimit)
    }

    private static func parse(_ text: String, sampleLimit: Int) throws -> [RawRivalSample] {
        try checkReplayImportCancellation()
        var didReadHeader = false
        var ti = -1
        var di = -1
        var pi = -1
        var hi = -1
        var si = -1
        var wi = -1
        var out: [RawRivalSample] = []
        out.reserveCapacity(min(sampleLimit, 4_096))

        try forEachRow(in: text) { columns in
            try checkReplayImportCancellation()
            if !didReadHeader {
                let header = columns.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                // Prefer exact/token matches so "timestamp" does not steal
                // elapsed time and "parameter" does not steal distance.
                ti = findHeader(
                    header,
                    names: ["elapsed", "elapsedtime", "seconds", "timer", "time"],
                    rejectedTokens: ["stamp", "date", "day", "zone", "clock", "local", "utc"]
                )
                di = findHeader(
                    header,
                    names: [
                        "distance", "distancemeters", "distancemetres", "dist",
                        "meters", "metres", "meter", "metre",
                    ],
                    rejectedTokens: ["parameter", "diameter"]
                )
                pi = findHeader(header, names: ["avgpace", "averagepace", "pace"])
                hi = findHeader(header, names: ["heart_rate", "heartrate", "hr", "bpm", "heart"])
                si = findHeader(
                    header,
                    names: ["stroke_rate", "strokerate", "stroke rate", "spm", "cadence"]
                )
                if si < 0,
                   let rateIndex = header.enumerated().first(where: { entry in
                       entry.offset != hi
                           && headerTokens(entry.element).contains("rate")
                           && !headerTokens(entry.element).contains("heart")
                   })?.offset {
                    si = rateIndex
                }
                wi = findHeader(header, names: ["powerwatts", "averagepower", "watts", "watt", "power"])
                didReadHeader = true
                return
            }

            guard ti >= 0, di >= 0 else { return }
            let t = parseClock(column(columns, ti))
            let d = numberOrNaN(column(columns, di))
            guard t.isFinite, d.isFinite else { return }
            let pace = pi >= 0 ? parseClock(column(columns, pi)) : .nan
            out.append(RawRivalSample(
                t: t,
                d: d,
                pace: pace.isFinite && pace > 0 ? pace : nil,
                spm: si >= 0 ? optionalNumber(column(columns, si)) : nil,
                hr: hi >= 0 ? optionalInt(column(columns, hi)) : nil,
                watts: wi >= 0 ? optionalNumber(column(columns, wi)) : nil
            ))
            if out.count > sampleLimit {
                throw ReplayRivalFileParserError.tooManySamples
            }
        }
        return out
    }

    /// Preserves quoted commas/newlines, unescapes doubled quotes, rejects
    /// unbalanced quotes, and emits one row at a time.
    private static func forEachRow(
        in text: String,
        _ body: ([String]) throws -> Void
    ) throws {
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var didCloseQuote = false
        let scalars = text.unicodeScalars
        var index = scalars.startIndex
        var scannedScalars = 0

        func finishField() {
            row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
            field.removeAll(keepingCapacity: true)
            didCloseQuote = false
        }

        func finishRow() throws {
            finishField()
            if row.count > 1 || row.contains(where: { !$0.isEmpty }) {
                try body(row)
            }
            row.removeAll(keepingCapacity: true)
        }

        while index < scalars.endIndex {
            if scannedScalars.isMultiple(of: 4_096) {
                try checkReplayImportCancellation()
            }
            scannedScalars &+= 1
            let scalar = scalars[index]
            if isQuoted {
                if scalar == "\"" {
                    let next = scalars.index(after: index)
                    if next < scalars.endIndex, scalars[next] == "\"" {
                        field.append("\"")
                        index = scalars.index(after: next)
                        continue
                    }
                    isQuoted = false
                    didCloseQuote = true
                } else {
                    field.unicodeScalars.append(scalar)
                }
            } else if scalar == "\"" {
                guard !didCloseQuote,
                      field.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw ReplayRivalFileParserError.malformed
                }
                field.removeAll(keepingCapacity: true)
                isQuoted = true
            } else if scalar == "," {
                finishField()
            } else if Character(scalar).isNewline {
                try finishRow()
            } else if didCloseQuote {
                guard Character(scalar).isWhitespace else {
                    throw ReplayRivalFileParserError.malformed
                }
            } else {
                field.unicodeScalars.append(scalar)
            }
            index = scalars.index(after: index)
        }

        guard !isQuoted else {
            throw ReplayRivalFileParserError.malformed
        }
        if !row.isEmpty || !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || didCloseQuote {
            try finishRow()
        }
    }

    /// Numeric seconds, or M:SS / H:MM:SS clock string.
    private static func parseClock(_ value: String?) -> Double {
        guard let value else { return .nan }
        let text = value.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .nan }
        if text.contains(":") {
            let rawParts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(rawParts.count) else { return .nan }

            let parts = rawParts.compactMap { part -> Double? in
                let component = part.trimmingCharacters(in: .whitespaces)
                guard !component.isEmpty,
                      let value = Double(component),
                      value.isFinite,
                      value >= 0 else {
                    return nil
                }
                return value
            }
            guard parts.count == rawParts.count,
                  parts.dropLast().allSatisfy({ $0.rounded(.towardZero) == $0 }),
                  let seconds = parts.last,
                  seconds < 60 else {
                return .nan
            }
            if parts.count == 3, parts[1] >= 60 {
                return .nan
            }

            let total = parts.reduce(0) { $0 * 60 + $1 }
            return total.isFinite ? total : .nan
        }
        return Double(normalizedNumberString(text)) ?? .nan
    }

    private static func column(_ columns: [String], _ index: Int) -> String? {
        guard index >= 0, index < columns.count else { return nil }
        return columns[index]
    }

    private static func numberOrNaN(_ value: String?) -> Double {
        guard let value,
              let number = Double(normalizedNumberString(value)),
              number.isFinite else {
            return .nan
        }
        return number
    }

    private static func optionalNumber(_ value: String?) -> Double? {
        guard let value,
              let number = Double(normalizedNumberString(value)),
              number.isFinite else {
            return nil
        }
        return number
    }

    private static func optionalInt(_ value: String?) -> Int? {
        guard let number = optionalNumber(value) else { return nil }
        return checkedPositiveRoundedInt(number)
    }

    private static func normalizedNumberString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return trimmed }

        let hasDot = trimmed.contains(".")
        let hasComma = trimmed.contains(",")
        if hasDot && hasComma,
           let lastDot = trimmed.lastIndex(of: "."),
           let lastComma = trimmed.lastIndex(of: ",") {
            if lastComma > lastDot {
                return trimmed
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            }
            return trimmed.replacingOccurrences(of: ",", with: "")
        }
        if hasComma && !hasDot {
            let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2,
               (1...2).contains(parts[1].count),
               parts[0].allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" }),
               parts[1].allSatisfy(\.isNumber) {
                return "\(parts[0]).\(parts[1])"
            }
            return trimmed.replacingOccurrences(of: ",", with: "")
        }
        return trimmed
    }

    /// Exact match first, then token match. Rejects columns that also carry
    /// disambiguating tokens (for example `timestamp` when looking for `time`).
    private static func findHeader(
        _ header: [String],
        names: [String],
        rejectedTokens: [String] = []
    ) -> Int {
        for name in names {
            if let index = header.firstIndex(of: name) {
                return index
            }
        }
        for name in names {
            if let index = header.firstIndex(where: { column in
                let tokens = headerTokens(column)
                guard tokens.contains(name) || column == name else { return false }
                if rejectedTokens.contains(where: { tokens.contains($0) || column.contains($0) }) {
                    return false
                }
                return true
            }) {
                return index
            }
        }
        for name in names where name.contains(" ") || name.contains("_") {
            let needle = name.replacingOccurrences(of: "_", with: " ")
            if let index = header.firstIndex(where: {
                $0.replacingOccurrences(of: "_", with: " ").contains(needle)
            }) {
                return index
            }
        }
        return -1
    }

    private static func headerTokens(_ column: String) -> [String] {
        column.split { character in
            !character.isLetter && !character.isNumber
        }.map(String.init)
    }
}
