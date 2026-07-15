import XCTest
@testable import RowPlayCore

final class ReplayRivalFactoryTests: XCTestCase {
    func testConstantPaceRivalIdentityUsesPOSIXDecimalSeparators() throws {
        let player = Workout(
            id: 1,
            date: Date(timeIntervalSince1970: 0),
            sport: .rower,
            distance: 2_000.5,
            time: 480,
            pace: 120,
            workoutType: "FixedDistance",
            hasStrokeData: true
        )

        let rival = try XCTUnwrap(ReplayRivalFactory.makeConstantPaceRival(
            pacePer500m: 120.25,
            player: player
        ))

        XCTAssertEqual(rival.id, "pace-120.2500-d-2000.500")
        XCTAssertFalse(rival.id.contains(","))
    }

    private struct FixtureFile: Decodable {
        let constantPace: [ConstantPaceCase]
    }

    private struct ConstantPaceCase: Decodable {
        let label: String
        let pacePer500m: Double
        let totalDistance: Double
        let sport: String
        let expectedStrokeCount: Int
        let expectedEndTime: Double?
        let expectedEndDistance: Double?
        let expectedPace: Double?
        let expectPositiveWatts: Bool?
        let expectBikeWattsDivisor: Bool?
    }

    private static let fixtureResult = Result {
        try ParityFixtureLoader.loadJSON(FixtureFile.self, from: "replay-rival-sources-parity")
    }

    func testConstantPaceParityFixture() throws {
        let fixture = try Self.fixtureResult.get()
        for c in fixture.constantPace {
            let sport = Sport(rawValue: c.sport) ?? .rower
            let strokes = ReplayRivalFactory.constantPaceStrokes(
                pacePer500m: c.pacePer500m,
                totalDistance: c.totalDistance,
                sport: sport
            )
            XCTAssertEqual(strokes.count, c.expectedStrokeCount, c.label)
            if c.expectedStrokeCount == 2 {
                XCTAssertEqual(strokes[0].t, 0, accuracy: 0.001, c.label)
                XCTAssertEqual(strokes[0].d, 0, accuracy: 0.001, c.label)
                if let endT = c.expectedEndTime {
                    XCTAssertEqual(strokes[1].t, endT, accuracy: 0.001, c.label)
                }
                if let endD = c.expectedEndDistance {
                    XCTAssertEqual(strokes[1].d, endD, accuracy: 0.001, c.label)
                }
                if let pace = c.expectedPace {
                    XCTAssertEqual(strokes[0].pace, pace, accuracy: 0.001, c.label)
                    XCTAssertEqual(strokes[1].pace, pace, accuracy: 0.001, c.label)
                }
                if c.expectPositiveWatts == true {
                    XCTAssertGreaterThan(strokes[0].watts, 0, c.label)
                }
                if c.expectBikeWattsDivisor == true {
                    let rower = ReplayRivalFactory.constantPaceStrokes(
                        pacePer500m: c.pacePer500m,
                        totalDistance: c.totalDistance,
                        sport: .rower
                    )
                    XCTAssertLessThan(strokes[0].watts, rower[0].watts, c.label)
                    let expected = Int(
                        (RowPlayFormatting.paceToWatts(for: .bike, pacePer500m: c.pacePer500m)).rounded()
                    )
                    XCTAssertEqual(strokes[0].watts, expected, c.label)
                }
                XCTAssertEqual(strokes[0].cadence, 0, c.label)
            }
        }
    }

    func testSessionRivalFromDetail() {
        let workout = Workout(
            id: 42,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sport: .rower,
            distance: 2000,
            time: 480,
            pace: 120,
            workoutType: "FixedDistanceIntervals",
            hasStrokeData: true
        )
        let strokes = [
            Stroke(t: 0, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 480, d: 2000, pace: 120, cadence: 28, watts: 200),
        ]
        let detail = WorkoutDetail(workout: workout, strokes: strokes, splits: [])
        let rival = ReplayRivalFactory.makeSessionRival(from: detail)
        XCTAssertNotNil(rival)
        XCTAssertEqual(rival?.kind, .session)
        XCTAssertEqual(rival?.sessionWorkoutID, 42)
        XCTAssertEqual(rival?.hasGenuineStrokeData, true)
        XCTAssertEqual(rival?.id, "session-42")
        XCTAssertEqual(rival?.strokes.count, 2)
    }

