import XCTest
@testable import RowPlayCore

final class GhostPickTests: XCTestCase {
    private func makeWorkout(
        id: Int,
        distance: Double,
        pace: TimeInterval,
        date: Date,
        sport: Sport = .rower,
        time: TimeInterval = 600,
        workoutType: String = "2000m test"
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

    private func date(_ str: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: str) ?? Date(timeIntervalSince1970: 0)
    }

    func testPrefersSameDistanceBandAndClosestMetres() {
        let current = GhostPickContext(id: 1, distance: 2000, sport: .rower, time: 480)
        let candidates = [
            makeWorkout(id: 2, distance: 5000, pace: 110, date: date("2026-01-01")),
            makeWorkout(id: 3, distance: 2010, pace: 115, date: date("2026-02-01")),
            makeWorkout(id: 4, distance: 10000, pace: 120, date: date("2026-03-01"))
        ]
        XCTAssertEqual(GhostPick.pickDefaultGhostCandidate(candidates: candidates, current: current)?.id, 3)
    }

    func testExcludesCurrentWorkoutId() {
        let current = GhostPickContext(id: 2, distance: 2000, sport: .rower, time: 480)
        let candidates = [
            makeWorkout(id: 2, distance: 2000, pace: 110, date: date("2026-01-01")),
            makeWorkout(id: 3, distance: 2005, pace: 112, date: date("2026-02-01"))
        ]
        XCTAssertEqual(GhostPick.pickDefaultGhostCandidate(candidates: candidates, current: current)?.id, 3)
    }

    func testReturnsNullWhenNoCandidateIsComparable() {
        let current = GhostPickContext(id: 1, distance: 2000, sport: .rower, time: 480)
        let candidates = [
            makeWorkout(id: 2, distance: 5000, pace: 110, date: date("2026-01-01")),
            makeWorkout(id: 3, distance: 10000, pace: 120, date: date("2026-03-01"))
        ]
        XCTAssertNil(GhostPick.pickDefaultGhostCandidate(candidates: candidates, current: current))
    }

    func testRejectsFixedTimeCandidatesForFixedDistancePiece() {
        let current = GhostPickContext(id: 1, distance: 2000, sport: .rower, time: 480, workoutType: "2000m test")
        let candidates = [
            makeWorkout(id: 2, distance: 7500, pace: 118, date: date("2026-01-01"), time: 1800, workoutType: "JustRow"),
            makeWorkout(id: 3, distance: 2010, pace: 115, date: date("2026-02-01"))
        ]
        XCTAssertEqual(GhostPick.pickDefaultGhostCandidate(candidates: candidates, current: current)?.id, 3)
    }

    func testPicksTimeClosestCandidateForTimeAxisPiece() {
        let current = GhostPickContext(id: 1, distance: 7500, sport: .rower, time: 1800, workoutType: "JustRow")
        let candidates = [
            makeWorkout(id: 2, distance: 7200, pace: 120, date: date("2026-01-01"), time: 1760, workoutType: "JustRow"),
            makeWorkout(id: 3, distance: 8000, pace: 118, date: date("2026-02-01"), time: 1900, workoutType: "JustRow"),
            makeWorkout(id: 4, distance: 7800, pace: 115, date: date("2026-03-01"), time: 1850, workoutType: "JustRow")
        ]
        // Candidate 2 is closest in time (|1800-1760|=40 vs |1800-1900|=100 vs |1800-1850|=50)
        XCTAssertEqual(GhostPick.pickDefaultGhostCandidate(candidates: candidates, current: current)?.id, 2)
    }

    func testBreaksEquidistantTieByFastestPace() {
        let current = GhostPickContext(id: 1, distance: 2000, sport: .rower, time: 480)
        let candidates = [
            makeWorkout(id: 2, distance: 1950, pace: 120, date: date("2026-05-01")),
            makeWorkout(id: 3, distance: 2050, pace: 110, date: date("2026-01-01"))
        ]
        XCTAssertEqual(GhostPick.pickDefaultGhostCandidate(candidates: candidates, current: current)?.id, 3)
    }

    func testBreaksDistanceAndPaceTieByMostRecentDate() {
        let current = GhostPickContext(id: 1, distance: 2000, sport: .rower, time: 480)
        let candidates = [
            makeWorkout(id: 2, distance: 1950, pace: 115, date: date("2026-01-01")),
            makeWorkout(id: 3, distance: 2050, pace: 115, date: date("2026-05-01"))
        ]
        XCTAssertEqual(GhostPick.pickDefaultGhostCandidate(candidates: candidates, current: current)?.id, 3)
    }
}
