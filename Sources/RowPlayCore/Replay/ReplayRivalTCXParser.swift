import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

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
                return byte == 0x2D
            case 10:
                return byte == 0x54
            case 13, 16:
                return byte == 0x3A
            default:
                return byte >= 0x30 && byte <= 0x39
            }
        }
    }
}

/// Focused TCX content detector and bounded XML decoder.
enum ReplayRivalTCXParser {
    static func looksLikeTCX(_ data: Data) throws -> Bool {
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

    static func parse(_ data: Data, sampleLimit: Int) throws -> [RawRivalSample] {
        try checkReplayImportCancellation()
        guard try !containsDocumentTypeDeclaration(data) else {
            throw ReplayRivalFileParserError.malformed
        }
        let delegate = ReplayTcxParserDelegate(sampleLimit: sampleLimit)
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

    private static func xmlProbeText(_ data: Data) -> String? {
        let prefix = Data(data.prefix(4096))
        let layout = xmlCodeUnitLayout(prefix)

        if let encoding = layout.encoding {
            return String(data: prefix, encoding: encoding)
        }
        return String(data: prefix, encoding: .utf8)
            ?? String(data: prefix, encoding: .isoLatin1)
    }

    private static func containsDocumentTypeDeclaration(_ data: Data) throws -> Bool {
        let layout = xmlCodeUnitLayout(data)
        return try containsASCIISequence(
            data,
            ascii: "<!DOCTYPE",
            unitWidth: layout.unitWidth,
            littleEndian: layout.littleEndian
        )
    }

    /// XML's BOM or required opening markup identifies the code-unit layout.
    /// Selecting it once keeps the security scan to one full-file pass without
    /// truncating the prolog, where a document type declaration may legally
    /// appear before the root element.
    private static func xmlCodeUnitLayout(
        _ data: Data
    ) -> (unitWidth: Int, littleEndian: Bool, encoding: String.Encoding?) {
        let leadingBytes = Array(data.prefix(4))
        if leadingBytes.starts(with: [0x00, 0x00, 0xFE, 0xFF])
            || leadingBytes.starts(with: [0x00, 0x00, 0x00, 0x3C]) {
            return (4, false, .utf32BigEndian)
        }
        if leadingBytes.starts(with: [0xFF, 0xFE, 0x00, 0x00])
            || leadingBytes.starts(with: [0x3C, 0x00, 0x00, 0x00]) {
            return (4, true, .utf32LittleEndian)
        }
        if leadingBytes.starts(with: [0xFE, 0xFF])
            || leadingBytes.starts(with: [0x00, 0x3C]) {
            return (2, false, .utf16BigEndian)
        }
        if leadingBytes.starts(with: [0xFF, 0xFE])
            || leadingBytes.starts(with: [0x3C, 0x00]) {
            return (2, true, .utf16LittleEndian)
        }
        return (1, true, nil)
    }

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
}
