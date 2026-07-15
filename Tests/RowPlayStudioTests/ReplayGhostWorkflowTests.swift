import CoreGraphics
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayGhostWorkflowTests: XCTestCase {
    func testReplayViewConstructsWithAndWithoutPastSessionCandidates() {
        guard let detail = DemoWorkoutLibrary.details.first else {
            return XCTFail("Demo data must include a replayable workout")
        }

        _ = ReplayView(detail: detail)
        _ = ReplayView(detail: detail, ghostCandidates: [detail], initialGhostID: detail.id)
        _ = ReplayView(detail: detail, ghostCandidates: [detail], initialGhostID: -1)
    }

    func testGhostPathUsesGhostElapsedTimeWithPlayerChartScale() {
        guard let detail = DemoWorkoutLibrary.details.first else {
            return XCTFail("Demo data must include a replayable workout")
        }
        let playerStrokes = [
            Stroke(t: 10, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 20, d: 100, pace: 120, cadence: 28, watts: 200),
        ]
        let ghostStrokes = [
            Stroke(t: 30, d: 0, pace: 120, cadence: 28, watts: 200),
            Stroke(t: 40, d: 100, pace: 120, cadence: 28, watts: 200),
        ]

        let path = ReplayView(detail: detail).makeGhostStrokePath(
            ghostStrokes: ghostStrokes,
            playerStrokes: playerStrokes,
            size: CGSize(width: 100, height: 100)
        )

        let bounds = path.cgPath.boundingBoxOfPath
        XCTAssertEqual(bounds.minX, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 100, accuracy: 0.001)
    }

    func testGhostPathIsEmptyWithoutEnoughStrokeData() {
        guard let detail = DemoWorkoutLibrary.details.first else {
            return XCTFail("Demo data must include a replayable workout")
        }
        let stroke = Stroke(t: 10, d: 0, pace: 120, cadence: 28, watts: 200)

        let path = ReplayView(detail: detail).makeGhostStrokePath(
            ghostStrokes: [stroke],
            playerStrokes: [stroke, Stroke(t: 20, d: 100, pace: 120, cadence: 28, watts: 200)],
            size: CGSize(width: 100, height: 100)
        )

        XCTAssertTrue(path.isEmpty)
    }
}