    func testSessionRivalRejectsSingleStroke() {
        let workout = Workout(
            id: 1,
            date: Date(),
            sport: .rower,
            distance: 500,
            time: 120,
            pace: 120,
            workoutType: "FixedDistanceIntervals",
            hasStrokeData: true
        )
        let detail = WorkoutDetail(
            workout: workout,
            strokes: [Stroke(t: 0, d: 0, pace: 120, cadence: 28, watts: 200)],
            splits: []
        )
        XCTAssertNil(ReplayRivalFactory.makeSessionRival(from: detail))
    }

    func testConstantPaceDistanceAxis() {
        let workout = Workout(
            id: 1,
            date: Date(),
            sport: .rower,
            distance: 2000,
            time: 500,
            pace: 125,
            workoutType: "FixedDistanceIntervals",
            hasStrokeData: true
        )
        let rival = ReplayRivalFactory.makeConstantPaceRival(pacePer500m: 120, player: workout)
        XCTAssertNotNil(rival)
        XCTAssertEqual(rival?.kind, .constantPace)
        XCTAssertEqual(rival?.hasGenuineStrokeData, false)
        XCTAssertEqual(rival?.targetPace, 120)
        XCTAssertEqual(rival?.strokes.count, 2)
        XCTAssertEqual(rival?.strokes.last?.d ?? 0, 2000, accuracy: 0.001)
        XCTAssertEqual(rival?.strokes.last?.t ?? 0, 480, accuracy: 0.001)
    }

    func testConstantPaceTimeAxis() {
        let workout = Workout(
            id: 1,
            date: Date(),
            sport: .rower,
            distance: 1000,
            time: 300,
            pace: 120,
            workoutType: "JustRow",
            hasStrokeData: true
        )
        let rival = ReplayRivalFactory.makeConstantPaceRival(pacePer500m: 100, player: workout)
        XCTAssertNotNil(rival)
        // distance = 500 * 300 / 100 = 1500
        XCTAssertEqual(rival?.strokes.last?.t ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(rival?.strokes.last?.d ?? 0, 1500, accuracy: 0.001)
    }

    func testConstantPaceRejectsInvalidInputs() {
        let workout = Workout(
            id: 1,
            date: Date(),
            sport: .rower,
            distance: 2000,
            time: 480,
            pace: 120,
            workoutType: "FixedDistanceIntervals",
            hasStrokeData: true
        )
        XCTAssertNil(ReplayRivalFactory.makeConstantPaceRival(pacePer500m: 0, player: workout))
        XCTAssertNil(ReplayRivalFactory.makeConstantPaceRival(pacePer500m: -1, player: workout))
        XCTAssertNil(ReplayRivalFactory.makeConstantPaceRival(pacePer500m: .nan, player: workout))
        XCTAssertNil(ReplayRivalFactory.makeConstantPaceRival(pacePer500m: .infinity, player: workout))
    }

    func testImportedRivalMarksNonGenuine() {
        let strokes = [
            Stroke(t: 0, d: 0, pace: 120, cadence: 0, watts: 200),
            Stroke(t: 100, d: 400, pace: 125, cadence: 0, watts: 190),
        ]
        let rival = ReplayRivalFactory.makeImportedRival(
            strokes: strokes,
            fileName: "/Users/secret/path/my-session.csv"
        )
        XCTAssertNotNil(rival)
        XCTAssertEqual(rival?.kind, .importedFile)
        XCTAssertEqual(rival?.hasGenuineStrokeData, false)
        XCTAssertEqual(rival?.localFileName, "my-session.csv")
        XCTAssertEqual(rival?.displayLabel, "my-session.csv")
        XCTAssertFalse(rival?.id.contains("Users") ?? true)
        XCTAssertFalse(rival?.id.contains("secret") ?? true)
    }
}
