import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

@MainActor
final class DashboardViewTests: XCTestCase {
    func testDistanceChartAccessibilityDescriptionUsesSelectedDistanceUnit() {
        let summary = SportSummary(
            sport: .rower,
            sessions: 2,
            distance: 5_000,
            time: 1_200,
            averagePace: 120,
            bestPace: 118,
            longestDistance: 5_000
        )

        let value = DashboardView.distanceBySportAccessibilityDescription([summary], unit: .imperial)

        XCTAssertTrue(value.contains("3.11 mi"))
    }

    func testDistanceChartAccessibilityDescriptionTracksDistanceUnit() {
        let summaries = [
            SportSummary(
                sport: .rower,
                sessions: 1,
                distance: 1_609.344,
                time: 420,
                averagePace: 130,
                bestPace: 130,
                longestDistance: 1_609.344
            )
        ]

        let metric = DashboardView.distanceBySportAccessibilityDescription(summaries, unit: .metric)
        let imperial = DashboardView.distanceBySportAccessibilityDescription(summaries, unit: .imperial)

        XCTAssertTrue(metric.contains("km"))
        XCTAssertTrue(imperial.contains("1.00 mi"))
        XCTAssertNotEqual(metric, imperial)
    }

    func testRecentPaceDerivedValuesTrackCurrentWorkouts() {
        let slowWorkout = makeWorkout(id: 1, pace: 180)
        let fastWorkout = makeWorkout(id: 2, pace: 90)

        let slowDescription = DashboardView.recentPaceAccessibilityDescription([slowWorkout])
        let fastDescription = DashboardView.recentPaceAccessibilityDescription([fastWorkout])
        let slowDomain = DashboardView.recentPaceChartDomain(for: [slowWorkout])
        let fastDomain = DashboardView.recentPaceChartDomain(for: [fastWorkout])

        XCTAssertNotEqual(slowDescription, fastDescription)
        XCTAssertNotEqual(slowDomain, fastDomain)
        XCTAssertEqual(DashboardView.recentPaceAccessibilityDescription([]), "No data")
    }

    private func makeWorkout(id: Int, pace: TimeInterval) -> Workout {
        Workout(
            id: id,
            date: Date(timeIntervalSince1970: TimeInterval(id)),
            sport: .rower,
            distance: 2_000,
            time: pace * 4,
            pace: pace,
            workoutType: "Test",
            hasStrokeData: false
        )
    }
}

// MARK: - ReplayRendererMode Tests

@MainActor
final class ReplayRendererModeTests: XCTestCase {
    func testDefaultIsThreeD() {
        let mode: ReplayRendererMode = .threeD
        XCTAssertEqual(mode, .threeD)
    }

    func testAllCasesCount() {
        XCTAssertEqual(ReplayRendererMode.allCases.count, 2)
    }

    func testDisplayNamesAreDistinct() {
        let names = Set(ReplayRendererMode.allCases.map(\.displayName))
        XCTAssertEqual(names.count, 2)
        XCTAssertTrue(names.contains("2D"))
        XCTAssertTrue(names.contains("3D"))
    }

    func testRawValuesMatchDisplayNames() {
        for mode in ReplayRendererMode.allCases {
            XCTAssertEqual(mode.rawValue, mode.displayName)
        }
    }

    func testIdIsRawValue() {
        for mode in ReplayRendererMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    func testGhostUsesElapsedReplayTimeInsteadOfLiveProgress() {
        let strokes = [
            Stroke(t: 10, d: 20, pace: 120, cadence: 28, watts: 150),
            Stroke(t: 20, d: 100, pace: 120, cadence: 28, watts: 170),
        ]

        XCTAssertEqual(Replay3DPlayback.absoluteTime(elapsed: 4, strokes: strokes), 14)
        XCTAssertEqual(Replay3DPlayback.absoluteTime(elapsed: 50, strokes: strokes), 20)
    }

    func testReplayPlaybackClockStartsAtZeroAfterResume() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        let resumed = ReplayPlaybackClock.tick(lastTickDate: nil, currentDate: now)
        XCTAssertNil(resumed.rawDelta)
        XCTAssertEqual(resumed.delta, 0)
        XCTAssertEqual(resumed.lastTickDate, now)

        let nextTick = ReplayPlaybackClock.tick(
            lastTickDate: now,
            currentDate: now.addingTimeInterval(0.25)
        )
        XCTAssertEqual(nextTick.rawDelta ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(nextTick.delta, 0.1, accuracy: 0.0001)
    }

    func testReplayPlaybackClockKeepsRawDeltaSeparateFromPlaybackClamp() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        let backgroundSizedTick = ReplayPlaybackClock.tick(
            lastTickDate: now,
            currentDate: now.addingTimeInterval(0.4)
        )

        XCTAssertEqual(backgroundSizedTick.rawDelta ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertEqual(backgroundSizedTick.delta, 0.1, accuracy: 0.0001)
    }
}
