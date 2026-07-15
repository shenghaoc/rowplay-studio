import XCTest
@testable import RowPlayCore

final class ReplayRaceReportTests: XCTestCase {
    func testReportRoundTrip() throws {
        let player = Workout(
            id: 7,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sport: .rower,
            distance: 2000,
            time: 480,
            pace: 120,
            workoutType: "FixedDistanceIntervals",
            comments: "secret comment",
            hasStrokeData: true
        )
        let rival = ReplayRival(
            id: "pace-120",
            kind: .constantPace,
            displayLabel: "2:00/500m",
            strokes: [
                Stroke(t: 0, d: 0, pace: 120, cadence: 0, watts: 200),
                Stroke(t: 500, d: 2000, pace: 120, cadence: 0, watts: 200),
            ],
            hasGenuineStrokeData: false,
            targetPace: 120
        )
        let result = ReplayRaceResult(
            outcome: .playerWon,
            axis: .distance,
            timeMargin: 20,
            distanceMargin: 80,
            rivalDidNotFinish: false,
            playerFinishTime: 480,
            rivalFinishTime: 500,
            playerDistance: 2000,
            rivalDistance: 1920
        )
        let report = ReplayRaceReportBuilder.build(
            player: player,
            rival: rival,
            result: result,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try ReplayRaceReportCodec.encode(report)
        let decoded = try ReplayRaceReportCodec.decode(data)

        XCTAssertEqual(decoded.schema, ReplayRaceReport.currentSchema)
        XCTAssertEqual(decoded.version, ReplayRaceReport.currentVersion)
        XCTAssertEqual(decoded.outcome, .playerWon)
        XCTAssertEqual(decoded.timeMargin ?? -1, 20, accuracy: 0.001)
        XCTAssertEqual(decoded.distanceMargin ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(decoded.rival.kind, .constantPace)
        XCTAssertEqual(decoded.rival.targetPace ?? -1, 120, accuracy: 0.001)
        XCTAssertEqual(decoded.rival.label, "Pace boat")
        XCTAssertEqual(decoded.sport, .rower)
    }

    func testImportedFilenameAbsentFromReportAndJSON() throws {
        let player = Workout(
            id: 1,
            date: Date(timeIntervalSince1970: 0),
            sport: .skierg,
            distance: 1000,
            time: 240,
            pace: 120,
            workoutType: "FixedDistanceIntervals",
            hasStrokeData: true
        )
        let rival = ReplayRival(
            id: "file-abc",
            kind: .importedFile,
            displayLabel: "secret-workout.fit",
            strokes: [
                Stroke(t: 0, d: 0, pace: 120, cadence: 0, watts: 200),
                Stroke(t: 250, d: 1000, pace: 120, cadence: 0, watts: 200),
            ],
            hasGenuineStrokeData: false,
            localFileName: "secret-workout.fit"
        )
        let result = ReplayRaceResult(
            outcome: .rivalWon,
            axis: .distance,
            timeMargin: 10,
            distanceMargin: 40
        )
        let report = ReplayRaceReportBuilder.build(player: player, rival: rival, result: result)
        let data = try ReplayRaceReportCodec.encode(report)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(report.rival.label, "Imported rival")
        XCTAssertFalse(json.contains("secret-workout"))
        XCTAssertFalse(json.contains(".fit"))
        XCTAssertFalse(json.contains("localFileName"))
        XCTAssertFalse(json.contains("comments"))
        XCTAssertFalse(json.contains("token"))
        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.contains("http"))
        XCTAssertFalse(json.contains("workoutID"))
        XCTAssertFalse(json.contains("sessionWorkoutID"))
    }

    func testSessionReportUsesGenericLabel() throws {
        let player = Workout(
            id: 1,
            date: Date(timeIntervalSince1970: 0),
            sport: .bike,
            distance: 5000,
            time: 600,
            pace: 60,
            workoutType: "FixedDistanceIntervals",
            hasStrokeData: true
        )
        let rival = ReplayRival(
            id: "session-9",
            kind: .session,
            displayLabel: "2024-01-01",
            strokes: [
                Stroke(t: 0, d: 0, pace: 60, cadence: 80, watts: 200),
                Stroke(t: 610, d: 5000, pace: 60, cadence: 80, watts: 200),
            ],
            hasGenuineStrokeData: true,
            sessionWorkoutID: 9
        )
        let result = ReplayRaceResult(
            outcome: .tie,
            axis: .distance,
            timeMargin: 0,
            distanceMargin: 0
        )
        let sessionDate = Date(timeIntervalSince1970: 1_000)
        let report = ReplayRaceReportBuilder.build(
            player: player,
            rival: rival,
            result: result,
            sessionDate: sessionDate
        )
        XCTAssertEqual(report.rival.label, "Past session")
        XCTAssertEqual(report.rival.sessionDate, sessionDate)
    }
}
