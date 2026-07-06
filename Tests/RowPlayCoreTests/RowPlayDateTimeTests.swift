import XCTest
@testable import RowPlayCore

final class RowPlayDateTimeTests: XCTestCase {
    // MARK: - parseLogbookDateTime

    func testParseLogbookDateTimeValidTimestamp() {
        let date = RowPlayDateTime.parseLogbookDateTime("2026-05-27 06:12:00")
        XCTAssertNotNil(date)
        let millis = date!.timeIntervalSince1970 * 1000
        // 2026-05-27T06:12:00Z
        XCTAssertEqual(millis, 1_779_862_320_000, accuracy: 1000)
    }

    func testParseLogbookDateTimeWithTSeparator() {
        let date = RowPlayDateTime.parseLogbookDateTime("2026-01-15T12:00:00")
        XCTAssertNotNil(date)
    }

    func testParseLogbookDateTimeInvalidString() {
        XCTAssertNil(RowPlayDateTime.parseLogbookDateTime("not a date"))
        XCTAssertNil(RowPlayDateTime.parseLogbookDateTime(""))
        XCTAssertNil(RowPlayDateTime.parseLogbookDateTime("2026-13-01 00:00:00"))
        XCTAssertNil(RowPlayDateTime.parseLogbookDateTime("2026-01-01 25:00:00"))
    }

    func testParseLogbookDateTimeTrimsWhitespace() {
        let date = RowPlayDateTime.parseLogbookDateTime("  2026-05-27 06:12:00  ")
        XCTAssertNotNil(date)
    }

    func testParseLogbookDateTimeRejectsLongRawInputBeforeTrimming() {
        let padded = String(repeating: " ", count: 1_000) + "2026-05-27 06:12:00"
        XCTAssertNil(RowPlayDateTime.parseLogbookDateTime(padded))
    }

    // MARK: - logbookEpochMillis

    func testLogbookEpochMillisReturnsFiniteValue() {
        let ms = RowPlayDateTime.logbookEpochMillis("2026-05-27 06:12:00")
        XCTAssertTrue(ms.isFinite)
        XCTAssertGreaterThan(ms, 0)
    }

    func testLogbookEpochMillisReturnsNaNForInvalid() {
        let ms = RowPlayDateTime.logbookEpochMillis("garbage")
        XCTAssertTrue(ms.isNaN)
    }

    // MARK: - dayKeyFromDate

    func testDayKeyFromDateUTC() {
        // 2026-05-27T00:00:00Z
        let date = Date(timeIntervalSince1970: 1_779_840_000)
        XCTAssertEqual(RowPlayDateTime.dayKeyFromDate(date), "2026-05-27")
    }

    // MARK: - dayKeyAddingDays

    func testDayKeyAddingDaysForward() {
        XCTAssertEqual(RowPlayDateTime.dayKeyAddingDays(1, to: "2026-05-27"), "2026-05-28")
    }

    func testDayKeyAddingDaysBackward() {
        XCTAssertEqual(RowPlayDateTime.dayKeyAddingDays(-1, to: "2026-05-01"), "2026-04-30")
    }

    func testDayKeyAddingDaysMonthBoundary() {
        XCTAssertEqual(RowPlayDateTime.dayKeyAddingDays(1, to: "2026-01-31"), "2026-02-01")
    }

    func testDayKeyAddingDaysInvalidKeyReturnsOriginal() {
        XCTAssertEqual(RowPlayDateTime.dayKeyAddingDays(1, to: "not-a-date"), "not-a-date")
    }

    // MARK: - daysBetween

    func testDaysBetweenSameDay() {
        XCTAssertEqual(RowPlayDateTime.daysBetween("2026-05-27", "2026-05-27"), 0)
    }

    func testDaysBetweenConsecutiveDays() {
        XCTAssertEqual(RowPlayDateTime.daysBetween("2026-05-27", "2026-05-28"), 1)
    }

    func testDaysBetweenReversedReturnsZero() {
        XCTAssertEqual(RowPlayDateTime.daysBetween("2026-05-28", "2026-05-27"), 0)
    }

    func testDaysBetweenAcrossMonths() {
        XCTAssertEqual(RowPlayDateTime.daysBetween("2026-05-30", "2026-06-02"), 3)
    }

