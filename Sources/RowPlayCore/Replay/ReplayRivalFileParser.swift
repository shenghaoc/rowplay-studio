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

/// Portable, dependency-free CSV / TCX / FIT facade for replay rivals.
///
/// Format-specific decoding lives in focused helpers; this type owns the public
/// API, bounded dispatch, and common trace normalization.
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

    /// Parse rival file data using extension hints plus plausible content
    /// detection. Content detection still works when a valid FIT or TCX file has
    /// been given a misleading text extension.
    public static func parse(data: Data, fileName: String) throws -> ParsedTrace {
        try checkReplayImportCancellation()
        guard data.count <= maximumFileSizeBytes else {
            throw ReplayRivalFileParserError.fileTooLarge
        }

        // Normalize sliced `Data` so format decoders can use zero-based offsets.
        let data = data.startIndex == 0 ? data : Data(data)
        let lastComponent = ReplayPathUtilities.lastPathComponent(fileName)
        let fileExtension = (lastComponent as NSString).pathExtension.lowercased()

        // A recognized payload is stronger evidence than a filename hint. This
        // preserves imports when Finder or an upstream exporter gives a valid
        // FIT/TCX trace the wrong known extension.
        let raw: [RawRivalSample]
        if ReplayRivalFITParser.hasPlausibleSignature(data) {
            raw = try ReplayRivalFITParser.parse(data, sampleLimit: maximumAcceptedSamples)
        } else if try ReplayRivalTCXParser.looksLikeTCX(data) {
            raw = try ReplayRivalTCXParser.parse(data, sampleLimit: maximumAcceptedSamples)
        } else if fileExtension == "fit" {
            raw = try ReplayRivalFITParser.parse(data, sampleLimit: maximumAcceptedSamples)
        } else if fileExtension == "tcx" {
            raw = try ReplayRivalTCXParser.parse(data, sampleLimit: maximumAcceptedSamples)
        } else {
            raw = try ReplayRivalCSVParser.parse(data: data, sampleLimit: maximumAcceptedSamples)
        }

        try checkReplayImportCancellation()
        let strokes = try finalize(raw)
        return ParsedTrace(strokes: strokes, fileName: lastComponent)
    }

    // MARK: - Common normalization

    private static func finalize(_ raw: [RawRivalSample]) throws -> [Stroke] {
        var points: [(offset: Int, element: RawRivalSample)] = []
        points.reserveCapacity(raw.count)
        for (offset, sample) in raw.enumerated() {
            if offset.isMultiple(of: 4_096) {
                try checkReplayImportCancellation()
            }
            if sample.t.isFinite && sample.d.isFinite && sample.d >= 0 && sample.t >= 0 {
                points.append((offset: offset, element: sample))
            }
        }

        var comparisonCount = 0
        try points.sort { lhs, rhs in
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
        cleaned.reserveCapacity(min(points.count, maximumAcceptedSamples + 1))
        for (index, point) in points.enumerated() {
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

        guard !cleaned.isEmpty else {
            throw ReplayRivalFileParserError.unsupportedOrEmpty
        }
        guard cleaned.count >= 2 else {
            throw ReplayRivalFileParserError.tooFewSamples
        }

        let firstTime = cleaned[0].t
        var output: [Stroke] = []
        output.reserveCapacity(cleaned.count)

        for index in 0..<cleaned.count {
            if index.isMultiple(of: 4_096) {
                try checkReplayImportCancellation()
            }
            let sample = cleaned[index]
            let time = sample.t - firstTime
            guard time.isFinite, time >= 0 else { continue }

            let resolvedPace: TimeInterval
            if let pace = sample.pace, pace.isFinite, pace > 0 {
                resolvedPace = pace
            } else if index > 0 {
                let previous = cleaned[index - 1]
                let distanceDelta = sample.d - previous.d
                let timeDelta = sample.t - previous.t
                if distanceDelta > 0, timeDelta > 0 {
                    resolvedPace = timeDelta / (distanceDelta / 500.0)
                } else if let last = output.last {
                    resolvedPace = last.pace
                } else {
                    resolvedPace = 0
                }
            } else {
                resolvedPace = 0
            }

            let safePace = resolvedPace.isFinite && resolvedPace >= 0 ? resolvedPace : 0
            let watts: Int
            if let value = sample.watts,
               let importedWatts = checkedPositiveRoundedInt(value) {
                watts = importedWatts
            } else {
                let derived = RowPlayFormatting.paceToWatts(safePace)
                watts = checkedPositiveRoundedInt(derived) ?? 0
            }

            let cadence = sample.spm.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
            let heartRate = sample.hr.flatMap { $0 > 0 ? $0 : nil }
            output.append(Stroke(
                t: time,
                d: sample.d,
                pace: safePace,
                cadence: cadence,
                heartRate: heartRate,
                watts: watts
            ))
        }

        if output.count > maximumAcceptedSamples {
            throw ReplayRivalFileParserError.tooManySamples
        }
        guard !output.isEmpty else {
            throw ReplayRivalFileParserError.unsupportedOrEmpty
        }
        guard output.count >= 2 else {
            throw ReplayRivalFileParserError.tooFewSamples
        }
        return output
    }
}
