import Foundation
import Synchronization

public enum WorkoutExport: Sendable {
    private static let exportSchemaVersion = 1

    /// CSV column order (stable, matches web export).
    static let csvHeaders = [
        "id", "date", "sport", "distance_m", "time_s", "pace_s_per_500m",
        "stroke_rate", "stroke_count", "heart_rate_avg", "hr_min", "hr_max",
        "calories", "watt_minutes", "drag_factor", "workout_type", "comments",
        "has_stroke_data",
    ]

    // MARK: - Formatters (Performance Optimization)
    // Instantiating DateFormatter is expensive. Reuse static instances, but
    // guard access with Mutex because DateFormatter is mutable and non-Sendable.

    /// Activity / lap timestamps: second-precision UTC ISO-8601.
    private static let tcxISO8601Formatter = Mutex({
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }())

    /// Trackpoint timestamps: fractional-second UTC ISO-8601.
    private static let tcxISO8601FractionalFormatter = Mutex({
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }())

    private static let filenameDateFormatter = Mutex({
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }())

    private static let logbookDateFormatter = Mutex({
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }())

    // MARK: - CSV Export

    /// Full logbook export as CSV (one row per workout).
    public static func csv(_ workouts: [Workout]) -> String {
        var lines = [csvHeaders.joined(separator: ",")]
        for w in workouts {
            let row = [
                csvCell(w.id),
                csvCell(logbookDateString(from: w.date)),
                csvCell(w.sport.rawValue),
                csvCell(w.distance),
                csvCell(w.time),
                csvCell(w.pace),
                csvCell(w.strokeRate),
                csvCell(w.strokeCount),
                csvCell(w.heartRateAvg),
                csvCell(nil as Int?),    // hr_min — not on native Workout yet
                csvCell(nil as Int?),    // hr_max — not on native Workout yet
                csvCell(w.caloriesTotal),
                csvCell(w.wattMinutes),
                csvCell(w.dragFactor),
                csvCell(w.workoutType.isEmpty ? nil : w.workoutType),
                csvCell(w.comments),
                csvCell(w.hasStrokeData ? 1 : 0),
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - JSON Export

    /// Full logbook export as JSON with schema metadata.
    public static func json(_ workouts: [Workout]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let payload = ExportPayload(
            schema: "rowplay-logbook-export",
            version: exportSchemaVersion,
            exportedAt: Date(),
            workoutCount: workouts.count,
            workouts: workouts.map { ExportWorkout(from: $0) }
        )

        guard let data = try? encoder.encode(payload) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - TCX Export

    private static let tcxXmlDecl = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    private static let tcxNS = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
    private static let xsiNS = "http://www.w3.org/2001/XMLSchema-instance"
    private static let tcxSchemaLocation =
        "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 " +
        "http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd"

    /// Export a single workout detail as Garmin Training Center Database v2 XML.
    public static func tcx(_ detail: WorkoutDetail) -> String {
        let w = detail.workout
        let sportAttr: String = w.sport == .bike ? "Biking" : "Other"
        let activityId = tcxISO8601Formatter.withLock { $0.string(from: w.date) }
        let calories = min(max(w.caloriesTotal ?? 0, 0), Int(UInt16.max))

        // Guard against non-finite workout summary values
        let safeTime = w.time.isFinite && w.time >= 0 ? w.time : 0
        let safeDistance = w.distance.isFinite && w.distance >= 0 ? w.distance : 0

        var xml = [String]()
        xml.append(tcxXmlDecl)
        xml.append("<TrainingCenterDatabase xmlns=\"\(tcxNS)\" xmlns:xsi=\"\(xsiNS)\" xsi:schemaLocation=\"\(tcxSchemaLocation)\">")
        xml.append("  <Activities>")
        xml.append("    <Activity Sport=\"\(sportAttr)\">")
        xml.append("      <Id>\(activityId)</Id>")

        // Lap
        xml.append("      <Lap StartTime=\"\(activityId)\">")
        xml.append("        <TotalTimeSeconds>\(formatDecimal(safeTime))</TotalTimeSeconds>")
        xml.append("        <DistanceMeters>\(formatDecimal(safeDistance))</DistanceMeters>")
        xml.append("        <Calories>\(formatInt(calories))</Calories>")
        if let avgHR = w.heartRateAvg, (1...255).contains(avgHR) {
            xml.append("        <AverageHeartRateBpm><Value>\(formatInt(avgHR))</Value></AverageHeartRateBpm>")
        }
        xml.append("        <Intensity>Active</Intensity>")
        xml.append("        <TriggerMethod>Manual</TriggerMethod>")

        // Track (only when valid strokes exist)
        let validStrokes = filterAndBuildTrackpoints(detail: detail)
        if !validStrokes.isEmpty {
            xml.append("        <Track>")
            for tp in validStrokes {
                xml.append("          <Trackpoint>")
                xml.append("            <Time>\(tp.time)</Time>")
                xml.append("            <DistanceMeters>\(tp.distance)</DistanceMeters>")
                if let hr = tp.heartRate {
                    xml.append("            <HeartRateBpm><Value>\(hr)</Value></HeartRateBpm>")
                }
                if let cadence = tp.cadence {
                    xml.append("            <Cadence>\(cadence)</Cadence>")
                }
                xml.append("          </Trackpoint>")
            }
            xml.append("        </Track>")
        }

        xml.append("      </Lap>")
        xml.append("    </Activity>")
        xml.append("  </Activities>")
        xml.append("</TrainingCenterDatabase>")

        return xml.joined(separator: "\n") + "\n"
    }

    // MARK: - TCX Helpers

    private struct TrackpointData {
        let time: String
        let distance: String
        let heartRate: Int?
        let cadence: Int?
    }

    /// Filter strokes for TCX export: validate, clamp, deduplicate, sort.
    private static func filterAndBuildTrackpoints(
        detail: WorkoutDetail
    ) -> [TrackpointData] {
        let w = detail.workout
        let workoutDuration = w.time
        let workoutDistance = w.distance
        guard workoutDuration.isFinite, workoutDuration > 0,
              workoutDistance.isFinite, workoutDistance > 0 else { return [] }

        var seenOffsets = Set<TimeInterval>()
        var result = [TrackpointData]()

        let sortedStrokes = detail.strokes.sorted { $0.t < $1.t }

        for stroke in sortedStrokes {
            // Reject non-finite or negative timestamps
            guard stroke.t.isFinite, stroke.t >= 0 else { continue }
            // Reject non-finite or negative distances
            guard stroke.d.isFinite, stroke.d >= 0 else { continue }

            // Skip strokes beyond workout duration
            guard stroke.t <= workoutDuration else { continue }

            let absoluteDate = w.date.addingTimeInterval(stroke.t)
            let timeString = tcxISO8601FractionalFormatter.withLock { $0.string(from: absoluteDate) }

            // Deduplicate identical source timestamps without collapsing distinct
            // sub-second samples that happen within the same wall-clock second.
            guard seenOffsets.insert(stroke.t).inserted else { continue }

            // Clamp distance to workout distance
            let clampedDistance = min(stroke.d, workoutDistance)
            let distanceString = formatDecimal(clampedDistance)

            // Heart rate: only 1...255
            var hr: Int? = nil
            if let rawHR = stroke.heartRate, rawHR >= 1, rawHR <= 255 {
                hr = rawHR
            }

            // Cadence: finite, non-negative, rounded and clamped to the
            // TCX CadenceValue_t range 0...254 before converting to Int.
            var cadence: Int? = nil
            if stroke.cadence.isFinite, stroke.cadence >= 0 {
                cadence = Int(min(stroke.cadence.rounded(), 254))
            }

            result.append(TrackpointData(
                time: timeString,
                distance: distanceString,
                heartRate: hr,
                cadence: cadence
            ))
        }

        return result
    }

    /// Locale-independent integer formatting.
    private static func formatInt(_ value: Int) -> String {
        String(format: "%d", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Locale-independent decimal formatting (dot separator).
    private static func formatDecimal(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    // MARK: - Filenames

    /// Generate a stable export filename.
    public static func exportFilename(ext: String) -> String {
        let dateKey = filenameDateFormatter.withLock { $0.string(from: Date()) }
        return "rowplay-logbook-\(dateKey).\(ext)"
    }

    /// Generate a stable per-workout export filename.
    public static func workoutExportFilename(id: Int, ext: String) -> String {
        "rowplay-workout-\(id).\(ext)"
    }

    /// Concept2 logbook timestamp string (`YYYY-MM-DD HH:MM:SS`) interpreted in UTC.
    static func logbookDateString(from date: Date) -> String {
        logbookDateFormatter.withLock { $0.string(from: date) }
    }

    // MARK: - CSV Cell Escaping (RFC 4180 + formula injection protection)

    /// Escape a CSV cell value. Handles nil, numbers, booleans, and strings.
    static func csvCell<T>(_ value: T?) -> String {
        guard let value else { return "" }
        var s = String(describing: value)

        // Formula injection protection: strip leading whitespace and newlines that might bypass
        // checks, then prefix formula-triggering characters with a single quote (OWASP recommendation).
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let formulaChars: [Character] = ["=", "+", "-", "@"]
        let startsWithControlCharacter = s.unicodeScalars.first.map {
            $0 == "\t" || $0 == "\r" || $0 == "\n"
        } ?? false
        let startsWithFormulaCharacter = trimmed.first.map(formulaChars.contains) ?? false
        if startsWithControlCharacter || startsWithFormulaCharacter {
            s = "'" + s
        }

        // RFC 4180 escaping. Use unicodeScalars to detect CR/LF because Swift treats
        // CRLF (\r\n) as a single grapheme cluster, causing String.contains to miss them.
        let needsQuoting = s.contains("\"") || s.contains(",")
            || s.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" })
        if needsQuoting {
            s = "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}

// MARK: - Export Codable Models

private struct ExportPayload: Encodable {
    let schema: String
    let version: Int
    let exportedAt: Date
    let workoutCount: Int
    let workouts: [ExportWorkout]
}

private struct ExportWorkout: Encodable {
    let id: Int
    let date: String
    let sport: String
    let distance: Double
    let time: Double
    let pace: Double
    let strokeRate: Double?
    let strokeCount: Int?
    let heartRateAvg: Int?
    let hrMin: Int?
    let hrMax: Int?
    let caloriesTotal: Int?
    let wattMinutes: Double?
    let dragFactor: Int?
    let workoutType: String
    let comments: String?
    let hasStrokeData: Bool

    init(from w: Workout) {
        self.id = w.id
        self.date = WorkoutExport.logbookDateString(from: w.date)
        self.sport = w.sport.rawValue
        self.distance = w.distance
        self.time = w.time
        self.pace = w.pace
        self.strokeRate = w.strokeRate
        self.strokeCount = w.strokeCount
        self.heartRateAvg = w.heartRateAvg
        self.hrMin = nil  // not on native Workout yet
        self.hrMax = nil  // not on native Workout yet
        self.caloriesTotal = w.caloriesTotal
        self.wattMinutes = w.wattMinutes
        self.dragFactor = w.dragFactor
        self.workoutType = w.workoutType
        self.comments = w.comments
        self.hasStrokeData = w.hasStrokeData
    }
}
