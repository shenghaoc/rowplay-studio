import Foundation
import Synchronization

/// Calendar and date helpers for Concept2 logbook timestamps.
///
/// Concept2 logbook dates are wall-clock strings in the format `YYYY-MM-DD HH:MM:SS`
/// with no timezone offset. The web app interprets them as UTC (`LOGBOOK_ZONE = "UTC"`);
/// this module does the same.
public enum RowPlayDateTime: Sendable {
    private struct LogbookParts {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Int
    }

    private static let utc = TimeZone(secondsFromGMT: 0)!
    private static let maxRawLogbookUTF16Length = 64
    private static let maxTrimmedLogbookUTF16Length = 30
    private static let maxRawDayKeyUTF16Length = 64
    private static let maxTrimmedDayKeyUTF16Length = 20

    private static let logbookRegex = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$"#
    )
    private static let dayKeyRegex = try! NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})$"#
    )

    // MARK: - Formatters

    private static let dayKeyFormatter = Mutex({
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = utc
        f.locale = Locale(identifier: "en_US_POSIX")
        f.isLenient = false
        return f
    }())

    private static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()

    // MARK: - Parsing

    /// Parse a Concept2 logbook timestamp (`YYYY-MM-DD HH:MM:SS`) to a `Date`.
    /// Returns `nil` when the string does not match the expected format.
    public static func parseLogbookDateTime(_ text: String) -> Date? {
        guard let parts = parseLogbookParts(text) else { return nil }
        return date(from: parts, timeZone: utc)
    }

    /// Epoch milliseconds for sorting; logbook wall times interpreted as UTC.
    /// Returns `NaN` when the string cannot be parsed.
    public static func logbookEpochMillis(_ text: String) -> Double {
        guard let date = parseLogbookDateTime(text) else { return .nan }
        return date.timeIntervalSince1970 * 1_000
    }

    // MARK: - Day Key Helpers

    /// Convert a `Date` to a `YYYY-MM-DD` string in UTC.
    public static func dayKeyFromDate(_ date: Date) -> String {
        dayKeyFormatter.withLock { $0.string(from: date) }
    }

    /// Today as `YYYY-MM-DD` in UTC.
    public static func todayKeyUTC() -> String {
        dayKeyFromDate(Date())
    }

    /// `YYYY-MM-DD` day key to UTC-midnight epoch milliseconds. `NaN` if unparseable.
    public static func dayKeyEpochMillis(_ key: String) -> Double {
        guard let date = parseDayKey(key) else { return .nan }
        return date.timeIntervalSince1970 * 1_000
    }

    /// Add `days` calendar days to a `YYYY-MM-DD` key.
    /// Returns the original key if it cannot be parsed.
    public static func dayKeyAddingDays(_ days: Int, to key: String) -> String {
        guard let date = parseDayKey(key) else { return key }
        guard let result = gregorian.date(byAdding: .day, value: days, to: date) else { return key }
        return dayKeyFormatter.withLock { $0.string(from: result) }
    }

    /// Non-negative calendar day count between two `YYYY-MM-DD` keys.
    /// Returns 0 if either key cannot be parsed or if `from` is after `to`.
    public static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let fromDate = parseDayKey(from),
              let toDate = parseDayKey(to) else { return 0 }
        return max(0, gregorian.dateComponents([.day], from: fromDate, to: toDate).day ?? 0)
    }

    /// Day of week from a `YYYY-MM-DD` key. Returns 0=Sun, 1=Mon, ..., 6=Sat.
    ///
    /// Matches the web app's `dayOfWeekUtc` which returns `day.dayOfWeek % 7`
    /// (Temporal `dayOfWeek` is 1=Mon..7=Sun, so `% 7` maps 7→0 for Sunday).
    public static func dayOfWeek(_ key: String) -> Int {
        guard let date = parseDayKey(key) else { return 0 }
        // Calendar.component(.weekday) returns 1=Sun..7=Sat
        return gregorian.component(.weekday, from: date) - 1
    }

    /// Day of year (1-based) from a `YYYY-MM-DD` key.
    public static func dayOfYear(_ key: String) -> Int {
        guard let date = parseDayKey(key) else { return 0 }
        return gregorian.ordinality(of: .day, in: .year, for: date) ?? 0
    }

    /// Calendar day key for a workout, resolving timezone differences.
    ///
    /// The Concept2 `date` is monitor-local. When `workoutTz` is known, the date string
    /// is taken as being in that zone. Cross-zone conversion is only applied when
    /// `homeTz` differs from `workoutTz`. With no zone, the plain date part is used as-is.
    public static func workoutLocalDayKey(
        _ date: String,
        workoutTz: String? = nil,
        homeTz: String? = nil
    ) -> String {
        let cleanWtz = workoutTz?.trimmingCharacters(in: .whitespaces)
        let cleanHtz = homeTz?.trimmingCharacters(in: .whitespaces)

        guard cleanWtz != nil || cleanHtz != nil else {
            return String(date.prefix(10))
        }

        guard let parts = parseLogbookParts(date) else {
            return String(date.prefix(10))
        }

        if let wtz = cleanWtz, !wtz.isEmpty, let tz = TimeZone(identifier: wtz) {
            if let htz = cleanHtz, !htz.isEmpty, htz != wtz, let home = TimeZone(identifier: htz) {
                guard let instant = self.date(from: parts, timeZone: tz) else {
                    return plainDayKey(from: parts)
                }
                return dayKey(for: instant, in: home)
            }
            return plainDayKey(from: parts)
        }

        return plainDayKey(from: parts)
    }

    // MARK: - ISO Helpers

    /// Thread-safe ISO-8601 formatter.
    private static let iso8601Formatter = Mutex({
        let formatter = ISO8601DateFormatter()
        // ISO8601DateFormatter defaults to GMT, which matches Date.ISO8601FormatStyle() behavior
        return formatter
    }())

    /// Current instant as an ISO-8601 string.
    public static func nowISOString() -> String {
        iso8601Formatter.withLock { $0.string(from: Date()) }
    }

    // MARK: - Private

    private static func parseLogbookParts(_ text: String) -> LogbookParts? {
        guard text.utf16.count <= maxRawLogbookUTF16Length else { return nil }

        let value = text.trimmingCharacters(in: .whitespaces)

        // Bound regex input; utf16.count matches NSRegularExpression's UTF-16 basis.
        guard value.utf16.count <= maxTrimmedLogbookUTF16Length else { return nil }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = logbookRegex.firstMatch(in: value, range: range) else {
            return nil
        }

        let values = (1...6).compactMap { index -> Int? in
            guard let swiftRange = Range(match.range(at: index), in: value) else { return nil }
            return Int(value[swiftRange])
        }
        guard values.count == 6 else { return nil }

        let parts = LogbookParts(
            year: values[0],
            month: values[1],
            day: values[2],
            hour: values[3],
            minute: values[4],
            second: values[5]
        )
        guard date(from: parts, timeZone: utc) != nil else { return nil }
        return parts
    }

    private static func parseDayKey(_ key: String) -> Date? {
        guard key.utf16.count <= maxRawDayKeyUTF16Length else { return nil }

        let value = key.trimmingCharacters(in: .whitespaces)

        // Bound regex input; utf16.count matches NSRegularExpression's UTF-16 basis.
        guard value.utf16.count <= maxTrimmedDayKeyUTF16Length else { return nil }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = dayKeyRegex.firstMatch(in: value, range: range) else { return nil }

        let values = (1...3).compactMap { index -> Int? in
            guard let swiftRange = Range(match.range(at: index), in: value) else { return nil }
            return Int(value[swiftRange])
        }
        guard values.count == 3 else { return nil }

        let parts = LogbookParts(
            year: values[0],
            month: values[1],
            day: values[2],
            hour: 0,
            minute: 0,
            second: 0
        )
        return date(from: parts, timeZone: utc)
    }

    private static func date(from parts: LogbookParts, timeZone: TimeZone) -> Date? {
        var calendar = gregorian
        calendar.timeZone = timeZone

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = parts.hour
        components.minute = parts.minute
        components.second = parts.second

        guard components.isValidDate(in: calendar),
              let date = components.date else {
            return nil
        }

        let roundTrip = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard roundTrip.year == parts.year,
              roundTrip.month == parts.month,
              roundTrip.day == parts.day,
              roundTrip.hour == parts.hour,
              roundTrip.minute == parts.minute,
              roundTrip.second == parts.second else {
            return nil
        }

        return date
    }

    private static func plainDayKey(from parts: LogbookParts) -> String {
        String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day)
    }

    private static func dayKey(for date: Date, in timeZone: TimeZone) -> String {
        var calendar = gregorian
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return dayKeyFromDate(date)
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
