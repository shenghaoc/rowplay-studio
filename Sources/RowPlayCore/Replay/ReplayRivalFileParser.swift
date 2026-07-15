import Foundation

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
        guard data.count <= maximumFileSizeBytes else {
            throw ReplayRivalFileParserError.fileTooLarge
        }

        let lastComponent = lastPathComponent(fileName)
        let ext = (lastComponent as NSString).pathExtension.lowercased()

        let raw: [RawRivalSample]
        if ext == "fit" || isFitSignature(data) {
            raw = try parseFit(data)
        } else if ext == "tcx" || looksLikeTcx(data) {
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                throw ReplayRivalFileParserError.unreadable
            }
            raw = parseTcx(text)
        } else {
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                throw ReplayRivalFileParserError.unreadable
            }
            raw = parseCsv(text)
        }

        let strokes = try finalize(raw)
        return ParsedTrace(strokes: strokes, fileName: lastComponent)
    }

    // MARK: - Normalization

    private static func finalize(_ raw: [RawRivalSample]) throws -> [Stroke] {
        var pts = raw.filter { sample in
            sample.t.isFinite && sample.d.isFinite && sample.d >= 0 && sample.t >= 0
        }
        pts.sort { $0.t < $1.t }

        // Remove backward / duplicate-invalid samples (non-increasing time after first).
        var cleaned: [RawRivalSample] = []
        cleaned.reserveCapacity(min(pts.count, maximumAcceptedSamples + 1))
        for sample in pts {
            if let last = cleaned.last {
                if sample.t < last.t { continue }
                // Drop exact duplicate timestamps with lower or equal distance (invalid).
                if sample.t == last.t && sample.d <= last.d { continue }
                // Drop backward distance at strictly later time.
                if sample.t > last.t && sample.d < last.d { continue }
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
            let s = cleaned[i]
            let t = s.t - t0
            guard t.isFinite, t >= 0 else { continue }

            var pace = s.pace
            if pace == nil || !(pace!.isFinite) || pace! <= 0 {
                if i > 0 {
                    let prev = cleaned[i - 1]
                    let dd = s.d - prev.d
                    let dt = s.t - prev.t
                    if dd > 0, dt > 0 {
                        pace = dt / (dd / 500.0)
                    } else if let last = out.last {
                        pace = last.pace
                    } else {
                        pace = 0
                    }
                } else {
                    pace = 0
                }
            }

            let safePace = (pace?.isFinite == true && pace! >= 0) ? pace! : 0
            let watts: Int
            if let w = s.watts, w.isFinite, w > 0, w <= Double(Int.max) {
                watts = Int(w.rounded())
            } else {
                let derived = RowPlayFormatting.paceToWatts(safePace)
                watts = derived.isFinite && derived > 0 && derived <= Double(Int.max)
                    ? Int(derived.rounded())
                    : 0
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

    private static func parseCsv(_ text: String) -> [RawRivalSample] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard lines.count >= 2 else { return [] }

        let header = splitCsv(lines[0]).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func find(_ names: String...) -> Int {
            header.firstIndex { h in names.contains(where: { h.contains($0) }) } ?? -1
        }

        let ti = find("time", "seconds", "elapsed")
        let di = find("distance", "meter", "metre")
        let pi = find("pace")
        let hi = find("heart", "hr", "bpm")
        var si = find("stroke rate", "strokerate", "spm", "cadence")
        if si < 0 {
            // Skip heart_rate (and any other column already bound as HR) when
            // falling back to a generic "rate" header match.
            if let rateIdx = header.enumerated().first(where: {
                $0.offset != hi && $0.element.contains("rate")
            })?.offset {
                si = rateIdx
            }
        }
        let wi = find("watt", "power")
        guard ti >= 0, di >= 0 else { return [] }

        var out: [RawRivalSample] = []
        out.reserveCapacity(lines.count - 1)
        for i in 1..<lines.count {
            let cols = splitCsv(lines[i])
            let t = parseClock(col(cols, ti))
            let d = numOrNaN(col(cols, di))
            guard t.isFinite, d.isFinite else { continue }
            let pace = pi >= 0 ? parseClock(col(cols, pi)) : .nan
            out.append(RawRivalSample(
                t: t,
                d: d,
                pace: pace.isFinite && pace > 0 ? pace : nil,
                spm: si >= 0 ? numOrUndef(col(cols, si)) : nil,
                hr: hi >= 0 ? intOrUndef(col(cols, hi)) : nil,
                watts: wi >= 0 ? numOrUndef(col(cols, wi)) : nil
            ))
        }
        return out
    }

    private static func splitCsv(_ line: String) -> [String] {
        var cells: [String] = []
        var cell = ""
        var isQuoted = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if isQuoted, next < line.endIndex, line[next] == "\"" {
                    cell.append("\"")
                    index = line.index(after: next)
                    continue
                }
                isQuoted.toggle()
            } else if character == ",", !isQuoted {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell.removeAll(keepingCapacity: true)
            } else {
                cell.append(character)
            }
            index = line.index(after: index)
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// Numeric seconds, or M:SS / H:MM:SS clock string.
    private static func parseClock(_ value: String?) -> Double {
        guard let value else { return .nan }
        let s = value.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return .nan }
        if s.contains(":") {
            let parts = s.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.allSatisfy({ $0?.isFinite == true }) else { return .nan }
            return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
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
        guard n > 0, n <= Double(Int.max) else { return nil }
        return Int(n.rounded())
    }

    private static func normalizedNumberString(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
    }

    // MARK: - TCX

    /// Precompiled TCX patterns — never rebuild regexes per trackpoint.
    private static let trackpointRegex = try? NSRegularExpression(
        pattern: #"<Trackpoint\b[^>]*>([\s\S]*?)</Trackpoint>"#,
        options: [.caseInsensitive]
    )
    private static let timeTagRegex = try? NSRegularExpression(
        pattern: #"<([A-Za-z0-9_]+:)?Time\b[^>]*>([^<]*)</([A-Za-z0-9_]+:)?Time>"#,
        options: [.caseInsensitive]
    )
    private static let distanceMetersTagRegex = try? NSRegularExpression(
        pattern: #"<([A-Za-z0-9_]+:)?DistanceMeters\b[^>]*>([^<]*)</([A-Za-z0-9_]+:)?DistanceMeters>"#,
        options: [.caseInsensitive]
    )
    private static let cadenceTagRegex = try? NSRegularExpression(
        pattern: #"<([A-Za-z0-9_]+:)?Cadence\b[^>]*>([^<]*)</([A-Za-z0-9_]+:)?Cadence>"#,
        options: [.caseInsensitive]
    )
    private static let heartRateBpmTagRegex = try? NSRegularExpression(
        pattern: #"<([A-Za-z0-9_]+:)?HeartRateBpm\b[^>]*>([\s\S]*?)</([A-Za-z0-9_]+:)?HeartRateBpm>"#,
        options: [.caseInsensitive]
    )
    private static let valueTagRegex = try? NSRegularExpression(
        pattern: #"<([A-Za-z0-9_]+:)?Value\b[^>]*>([^<]*)</([A-Za-z0-9_]+:)?Value>"#,
        options: [.caseInsensitive]
    )
    private static let wattsTagRegex = try? NSRegularExpression(
        pattern: #"<([A-Za-z0-9_]+:)?Watts\b[^>]*>([^<]*)</([A-Za-z0-9_]+:)?Watts>"#,
        options: [.caseInsensitive]
    )

    private static func looksLikeTcx(_ data: Data) -> Bool {
        guard let text = String(data: data.prefix(4096), encoding: .utf8)
                ?? String(data: data.prefix(4096), encoding: .isoLatin1) else {
            return false
        }
        return text.range(of: "TrainingCenterDatabase", options: .caseInsensitive) != nil
            || text.range(of: "Trackpoint", options: .caseInsensitive) != nil
    }

    private static func parseTcx(_ text: String) -> [RawRivalSample] {
        // Lightweight namespace-insensitive regex extraction (no XML framework dependency).
        guard let trackpointRegex else { return [] }

        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = trackpointRegex.matches(in: text, range: full)
        var out: [RawRivalSample] = []
        out.reserveCapacity(matches.count)
        var t0: Double?

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let body = ns.substring(with: match.range(at: 1))
            let timeText = extractTagText(body, regex: timeTagRegex) ?? ""
            var ms = parseInstantMillis(timeText)
            if !ms.isFinite, looksLikeNaiveISO8601(timeText) {
                // Timezone-less ISO → treat as UTC.
                ms = parseInstantMillis(timeText.hasSuffix("Z") ? timeText : timeText + "Z")
            }
            if ms.isFinite, t0 == nil {
                t0 = ms
            }
            let t: Double
            if ms.isFinite, let origin = t0 {
                t = (ms - origin) / 1000.0
            } else {
                t = .nan
            }
            let d = Double(extractTagText(body, regex: distanceMetersTagRegex) ?? "") ?? .nan
            guard t.isFinite, d.isFinite else { continue }

            let cadence = Double(extractTagText(body, regex: cadenceTagRegex) ?? "")
            let hrValue = extractNestedTagText(
                body,
                outerRegex: heartRateBpmTagRegex,
                innerRegex: valueTagRegex
            ).flatMap { Double($0) }
            // Namespace-insensitive Watts also matches ns3:Watts.
            let watts = extractTagText(body, regex: wattsTagRegex).flatMap { Double($0) }

            out.append(RawRivalSample(
                t: t,
                d: d,
                pace: nil,
                spm: cadence.flatMap { $0.isFinite ? $0 : nil },
                hr: hrValue.flatMap { $0.isFinite && $0 > 0 ? Int($0.rounded()) : nil },
                watts: watts.flatMap { $0.isFinite ? $0 : nil }
            ))
        }
        return out
    }

    private static func extractTagText(_ body: String, regex: NSRegularExpression?) -> String? {
        guard let regex else { return nil }
        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: body, range: range), match.numberOfRanges >= 3 else {
            return nil
        }
        let value = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func extractNestedTagText(
        _ body: String,
        outerRegex: NSRegularExpression?,
        innerRegex: NSRegularExpression?
    ) -> String? {
        guard let outerRegex else { return nil }
        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = outerRegex.firstMatch(in: body, range: range), match.numberOfRanges >= 3 else {
            return nil
        }
        let outerBody = ns.substring(with: match.range(at: 2))
        return extractTagText(outerBody, regex: innerRegex)
    }

    /// Parse ISO-8601 instant to milliseconds since epoch.
    private static func parseInstantMillis(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .nan }

        // Prefer ISO8601DateFormatter with fractional seconds.
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: trimmed) {
            return date.timeIntervalSince1970 * 1000
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: trimmed) {
            return date.timeIntervalSince1970 * 1000
        }
        return .nan
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
        return data[8] == 0x2E && data[9] == 0x46 && data[10] == 0x49 && data[11] == 0x54
    }

    private static func parseFit(_ data: Data) throws -> [RawRivalSample] {
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

            let end = min(byteCount, headerSize + dataSize)
            guard end >= headerSize else { throw ReplayRivalFileParserError.malformed }

            var defs: [Int: FitMsgDef] = [:]
            var records: [FitRecord] = []
            var lastTimestamp: UInt32?
            var pos = headerSize

            while pos < end {
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
                    if timestamp <= previousTimestamp {
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
                               end: end
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
                    let littleEndian = readUInt8(base, offset: pos + 1) == 0
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
                    guard let def = defs[local] else { break }
                    var rec = FitRecord()
                    for field in def.fields {
                        guard field.size >= 0, pos + field.size <= end else {
                            throw ReplayRivalFileParserError.malformed
                        }
                        if def.global == fitRecordGlobal, field.num >= 0 {
                            if let v = readBase(
                                base,
                                offset: pos,
                                baseType: field.baseType,
                                littleEndian: def.littleEndian,
                                end: end
                            ) {
                                assignRecordField(&rec, num: field.num, value: v)
                            }
                        }
                        pos += field.size
                    }
                    if def.global == fitRecordGlobal, rec.ts != nil {
                        records.append(rec)
                        lastTimestamp = rec.ts
                        if records.count > maximumAcceptedSamples {
                            throw ReplayRivalFileParserError.tooManySamples
                        }
                    }
                }
            }

            guard !records.isEmpty else { return [] }

            var ts0 = UInt32.max
            for r in records {
                if let ts = r.ts, ts < ts0 { ts0 = ts }
            }
            guard ts0 != UInt32.max else { return [] }

            var out: [RawRivalSample] = []
            out.reserveCapacity(records.count)
            for r in records {
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

    // MARK: - Path helpers

    private static func lastPathComponent(_ path: String) -> String {
        if let slash = path.lastIndex(of: "/") {
            return String(path[path.index(after: slash)...])
        }
        if let slash = path.lastIndex(of: "\\") {
            return String(path[path.index(after: slash)...])
        }
        return path
    }
}