    func testDaysBetweenInvalidKeysReturnsZero() {
        XCTAssertEqual(RowPlayDateTime.daysBetween("bad", "2026-05-27"), 0)
    }

    // MARK: - dayOfWeek

    func testDayOfWeekKnownDate() {
        // 2026-05-27 is a Wednesday → 3 (0=Sun)
        XCTAssertEqual(RowPlayDateTime.dayOfWeek("2026-05-27"), 3)
    }

    func testDayOfWeekSunday() {
        // 2026-05-24 is a Sunday → 0
        XCTAssertEqual(RowPlayDateTime.dayOfWeek("2026-05-24"), 0)
    }

    func testDayOfWeekSaturday() {
        // 2026-05-23 is a Saturday → 6
        XCTAssertEqual(RowPlayDateTime.dayOfWeek("2026-05-23"), 6)
    }

    func testDayOfWeekInvalidReturnsZero() {
        XCTAssertEqual(RowPlayDateTime.dayOfWeek("not-a-date"), 0)
    }

    // MARK: - dayOfYear

    func testDayOfYearJanuary1() {
        XCTAssertEqual(RowPlayDateTime.dayOfYear("2026-01-01"), 1)
    }

    func testDayOfYearKnownDate() {
        // 2026-05-27 is day 147
        XCTAssertEqual(RowPlayDateTime.dayOfYear("2026-05-27"), 147)
    }

    func testDayOfYearInvalidReturnsZero() {
        XCTAssertEqual(RowPlayDateTime.dayOfYear("bad"), 0)
    }

    // MARK: - dayKeyEpochMillis

    func testDayKeyEpochMillisReturnsFinite() {
        let ms = RowPlayDateTime.dayKeyEpochMillis("2026-05-27")
        XCTAssertTrue(ms.isFinite)
        XCTAssertGreaterThan(ms, 0)
    }

    func testDayKeyEpochMillisInvalidReturnsNaN() {
        XCTAssertTrue(RowPlayDateTime.dayKeyEpochMillis("bad").isNaN)
    }

    func testDayKeyEpochMillisRejectsLongRawInputBeforeTrimming() {
        let padded = String(repeating: " ", count: 1_000) + "2026-05-27"
        XCTAssertTrue(RowPlayDateTime.dayKeyEpochMillis(padded).isNaN)
    }

    // MARK: - workoutLocalDayKey

    func testWorkoutLocalDayKeyNoTimezone() {
        XCTAssertEqual(RowPlayDateTime.workoutLocalDayKey("2026-05-27 06:12:00"), "2026-05-27")
    }

    func testWorkoutLocalDayKeyWithWorkoutTz() {
        // With only workoutTz, the monitor-local plain date is preserved.
        let result = RowPlayDateTime.workoutLocalDayKey("2026-05-27 00:30:00", workoutTz: "America/Los_Angeles")
        XCTAssertEqual(result, "2026-05-27")
    }

    func testWorkoutLocalDayKeyCrossTimezone() {
        // 2026-05-27 00:30:00 UTC → in Asia/Tokyo (UTC+9) that's 09:30 on 2026-05-27
        let result = RowPlayDateTime.workoutLocalDayKey("2026-05-27 00:30:00", workoutTz: "UTC", homeTz: "Asia/Tokyo")
        XCTAssertEqual(result, "2026-05-27")
    }

    func testWorkoutLocalDayKeyWithDifferentHomeTz() {
        // 2026-05-27 01:00:00 UTC → in US/Pacific (UTC-7) that's 2026-05-26 18:00
        let result = RowPlayDateTime.workoutLocalDayKey("2026-05-27 01:00:00", workoutTz: "UTC", homeTz: "America/Los_Angeles")
        XCTAssertEqual(result, "2026-05-26")
    }

    // MARK: - todayKeyUTC

    func testTodayKeyUTCReturnsValidFormat() {
        let key = RowPlayDateTime.todayKeyUTC()
        XCTAssertEqual(key.count, 10)
        XCTAssertTrue(key.contains("-"))
    }

    // MARK: - nowISOString

    func testNowISOStringReturnsISOFormat() {
        let iso = RowPlayDateTime.nowISOString()
        // Full ISO 8601 internet date-time: yyyy-MM-dd'T'HH:mm:ss'Z'
        XCTAssertEqual(iso.count, 20)
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#
        XCTAssertNotNil(iso.range(of: pattern, options: .regularExpression))
    }
}
