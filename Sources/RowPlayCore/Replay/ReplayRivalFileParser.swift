import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Errors from rival file import. Messages never include full paths or contents.
public enum ReplayRivalFileParserError: Error, Equatable, Sendable, LocalizedError {
    case fileTooLarge
    case unreadable
    case unsupportedOrEmpty
    case tooFewSamples
    case tooManySamples
    case malformed

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "Rival file exceeds the 25 MiB size limit."
        case .unreadable:
            return "Could not read the selected rival file."
        case .unsupportedOrEmpty:
            return "No usable samples found in the selected file."
        case .tooFewSamples:
            return "Rival file needs at least two usable samples."
        case .tooManySamples:
            return "Rival file exceeds the maximum sample count."
        case .malformed:
            return "Rival file is malformed or truncated."
        }
    }
}

/// Intermediate sample before pace/watts derivation.
private struct RawRivalSample {
    var t: TimeInterval
    var d: Double
    var pace: TimeInterval?
    var spm: Double?
    var hr: Int?
    var watts: Double?
}

/// Convert an optional positive metric to the nearest `Int` without relying on
/// `Double(Int.max)`, which rounds up to an unrepresentable value on 64-bit
/// platforms.
private func checkedPositiveRoundedInt(_ value: Double) -> Int? {
    guard value.isFinite, value > 0 else { return nil }
    return Int(exactly: value.rounded())
}

@inline(__always)
private func checkReplayImportCancellation() throws {
    try Task<Never, Never>.checkCancellation()
}

/// Stateful XMLParser delegate scoped to one TCX import. The parser and its
/// formatters are never shared across tasks.
private final class ReplayTcxParserDelegate: NSObject, XMLParserDelegate {
    private struct PendingTrackpoint {
        var time: String?
        var distance: Double?
        var cadence: Double?
        var heartRate: Int?
        var watts: Double?
    }

    private let sampleLimit: Int
    private let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let basicFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private var pending: PendingTrackpoint?
    private var currentElement: String?
    private var textBuffer = ""
    private var isInsideHeartRate = false
    private var elementStack: [String] = []
    private var rootElementCount = 0
    private var didReachEndDocument = false

    private(set) var samples: [RawRivalSample] = []
    private(set) var exceededSampleLimit = false
    private(set) var isStructurallyMalformed = false
    private(set) var wasCancelled = false

    var isStructurallyComplete: Bool {
        didReachEndDocument
            && !isStructurallyMalformed
            && rootElementCount == 1
            && elementStack.isEmpty
    }

    init(sampleLimit: Int) {
        self.sampleLimit = sampleLimit
        super.init()
        samples.reserveCapacity(min(sampleLimit, 4_096))
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !abortIfCancelled(parser) else { return }
        let name = Self.localName(qName ?? elementName)
        if elementStack.isEmpty {
            rootElementCount += 1
            if rootElementCount > 1 {
                isStructurallyMalformed = true
                parser.abortParsing()
                return
            }
        }
        elementStack.append(name)
        if name == "trackpoint" {
            pending = PendingTrackpoint()
        }
        guard pending != nil else { return }

        if name == "heartratebpm" {
            isInsideHeartRate = true
        }
        currentElement = name
        textBuffer.removeAll(keepingCapacity: true)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !abortIfCancelled(parser) else { return }
        guard pending != nil, currentElement != nil else { return }
        textBuffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard !abortIfCancelled(parser) else { return }
        let name = Self.localName(qName ?? elementName)
        guard elementStack.last == name else {
            isStructurallyMalformed = true
            parser.abortParsing()
            return
        }
        elementStack.removeLast()
        guard var trackpoint = pending else { return }
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "time":
            trackpoint.time = value.isEmpty ? nil : value
        case "distancemeters":
            trackpoint.distance = Self.finiteDouble(value)
        case "cadence":
            trackpoint.cadence = Self.finiteDouble(value)
        case "value" where isInsideHeartRate:
            if let heartRate = Self.finiteDouble(value),
               let roundedHeartRate = checkedPositiveRoundedInt(heartRate) {
                trackpoint.heartRate = roundedHeartRate
            }
        case "watts":
            trackpoint.watts = Self.finiteDouble(value)
        case "trackpoint":
            if let time = trackpoint.time,
               let seconds = secondsSinceEpoch(time),
               let distance = trackpoint.distance {
                samples.append(RawRivalSample(
                    t: seconds,
                    d: distance,
                    pace: nil,
                    spm: trackpoint.cadence,
                    hr: trackpoint.heartRate,
                    watts: trackpoint.watts
                ))
                if samples.count > sampleLimit {
                    exceededSampleLimit = true
                    parser.abortParsing()
                }
            }
            pending = nil
            currentElement = nil
            textBuffer.removeAll(keepingCapacity: true)
            return
        default:
            break
        }

