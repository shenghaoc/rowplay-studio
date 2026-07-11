import XCTest
@testable import RowPlayCore
@testable import RowPlayStudio

@MainActor
final class DashboardViewTests: XCTestCase {
    func testSportSummaryAccessibilityValueUsesSelectedDistanceUnit() {
        let summary = SportSummary(
            sport: .rower,
            sessions: 2,
            distance: 5_000,
            time: 1_200,
            averagePace: 120,
            bestPace: 118,
            longestDistance: 5_000
        )

        let value = DashboardView.sportSummaryAccessibilityValue(summary, unit: .imperial)

        XCTAssertTrue(value.contains("3.11 mi"))
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
}
