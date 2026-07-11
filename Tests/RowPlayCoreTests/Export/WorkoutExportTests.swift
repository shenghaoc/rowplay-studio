import XCTest
@testable import RowPlayCore

final class WorkoutExportTests: XCTestCase {

    private func makeWorkout(
        id: Int = 1,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        sport: Sport = .rower,
        distance: Double = 2000,
        time: TimeInterval = 480,
        pace: TimeInterval = 120,
        workoutType: String = "fixed_distance"
    ) -> Workout {
        Workout(
            id: id,
            date: date,
            sport: sport,
            distance: distance,
            time: time,
            pace: pace,
            workoutType: workoutType,
            hasStrokeData: true
        )
    }

    // MARK: - CSV

    func testCsvHeaders() {
        let csv = WorkoutExport.csv([])
        let firstLine = csv.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(firstLine.hasPrefix("id,date,sport,distance_m,time_s"))
    }

    func testCsvSingleWorkout() {
        let w = makeWorkout(distance: 2000, time: 480, pace: 120)
        let csv = WorkoutExport.csv([w])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2) // header + 1 row
        let row = lines[1]
        XCTAssertTrue(row.contains("rower"))
        XCTAssertTrue(row.contains("2000"))
        XCTAssertTrue(row.contains("480"))
    }

    func testCsvUsesLogbookDateFormat() {
        let w = makeWorkout(date: Date(timeIntervalSince1970: 1_700_000_000))
        let csv = WorkoutExport.csv([w])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertTrue(lines[1].contains("2023-11-14 22:13:20"))
        XCTAssertFalse(lines[1].contains("22:13:20Z"))
    }

    func testCsvMultipleWorkouts() {
        let workouts = [
            makeWorkout(id: 1),
            makeWorkout(id: 2, sport: .bike),
            makeWorkout(id: 3, sport: .skierg),
        ]
        let csv = WorkoutExport.csv(workouts)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 4) // header + 3 rows
    }

    // MARK: - JSON

    func testJsonContainsSchema() {
        let json = WorkoutExport.json([makeWorkout()])
        XCTAssertTrue(json.contains("rowplay-logbook-export"))
        XCTAssertTrue(json.contains("\"version\" : 1"))
        XCTAssertTrue(json.contains("\"workoutCount\" : 1"))
    }

    func testJsonUsesLogbookDateFormatForWorkoutDate() {
        let json = WorkoutExport.json([makeWorkout(date: Date(timeIntervalSince1970: 1_700_000_000))])
        XCTAssertTrue(json.contains("\"date\" : \"2023-11-14 22:13:20\""))
        XCTAssertFalse(json.contains("\"date\" : \"2023-11-14T22:13:20Z\""))
    }

    func testJsonEmpty() {
        let json = WorkoutExport.json([])
        XCTAssertTrue(json.contains("\"workoutCount\" : 0"))
    }

    // MARK: - CSV Cell Escaping

    func testCsvCellEscapesCommas() {
        XCTAssertEqual(WorkoutExport.csvCell("hello, world"), "\"hello, world\"")
    }

    func testCsvCellEscapesQuotes() {
        XCTAssertEqual(WorkoutExport.csvCell("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testCsvCellEscapesNewlines() {
        XCTAssertEqual(WorkoutExport.csvCell("line1\nline2"), "\"line1\nline2\"")
    }

    func testCsvCellProtectsFormulaInjection() {
        let result = WorkoutExport.csvCell("=cmd")
        XCTAssertEqual(result, "'=cmd")
    }

    func testCsvCellProtectsAtSign() {
        let result = WorkoutExport.csvCell("@SUM(A1)")
        XCTAssertEqual(result, "'@SUM(A1)")
    }

    func testCsvCellProtectsLeadingWhitespaceBypass() {
        let result = WorkoutExport.csvCell(" =cmd")
        XCTAssertEqual(result, "' =cmd")
    }

    func testCsvCellProtectsLineFeedPrefix() {
        let result = WorkoutExport.csvCell("\n=HYPERLINK(\"http://evil.com\")")
        // LF triggers both formula prefix ('), and RFC 4180 quoting (wraps in "")
        XCTAssertEqual(result, "\"'\n=HYPERLINK(\"\"http://evil.com\"\")\"")
    }

    func testCsvCellProtectsCarriageReturnPrefix() {
        let result = WorkoutExport.csvCell("\r=cmd")
        // CR triggers both formula prefix ('), and RFC 4180 quoting (wraps in "")
        XCTAssertEqual(result, "\"'\r=cmd\"")
    }

    func testCsvCellProtectsTabPrefix() {
        let result = WorkoutExport.csvCell("\t=cmd")
        // Tab is stripped by .whitespacesAndNewlines for detection; original s preserved with prefix
        XCTAssertEqual(result, "'\t=cmd")
    }

    func testCsvCellProtectsCRLFPrefix() {
        let result = WorkoutExport.csvCell("\r\n=cmd")
        // CRLF is stripped by .whitespacesAndNewlines for detection; original s preserved with prefix
        XCTAssertEqual(result, "'\r\n=cmd")
    }

    func testCsvCellProtectsDoubleNewlinePrefix() {
        let result = WorkoutExport.csvCell("\n\n=cmd")
        // Newlines trigger RFC 4180 quoting; formula prefix still applied
        XCTAssertEqual(result, "\"'\n\n=cmd\"")
    }

    func testCsvCellNil() {
        XCTAssertEqual(WorkoutExport.csvCell(nil as String?), "")
    }

    func testCsvCellNumber() {
        XCTAssertEqual(WorkoutExport.csvCell(42), "42")
    }

    // MARK: - Filenames

    func testExportFilename() {
        let filename = WorkoutExport.exportFilename(ext: "csv")
        XCTAssertTrue(filename.hasPrefix("rowplay-logbook-"))
        XCTAssertTrue(filename.hasSuffix(".csv"))
    }

    func testWorkoutExportFilename() {
        let filename = WorkoutExport.workoutExportFilename(id: 123, ext: "json")
        XCTAssertEqual(filename, "rowplay-workout-123.json")
    }
}