        pending = trackpoint
        if name == "heartratebpm" {
            isInsideHeartRate = false
        }
        currentElement = nil
        textBuffer.removeAll(keepingCapacity: true)
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        guard !abortIfCancelled(parser) else { return }
        didReachEndDocument = true
    }

    func parser(
        _ parser: XMLParser,
        foundInternalEntityDeclarationWithName name: String,
        value: String?
    ) {
        rejectDocumentType(parser)
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        rejectDocumentType(parser)
    }

    func parser(
        _ parser: XMLParser,
        foundUnparsedEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?,
        notationName: String?
    ) {
        rejectDocumentType(parser)
    }

    func parser(
        _ parser: XMLParser,
        foundNotationDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        rejectDocumentType(parser)
    }

    func parser(
        _ parser: XMLParser,
        foundElementDeclarationWithName elementName: String,
        model: String
    ) {
        rejectDocumentType(parser)
    }

    func parser(
        _ parser: XMLParser,
        foundAttributeDeclarationWithName attributeName: String,
        forElement elementName: String,
        type: String?,
        defaultValue: String?
    ) {
        rejectDocumentType(parser)
    }

    private func rejectDocumentType(_ parser: XMLParser) {
        guard !abortIfCancelled(parser) else { return }
        isStructurallyMalformed = true
        parser.abortParsing()
    }

    private func abortIfCancelled(_ parser: XMLParser) -> Bool {
        guard Task<Never, Never>.isCancelled else { return false }
        wasCancelled = true
        parser.abortParsing()
        return true
    }

    private func secondsSinceEpoch(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = fractionalFormatter.date(from: trimmed) ?? basicFormatter.date(from: trimmed) {
            return date.timeIntervalSince1970
        }
        guard Self.looksLikeNaiveISO8601(trimmed) else { return nil }
        let utc = trimmed.hasSuffix("Z") ? trimmed : trimmed + "Z"
        return (fractionalFormatter.date(from: utc) ?? basicFormatter.date(from: utc))?.timeIntervalSince1970
    }

    private static func localName(_ qualifiedName: String) -> String {
        String(qualifiedName.split(separator: ":").last ?? Substring(qualifiedName)).lowercased()
    }

    private static func finiteDouble(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func looksLikeNaiveISO8601(_ text: String) -> Bool {
        guard text.utf8.count >= 19 else { return false }
        return text.utf8.prefix(19).enumerated().allSatisfy { index, byte in
            switch index {
            case 4, 7:
                return byte == 0x2D // -
            case 10:
                return byte == 0x54 // T
            case 13, 16:
                return byte == 0x3A // :
            default:
                return byte >= 0x30 && byte <= 0x39
            }
        }
    }
}

/// Portable, dependency-free CSV / TCX / FIT parser for replay rivals.
///
/// Limits: 25 MiB file size, 200_000 accepted samples.
/// Never logs file contents or paths.
public enum ReplayRivalFileParser: Sendable {
    public static let maximumFileSizeBytes = 25 * 1024 * 1024
    public static let maximumAcceptedSamples = 200_000

    public struct ParsedTrace: Equatable, Sendable {
        public var strokes: [Stroke]
        /// Last path component only (never a full path).
        public var fileName: String

        public init(strokes: [Stroke], fileName: String) {
            self.strokes = strokes
            self.fileName = fileName
        }
    }

    /// Parse rival file data using the selected file's last path component for type hints.
    public static func parse(data: Data, fileName: String) throws -> ParsedTrace {
        try checkReplayImportCancellation()
        guard data.count <= maximumFileSizeBytes else {
            throw ReplayRivalFileParserError.fileTooLarge
        }

        // Normalize sliced `Data` (non-zero `startIndex`) so every internal
        // byte walk can use zero-based offsets safely.
        let data = data.startIndex == 0 ? data : Data(data)

        let lastComponent = ReplayPathUtilities.lastPathComponent(fileName)
        let ext = (lastComponent as NSString).pathExtension.lowercased()

        // Extension wins for known rival types so a 4-byte `.FIT` coincidence
        // inside CSV/TCX text cannot hijack dispatch. Signature sniffing is
        // reserved for empty/unknown extensions.
        let raw: [RawRivalSample]
        switch ext {
        case "fit":
            raw = try parseFit(data)
        case "tcx":
            raw = try parseTcx(data)
        case "csv", "txt", "text":
            raw = try parseCsvData(data)
        default:
            if isFitSignature(data) {
                raw = try parseFit(data)
            } else if try looksLikeTcx(data) {
                raw = try parseTcx(data)
            } else {
                raw = try parseCsvData(data)
            }
        }

        try checkReplayImportCancellation()
        let strokes = try finalize(raw)
        return ParsedTrace(strokes: strokes, fileName: lastComponent)
    }

