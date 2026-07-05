import Foundation

public enum WorkoutExport {
    private static let exportSchemaVersion = 1

    /// CSV column order (stable, matches web export).
    static let csvHeaders = [
        "id", "date", "sport", "distance_m", "time_s", "pace_s_per_500m",
        "stroke_rate", "stroke_count", "heart_rate_avg", "hr_min", "hr_max",
        "calories", "watt_minutes", "drag_factor", "workout_type", "comments",
        "has_stroke_data",
    ]

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

    // MARK: - Filenames

    /// Generate a stable export filename.
    public static func exportFilename(ext: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let dateKey = formatter.string(from: Date())
        return "rowplay-logbook-\(dateKey).\(ext)"
    }

    /// Generate a stable per-workout export filename.
    public static func workoutExportFilename(id: Int, ext: String) -> String {
        "rowplay-workout-\(id).\(ext)"
    }

    /// Concept2 logbook timestamp string (`YYYY-MM-DD HH:MM:SS`) interpreted in UTC.
    static func logbookDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // MARK: - CSV Cell Escaping (RFC 4180 + formula injection protection)

    /// Escape a CSV cell value. Handles nil, numbers, booleans, and strings.
    static func csvCell<T>(_ value: T?) -> String {
        guard let value else { return "" }
        var s = String(describing: value)

        // Formula injection protection: strip leading whitespace that might bypass checks,
        // then prefix formula-triggering characters with a single quote (OWASP recommendation).
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let formulaChars: [Character] = ["=", "+", "-", "@", "\t", "\r", "\n"]
        if let first = trimmed.first, formulaChars.contains(first) {
            s = "'" + s
        }

        // RFC 4180 escaping
        if s.contains("\"") || s.contains(",") || s.contains("\n") || s.contains("\r") {
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