    private static func parseCsvData(_ data: Data) throws -> [RawRivalSample] {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ReplayRivalFileParserError.unreadable
        }
        try checkReplayImportCancellation()
        return try parseCsv(text)
    }

    // MARK: - Normalization

    private static func finalize(_ raw: [RawRivalSample]) throws -> [Stroke] {
        var pts: [(offset: Int, element: RawRivalSample)] = []
        pts.reserveCapacity(raw.count)
        for (offset, sample) in raw.enumerated() {
            if offset.isMultiple(of: 4_096) {
                try checkReplayImportCancellation()
            }
            if sample.t.isFinite && sample.d.isFinite && sample.d >= 0 && sample.t >= 0 {
                pts.append((offset: offset, element: sample))
            }
        }

        var comparisonCount = 0
        try pts.sort { lhs, rhs in
            comparisonCount &+= 1
            if comparisonCount.isMultiple(of: 4_096) {
                try checkReplayImportCancellation()
            }
            if lhs.element.t != rhs.element.t {
                return lhs.element.t < rhs.element.t
            }
            if lhs.element.d != rhs.element.d {
                return lhs.element.d > rhs.element.d
            }
            return lhs.offset < rhs.offset
        }

        // Keep one deterministic, farthest-distance sample per timestamp, then
        // remove backward distance so output time is strictly increasing.
        var cleaned: [RawRivalSample] = []
        cleaned.reserveCapacity(min(pts.count, maximumAcceptedSamples + 1))
        for (index, point) in pts.enumerated() {
            if index.isMultiple(of: 4_096) {
                try checkReplayImportCancellation()
            }
            let sample = point.element
            if let last = cleaned.last {
                if sample.t == last.t { continue }
                if sample.d < last.d { continue }
            }
            cleaned.append(sample)
            if cleaned.count > maximumAcceptedSamples {
                throw ReplayRivalFileParserError.tooManySamples
            }
        }

        guard cleaned.count >= 2 else {
            throw ReplayRivalFileParserError.tooFewSamples
        }

        // Normalize first accepted time to zero.
        let t0 = cleaned[0].t
        var out: [Stroke] = []
        out.reserveCapacity(cleaned.count)

        for i in 0..<cleaned.count {
            if i.isMultiple(of: 4_096) {
                try checkReplayImportCancellation()
            }
            let s = cleaned[i]
            let t = s.t - t0
            guard t.isFinite, t >= 0 else { continue }

            let resolvedPace: TimeInterval
            if let pace = s.pace, pace.isFinite, pace > 0 {
                resolvedPace = pace
            } else {
                if i > 0 {
                    let prev = cleaned[i - 1]
                    let dd = s.d - prev.d
                    let dt = s.t - prev.t
                    if dd > 0, dt > 0 {
                        resolvedPace = dt / (dd / 500.0)
                    } else if let last = out.last {
                        resolvedPace = last.pace
                    } else {
                        resolvedPace = 0
                    }
                } else {
                    resolvedPace = 0
                }
            }

            let safePace = resolvedPace.isFinite && resolvedPace >= 0 ? resolvedPace : 0
            let watts: Int
            if let w = s.watts, let importedWatts = checkedPositiveRoundedInt(w) {
                watts = importedWatts
            } else {
                let derived = RowPlayFormatting.paceToWatts(safePace)
                watts = checkedPositiveRoundedInt(derived) ?? 0
            }

            let cadence = s.spm.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
            let hr = s.hr.flatMap { $0 > 0 ? $0 : nil }

            out.append(Stroke(
                t: t,
                d: s.d,
                pace: safePace,
                cadence: cadence,
                heartRate: hr,
                watts: watts
            ))
        }

        // Cap output and re-check count after dropping non-finite rows.
        if out.count > maximumAcceptedSamples {
            throw ReplayRivalFileParserError.tooManySamples
        }
        guard out.count >= 2 else {
            throw ReplayRivalFileParserError.tooFewSamples
        }
        return out
    }

    // MARK: - CSV

    private static func parseCsv(_ text: String) throws -> [RawRivalSample] {
        try checkReplayImportCancellation()
        var didReadHeader = false
        var ti = -1
        var di = -1
        var pi = -1
        var hi = -1
        var si = -1
        var wi = -1
        var out: [RawRivalSample] = []
        out.reserveCapacity(min(maximumAcceptedSamples, 4_096))

        try forEachCsvRow(in: text) { columns in
            try checkReplayImportCancellation()
            if !didReadHeader {
                let header = columns.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                // Prefer exact/token matches so "timestamp" does not steal
                // elapsed time and "parameter" does not steal distance.
                ti = findHeader(
                    header,
                    names: ["elapsed", "seconds", "timer", "time"],
                    rejectedTokens: ["stamp", "date", "day", "zone", "clock", "local", "utc"]
                )
                di = findHeader(
                    header,
                    names: ["distance", "dist", "meters", "metres", "meter", "metre"],
                    rejectedTokens: ["parameter", "diameter"]
                )
                pi = findHeader(header, names: ["pace"])
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
                wi = findHeader(header, names: ["watts", "watt", "power"])
                didReadHeader = true
                return
            }

            guard ti >= 0, di >= 0 else { return }
            let t = parseClock(col(columns, ti))
            let d = numOrNaN(col(columns, di))
            guard t.isFinite, d.isFinite else { return }
            let pace = pi >= 0 ? parseClock(col(columns, pi)) : .nan
            out.append(RawRivalSample(
                t: t,
                d: d,
                pace: pace.isFinite && pace > 0 ? pace : nil,
                spm: si >= 0 ? numOrUndef(col(columns, si)) : nil,
                hr: hi >= 0 ? intOrUndef(col(columns, hi)) : nil,
                watts: wi >= 0 ? numOrUndef(col(columns, wi)) : nil
            ))
            if out.count > maximumAcceptedSamples {
                throw ReplayRivalFileParserError.tooManySamples
            }
        }
        return out
    }

    /// RFC 4180-style row scanner. It preserves quoted commas/newlines,
    /// unescapes doubled quotes, rejects unbalanced quotes, and emits one row
    /// at a time so a 25 MiB input does not require a second full-file copy.
    private static func forEachCsvRow(
        in text: String,
        _ body: ([String]) throws -> Void
    ) throws {
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var didCloseQuote = false
        var index = text.startIndex
        var scannedCharacters = 0

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

        while index < text.endIndex {
            if scannedCharacters.isMultiple(of: 4_096) {
                try checkReplayImportCancellation()
            }
            scannedCharacters &+= 1
            let character = text[index]
            if isQuoted {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    isQuoted = false
                    didCloseQuote = true
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                guard !didCloseQuote,
                      field.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw ReplayRivalFileParserError.malformed
                }
                field.removeAll(keepingCapacity: true)
                isQuoted = true
            } else if character == "," {
                finishField()
            } else if character.isNewline {
                try finishRow()
            } else if didCloseQuote {
                guard character.isWhitespace else {
                    throw ReplayRivalFileParserError.malformed
                }
            } else {
                field.append(character)
            }
            index = text.index(after: index)
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
        let s = value.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return .nan }
        if s.contains(":") {
            let rawParts = s.split(separator: ":", omittingEmptySubsequences: false)
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
        return Double(normalizedNumberString(s)) ?? .nan
    }

    private static func col(_ cols: [String], _ index: Int) -> String? {
        guard index >= 0, index < cols.count else { return nil }
        return cols[index]
    }

    private static func numOrNaN(_ value: String?) -> Double {
        guard let value,
              let n = Double(normalizedNumberString(value)),
              n.isFinite else {
            return .nan
        }
        return n
    }

    private static func numOrUndef(_ value: String?) -> Double? {
        guard let value,
              let n = Double(normalizedNumberString(value)),
              n.isFinite else {
            return nil
        }
        return n
    }

    private static func intOrUndef(_ value: String?) -> Int? {
        guard let n = numOrUndef(value) else { return nil }
        return checkedPositiveRoundedInt(n)
    }

    private static func normalizedNumberString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return trimmed }

        // Support both "1,000.5" (US) and "1.000,5" (EU) thousand/decimal forms
        // without treating a lone European decimal comma as a thousands mark.
        let hasDot = trimmed.contains(".")
        let hasComma = trimmed.contains(",")
        if hasDot && hasComma {
            if let lastDot = trimmed.lastIndex(of: "."),
               let lastComma = trimmed.lastIndex(of: ",") {
                if lastComma > lastDot {
                    // 1.000,5 → 1000.5
                    return trimmed
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                }
                // 1,000.5 → 1000.5
                return trimmed.replacingOccurrences(of: ",", with: "")
            }
        }
        if hasComma && !hasDot {
            let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
            // Only 1–2 fractional digits count as a European decimal ("1,5",
            // "1,50"). Three digits are treated as a thousands group ("1,000").
            if parts.count == 2,
               (1...2).contains(parts[1].count),
               parts[0].allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" }),
               parts[1].allSatisfy(\.isNumber) {
                return "\(parts[0]).\(parts[1])"
            }
            // Thousands groups: 1,000 → 1000
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
        // Last resort: multi-word phrase containment (e.g. "stroke rate").
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

    // MARK: - TCX

    private static func looksLikeTcx(_ data: Data) throws -> Bool {
        try checkReplayImportCancellation()
        guard let text = xmlProbeText(data) else {
            return false
        }

        func index(after terminator: String, from start: String.Index) -> String.Index? {
            text.range(of: terminator, range: start..<text.endIndex)?.upperBound
        }

        func indexAfterTag(from start: String.Index) throws -> String.Index? {
            var cursor = start
            var quote: Character?
            var scannedCharacters = 0
            while cursor < text.endIndex {
                if scannedCharacters.isMultiple(of: 1_024) {
                    try checkReplayImportCancellation()
                }
                scannedCharacters &+= 1
                let character = text[cursor]
                if let activeQuote = quote {
                    if character == activeQuote {
                        quote = nil
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == ">" {
                    return text.index(after: cursor)
                }
                cursor = text.index(after: cursor)
            }
            return nil
        }

        var documentStart = text.startIndex
        while documentStart < text.endIndex,
              text[documentStart].isWhitespace || text[documentStart] == "\u{FEFF}" {
            documentStart = text.index(after: documentStart)
        }
        guard documentStart < text.endIndex, text[documentStart] == "<" else {
            return false
        }

        var searchStart = documentStart
        while searchStart < text.endIndex,
              let openingBracket = text[searchStart...].firstIndex(of: "<") {
            try checkReplayImportCancellation()
            let nameStart = text.index(after: openingBracket)
            guard nameStart < text.endIndex else { return false }

            let marker = text[nameStart]
            let remainder = text[nameStart...]
            if remainder.hasPrefix("!--") {
                guard let end = index(after: "-->", from: nameStart) else { return false }
                searchStart = end
                continue
            }
            if remainder.hasPrefix("![CDATA[") {
                guard let end = index(after: "]]>", from: nameStart) else { return false }
                searchStart = end
                continue
            }
            if marker == "?" {
                guard let end = index(after: "?>", from: nameStart) else { return false }
                searchStart = end
                continue
            }
            if marker == "/" || marker == "!" {
                guard let end = try indexAfterTag(from: nameStart) else { return false }
                searchStart = end
                continue
            }
            if marker.isWhitespace {
                return false
            }

            let nameEnd = text[nameStart...].firstIndex {
                $0.isWhitespace || $0 == "/" || $0 == ">"
            } ?? text.endIndex
            guard nameStart < nameEnd,
                  let tagEnd = try indexAfterTag(from: nameEnd) else {
                return false
            }

            let qualifiedName = text[nameStart..<nameEnd]
            let localName = qualifiedName.split(separator: ":").last?.lowercased()
            if localName == "trainingcenterdatabase" || localName == "trackpoint" {
                return true
            }
            searchStart = tagEnd
        }
        return false
    }

    private static func xmlProbeText(_ data: Data) -> String? {
        let prefix = Data(data.prefix(4096))
        let leadingBytes = Array(prefix.prefix(4))
        let encoding: String.Encoding?

        if leadingBytes.starts(with: [0x00, 0x00, 0xFE, 0xFF])
            || leadingBytes.starts(with: [0x00, 0x00, 0x00, 0x3C]) {
            encoding = .utf32BigEndian
        } else if leadingBytes.starts(with: [0xFF, 0xFE, 0x00, 0x00])
                    || leadingBytes.starts(with: [0x3C, 0x00, 0x00, 0x00]) {
            encoding = .utf32LittleEndian
        } else if leadingBytes.starts(with: [0xFE, 0xFF])
                    || leadingBytes.starts(with: [0x00, 0x3C]) {
            encoding = .utf16BigEndian
        } else if leadingBytes.starts(with: [0xFF, 0xFE])
                    || leadingBytes.starts(with: [0x3C, 0x00]) {
            encoding = .utf16LittleEndian
        } else {
            encoding = nil
        }

        if let encoding {
            return String(data: prefix, encoding: encoding)
        }
        return String(data: prefix, encoding: .utf8)
            ?? String(data: prefix, encoding: .isoLatin1)
    }

    /// Reject DOCTYPE / DTD payloads before XMLParser runs.
    ///
    /// Scans the raw bytes for `<!DOCTYPE` in UTF-8 and the common multi-byte
    /// XML encodings (UTF-16/32, both endiannesses) rather than relying only on
    /// a zero-byte strip, which is harder to reason about under review and can
    /// false-match unrelated binary with interleaved zeros.
    private static func containsDocumentTypeDeclaration(_ data: Data) throws -> Bool {
        // Early probe covers the usual declaration-at-start case across encodings.
        if let probe = xmlProbeText(data),
           probe.range(of: "<!DOCTYPE", options: [.caseInsensitive, .literal]) != nil {
            return true
        }

        // Full-file UTF-8 / ASCII-compatible scan catches late declarations.
        if try containsASCIISequence(
            data,
            ascii: "<!DOCTYPE",
            unitWidth: 1,
            littleEndian: true
        ) {
            return true
        }

        // Wide encodings pad ASCII with zero bytes. Skip the multi-byte scans
        // when no zeros are present (pure UTF-8/Latin-1 payloads).
        guard data.contains(0) else { return false }

        let wideLayouts: [(unitWidth: Int, littleEndian: Bool)] = [
            (2, true),   // UTF-16 LE
            (2, false),  // UTF-16 BE
            (4, true),   // UTF-32 LE
            (4, false),  // UTF-32 BE
        ]
        for layout in wideLayouts {
            if try containsASCIISequence(
                data,
                ascii: "<!DOCTYPE",
                unitWidth: layout.unitWidth,
                littleEndian: layout.littleEndian
            ) {
                return true
            }
        }
        return false
    }

    /// Case-insensitive search for an ASCII needle encoded with fixed-width units.
    ///
    /// Uses `withUnsafeBytes` so sliced `Data` (non-zero `startIndex`) cannot
    /// trap on integer subscripts.
    private static func containsASCIISequence(
        _ data: Data,
        ascii: String,
        unitWidth: Int,
        littleEndian: Bool
    ) throws -> Bool {
        let needle = Array(ascii.utf8)
        guard !needle.isEmpty, unitWidth == 1 || unitWidth == 2 || unitWidth == 4 else {
            return false
        }

        return try data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }
            let count = buffer.count
            var matched = 0
            var offset = 0
            while offset + unitWidth <= count {
                if offset.isMultiple(of: 4_096) {
                    try checkReplayImportCancellation()
                }

                let codeUnit: UInt32
                switch unitWidth {
                case 1:
                    codeUnit = UInt32(base[offset])
                case 2:
                    let b0 = UInt32(base[offset])
                    let b1 = UInt32(base[offset + 1])
                    codeUnit = littleEndian ? (b0 | (b1 &<< 8)) : ((b0 &<< 8) | b1)
                default:
                    let b0 = UInt32(base[offset])
                    let b1 = UInt32(base[offset + 1])
                    let b2 = UInt32(base[offset + 2])
                    let b3 = UInt32(base[offset + 3])
                    codeUnit = littleEndian
                        ? (b0 | (b1 &<< 8) | (b2 &<< 16) | (b3 &<< 24))
                        : ((b0 &<< 24) | (b1 &<< 16) | (b2 &<< 8) | b3)
                }

                // Only pure ASCII code units participate; multi-byte content resets.
                if codeUnit <= 0x7F {
                    var normalized = UInt8(codeUnit)
                    if normalized >= 0x61 && normalized <= 0x7A {
                        normalized -= 0x20
                    }
                    if normalized == needle[matched] {
                        matched += 1
                        if matched == needle.count {
                            return true
                        }
                    } else {
                        matched = normalized == needle[0] ? 1 : 0
                    }
                } else {
                    matched = 0
                }

                offset += unitWidth
            }
            return false
        }
    }

    private static func parseTcx(_ data: Data) throws -> [RawRivalSample] {
        try checkReplayImportCancellation()
        // A bare DOCTYPE may not emit an XMLParser delegate callback. Reject it
        // up front with multi-encoding raw scans; the delegate callbacks remain
        // defense in depth for declarations.
        guard try !containsDocumentTypeDeclaration(data) else {
            throw ReplayRivalFileParserError.malformed
        }
        let delegate = ReplayTcxParserDelegate(sampleLimit: maximumAcceptedSamples)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        let succeeded = parser.parse()
        if delegate.wasCancelled {
            throw CancellationError()
        }
        try checkReplayImportCancellation()
        if delegate.exceededSampleLimit {
            throw ReplayRivalFileParserError.tooManySamples
        }
        guard succeeded, delegate.isStructurallyComplete else {
            throw ReplayRivalFileParserError.malformed
        }
        return delegate.samples
    }

    // MARK: - FIT

    private static let fitRecordGlobal: UInt16 = 20

    private struct FitFieldDef {
        var num: Int
        var size: Int
        var baseType: UInt8
    }

    private struct FitMsgDef {
        var global: UInt16
        var littleEndian: Bool
        var fields: [FitFieldDef]
    }

    private struct FitRecord {
        var ts: UInt32?
        var dist: UInt32?
        var speed: UInt32?
        var power: UInt16?
        var cad: UInt8?
        var hr: UInt8?
    }

    private static func isFitSignature(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        // Bytes 8-11 are ".FIT"
        let signatureStart = data.index(data.startIndex, offsetBy: 8)
        let signatureEnd = data.index(signatureStart, offsetBy: 4)
        return data[signatureStart..<signatureEnd].elementsEqual([0x2E, 0x46, 0x49, 0x54])
    }

    private static func parseFit(_ data: Data) throws -> [RawRivalSample] {
        try checkReplayImportCancellation()
        guard data.count >= 14 else { throw ReplayRivalFileParserError.malformed }
        return try data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> [RawRivalSample] in
            guard let base = rawBuffer.baseAddress else {
                throw ReplayRivalFileParserError.unreadable
            }
            let byteCount = rawBuffer.count
            let headerSize = Int(base.load(as: UInt8.self))
            guard headerSize >= 12, headerSize <= byteCount else {
                throw ReplayRivalFileParserError.malformed
            }

            // dataSize at offset 4, little-endian
            let dataSize = Int(readUInt32(base, offset: 4, littleEndian: true))
            guard isFitSignature(data) else {
                throw ReplayRivalFileParserError.malformed
            }

            guard dataSize <= byteCount - headerSize else {
                throw ReplayRivalFileParserError.malformed
            }
            let end = headerSize + dataSize

            var defs: [Int: FitMsgDef] = [:]
            var records: [FitRecord] = []
            var lastTimestamp: UInt32?
            var pos = headerSize
            var parsedMessageCount = 0

            while pos < end {
                if parsedMessageCount.isMultiple(of: 256) {
                    try checkReplayImportCancellation()
                }
                parsedMessageCount &+= 1
                guard pos < end else { break }
                let header = Int(readUInt8(base, offset: pos))
                pos += 1

                if header & 0x80 != 0 {
                    let local = (header >> 5) & 0x3
                    let timeOffset = UInt32(header & 0x1F)
                    guard let def = defs[local], let previousTimestamp = lastTimestamp else {
                        throw ReplayRivalFileParserError.malformed
                    }

                    // A compressed timestamp header replaces both the normal
                    // data header and field 253 in the record payload.
                    var rec = FitRecord()
                    var timestamp = (previousTimestamp & ~UInt32(0x1F)) | timeOffset
                    if timestamp < previousTimestamp {
                        timestamp &+= 0x20
                    }
                    rec.ts = timestamp

                    for field in def.fields where field.num != 253 {
                        guard field.size >= 0, pos + field.size <= end else {
                            throw ReplayRivalFileParserError.malformed
                        }
                        if def.global == fitRecordGlobal, field.num >= 0,
                           let value = readBase(
                               base,
                               offset: pos,
                               baseType: field.baseType,
                               littleEndian: def.littleEndian,
                               end: pos + field.size
                           ) {
                            assignRecordField(&rec, num: field.num, value: value)
                        }
                        pos += field.size
                    }

                    lastTimestamp = timestamp
                    if def.global == fitRecordGlobal {
                        records.append(rec)
                        if records.count > maximumAcceptedSamples {
                            throw ReplayRivalFileParserError.tooManySamples
                        }
                    }
                    continue
                }

                let local = header & 0x0F
                if header & 0x40 != 0 {
                    // Definition message.
                    guard pos + 5 <= end else { throw ReplayRivalFileParserError.malformed }
                    let architecture = readUInt8(base, offset: pos + 1)
                    guard architecture == 0 || architecture == 1 else {
                        throw ReplayRivalFileParserError.malformed
                    }
                    let littleEndian = architecture == 0
                    let global = readUInt16(base, offset: pos + 2, littleEndian: littleEndian)
                    let numFields = Int(readUInt8(base, offset: pos + 4))
                    pos += 5
                    var fields: [FitFieldDef] = []
                    fields.reserveCapacity(numFields)
                    for _ in 0..<numFields {
                        guard pos + 3 <= end else { throw ReplayRivalFileParserError.malformed }
                        fields.append(FitFieldDef(
                            num: Int(readUInt8(base, offset: pos)),
                            size: Int(readUInt8(base, offset: pos + 1)),
                            baseType: readUInt8(base, offset: pos + 2)
                        ))
                        pos += 3
                    }
                    if header & 0x20 != 0 {
                        guard pos < end else { throw ReplayRivalFileParserError.malformed }
                        let numDev = Int(readUInt8(base, offset: pos))
                        pos += 1
                        for _ in 0..<numDev {
                            guard pos + 3 <= end else { throw ReplayRivalFileParserError.malformed }
                            fields.append(FitFieldDef(
                                num: -1,
                                size: Int(readUInt8(base, offset: pos + 1)),
                                baseType: 0x0D
                            ))
                            pos += 3
                        }
                    }
                    defs[local] = FitMsgDef(global: global, littleEndian: littleEndian, fields: fields)
                } else {
                    // Data message.
                    guard let def = defs[local] else {
                        throw ReplayRivalFileParserError.malformed
                    }
                    var rec = FitRecord()
                    for field in def.fields {
                        guard field.size >= 0, pos + field.size <= end else {
                            throw ReplayRivalFileParserError.malformed
                        }
                        // Timestamp (field 253) can appear on any global message
                        // and is the basis for later compressed-timestamp records.
                        if field.num >= 0 {
                            if let v = readBase(
                                base,
                                offset: pos,
                                baseType: field.baseType,
                                littleEndian: def.littleEndian,
                                end: pos + field.size
                            ) {
                                if field.num == 253 {
                                    assignRecordField(&rec, num: field.num, value: v)
                                } else if def.global == fitRecordGlobal {
                                    assignRecordField(&rec, num: field.num, value: v)
                                }
                            }
                        }
                        pos += field.size
                    }
                    // Always advance the compressed-timestamp base when present.
                    if let timestamp = rec.ts {
                        lastTimestamp = timestamp
                    }
                    if def.global == fitRecordGlobal, rec.ts != nil {
                        records.append(rec)
                        if records.count > maximumAcceptedSamples {
                            throw ReplayRivalFileParserError.tooManySamples
                        }
                    }
                }
            }

            guard !records.isEmpty else { return [] }

            var ts0 = UInt32.max
            for (index, r) in records.enumerated() {
                if index.isMultiple(of: 4_096) {
                    try checkReplayImportCancellation()
                }
                if let ts = r.ts, ts < ts0 { ts0 = ts }
            }
            guard ts0 != UInt32.max else { return [] }

            var out: [RawRivalSample] = []
            out.reserveCapacity(records.count)
            for (index, r) in records.enumerated() {
                if index.isMultiple(of: 4_096) {
                    try checkReplayImportCancellation()
                }
                guard let ts = r.ts else { continue }
                let speedMps: Double? = r.speed.map { Double($0) / 1000.0 }
                let pace: Double? = {
                    guard let speed = speedMps, speed > 0 else { return nil }
                    return 500.0 / speed
                }()
                let dist: Double = r.dist.map { Double($0) / 100.0 } ?? .nan
                let t = Double(ts &- ts0)
                guard t.isFinite, dist.isFinite else { continue }
                out.append(RawRivalSample(
                    t: t,
                    d: dist,
                    pace: pace,
                    spm: r.cad.map { Double($0) },
                    hr: r.hr.map { Int($0) },
                    watts: r.power.map { Double($0) }
                ))
            }
            return out
        }
    }

    private static func assignRecordField(_ rec: inout FitRecord, num: Int, value: Double) {
        switch num {
        case 253:
            if value >= 0, value <= Double(UInt32.max) {
                rec.ts = UInt32(value)
            }
        case 5:
            if value >= 0, value <= Double(UInt32.max) {
                rec.dist = UInt32(value)
            }
        case 6:
            if value >= 0, value <= Double(UInt32.max) {
                rec.speed = UInt32(value)
            }
        case 73:
            if rec.speed == nil, value >= 0, value <= Double(UInt32.max) {
                rec.speed = UInt32(value)
            }
        case 7:
            if value >= 0, value <= Double(UInt16.max) {
                rec.power = UInt16(value)
            }
        case 4:
            if value >= 0, value <= Double(UInt8.max) {
                rec.cad = UInt8(value)
            }
        case 3:
            if value >= 0, value <= Double(UInt8.max) {
                rec.hr = UInt8(value)
            }
        default:
            break
        }
    }

    private static func readBase(
        _ base: UnsafeRawPointer,
        offset: Int,
        baseType: UInt8,
        littleEndian: Bool,
        end: Int
    ) -> Double? {
        let type = baseType & 0x0F
        switch type {
        case 1:
            guard offset + 1 <= end else { return nil }
            let v = Int8(bitPattern: readUInt8(base, offset: offset))
            return v == 0x7F ? nil : Double(v)
        case 0, 2, 10, 13:
            guard offset + 1 <= end else { return nil }
            let v = readUInt8(base, offset: offset)
            return v == 0xFF ? nil : Double(v)
        case 3:
            guard offset + 2 <= end else { return nil }
            let v = Int16(bitPattern: readUInt16(base, offset: offset, littleEndian: littleEndian))
            return v == 0x7FFF ? nil : Double(v)
        case 4, 11:
            guard offset + 2 <= end else { return nil }
            let v = readUInt16(base, offset: offset, littleEndian: littleEndian)
            return v == 0xFFFF ? nil : Double(v)
        case 5:
            guard offset + 4 <= end else { return nil }
            let v = Int32(bitPattern: readUInt32(base, offset: offset, littleEndian: littleEndian))
            return v == 0x7FFF_FFFF ? nil : Double(v)
        case 6, 12:
            guard offset + 4 <= end else { return nil }
            let v = readUInt32(base, offset: offset, littleEndian: littleEndian)
            return v == 0xFFFF_FFFF ? nil : Double(v)
        case 8:
            guard offset + 4 <= end else { return nil }
            let bits = readUInt32(base, offset: offset, littleEndian: littleEndian)
            let v = Float(bitPattern: bits)
            return v.isNaN ? nil : Double(v)
        case 9:
            guard offset + 8 <= end else { return nil }
            let bits = readUInt64(base, offset: offset, littleEndian: littleEndian)
            let v = Double(bitPattern: bits)
            return v.isNaN ? nil : v
        default:
            return nil
        }
    }

    private static func readUInt8(_ base: UnsafeRawPointer, offset: Int) -> UInt8 {
        base.load(fromByteOffset: offset, as: UInt8.self)
    }

    private static func readUInt16(_ base: UnsafeRawPointer, offset: Int, littleEndian: Bool) -> UInt16 {
        let b0 = UInt16(base.load(fromByteOffset: offset, as: UInt8.self))
        let b1 = UInt16(base.load(fromByteOffset: offset + 1, as: UInt8.self))
        return littleEndian ? (b0 | (b1 &<< 8)) : ((b0 &<< 8) | b1)
    }

    private static func readUInt32(_ base: UnsafeRawPointer, offset: Int, littleEndian: Bool) -> UInt32 {
        let b0 = UInt32(base.load(fromByteOffset: offset, as: UInt8.self))
        let b1 = UInt32(base.load(fromByteOffset: offset + 1, as: UInt8.self))
        let b2 = UInt32(base.load(fromByteOffset: offset + 2, as: UInt8.self))
        let b3 = UInt32(base.load(fromByteOffset: offset + 3, as: UInt8.self))
        if littleEndian {
            return b0 | (b1 &<< 8) | (b2 &<< 16) | (b3 &<< 24)
        }
        return (b0 &<< 24) | (b1 &<< 16) | (b2 &<< 8) | b3
    }

    private static func readUInt64(_ base: UnsafeRawPointer, offset: Int, littleEndian: Bool) -> UInt64 {
        let lo = UInt64(readUInt32(base, offset: offset, littleEndian: littleEndian))
        let hi = UInt64(readUInt32(base, offset: offset + 4, littleEndian: littleEndian))
        return littleEndian ? (lo | (hi &<< 32)) : (hi | (lo &<< 32))
    }

}
