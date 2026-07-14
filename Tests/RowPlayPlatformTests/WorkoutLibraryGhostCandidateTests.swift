import XCTest
@testable import RowPlayCore
@testable import RowPlayPlatform

@MainActor
final class WorkoutLibraryGhostCandidateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "RowPlayStudioTests.GhostCandidate.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Ghost Candidates from Demo Data

    func testGhostCandidatesForDemoWorkout() {
        let library = WorkoutLibrary(details: DemoWorkoutLibrary.details)
        // Use a 2K row workout from the demo set
        guard let targetID = DemoWorkoutLibrary.details.first(where: {
            $0.workout.sport == .rower && $0.workout.distance == 2000
        })?.id else {
            XCTFail("No 2K row workout found in demo data")
            return
        }

        let candidates = library.ghostCandidates(for: targetID)
        // There should be at least one comparable past-session candidate
        // since the demo library has multiple 2K workouts
        XCTAssertFalse(candidates.isEmpty, "Should have at least one ghost candidate")
        // None should be the current workout
        XCTAssertTrue(candidates.allSatisfy { $0.id != targetID })
    }

    func testGhostCandidatesExcludesCurrentWorkout() {
        let details = [
            makeDetail(id: 1, distance: 2_000, time: 480, pace: 120),
            makeDetail(id: 2, distance: 2_000, time: 480, pace: 120),
        ]
        let library = WorkoutLibrary(details: details)
        let candidates = library.ghostCandidates(for: 1)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.id, 2)
    }

    // MARK: - Ghost Candidate Caching

    func testGhostCandidatesAreCached() {
        let details = [
            makeDetail(id: 1, distance: 2_000, time: 480, pace: 120),
            makeDetail(id: 2, distance: 2_000, time: 480, pace: 130),
        ]
        let library = WorkoutLibrary(details: details)
        let first = library.ghostCandidates(for: 1)
        let second = library.ghostCandidates(for: 1)
        // Both calls should return the same result (cached)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testGhostCandidateCacheInvalidatesOnDetailsChange() {
        let details = [
            makeDetail(id: 1, distance: 2_000, time: 480, pace: 120),
            makeDetail(id: 2, distance: 2_000, time: 480, pace: 130),
        ]
        let library = WorkoutLibrary(details: details)
        _ = library.ghostCandidates(for: 1)  // populate cache

        // Add a new detail
        library.details.append(makeDetail(id: 3, distance: 2_000, time: 480, pace: 110))
        let second = library.ghostCandidates(for: 1)

        // Should now include workout 3 in the candidates
        XCTAssertTrue(second.contains(where: { $0.id == 3 }))
    }

    // MARK: - Default Ghost Candidate

    func testDefaultGhostCandidateReturnsFirstRanked() {
        let details = [
            makeDetail(id: 1, distance: 2_000, time: 480, pace: 120),
            makeDetail(id: 2, distance: 2_000, time: 480, pace: 130),
            makeDetail(id: 3, distance: 2_000, time: 480, pace: 115),
        ]
        let library = WorkoutLibrary(details: details)
        let defaultGhost = library.defaultGhostCandidate(for: 1)
        // Should be id=3 (fastest pace among same-band)
        XCTAssertEqual(defaultGhost?.id, 3)
    }

    func testDefaultGhostCandidateReturnsNilWhenNoComparable() {
        let details = [
            makeDetail(id: 1, distance: 2_000, time: 480, pace: 120),
        ]
        let library = WorkoutLibrary(details: details)
        let defaultGhost = library.defaultGhostCandidate(for: 1)
        XCTAssertNil(defaultGhost)
    }

    // MARK: - Empty-Stroke Exclusion

    func testGhostCandidatesExcludesEmptyStrokeDetails() {
        let detailWithEmptyStrokes = WorkoutDetail(
            workout: Workout(id: 2, date: Date(), sport: .rower, distance: 2_000, time: 480,
                              pace: 120, workoutType: "FixedDistance", source: "Test", hasStrokeData: true),
            strokes: [],
            splits: []
        )
        let details = [
            makeDetail(id: 1, distance: 2_000, time: 480, pace: 120),
            detailWithEmptyStrokes,
        ]
        let library = WorkoutLibrary(details: details)
        let candidates = library.ghostCandidates(for: 1)
        XCTAssertTrue(candidates.isEmpty, "Should exclude candidates with empty strokes even when hasStrokeData is true")
    }

    // MARK: - Helpers

    private func makeDetail(
        id: Int,
        distance: Double,
        time: TimeInterval,
        pace: TimeInterval,
        sport: Sport = .rower,
        workoutType: String = "FixedDistance",
        strokeCount: Int = 10
    ) -> WorkoutDetail {
        let date = Date(timeIntervalSinceReferenceDate: 1_000 + TimeInterval(id * 1000))
        let workout = Workout(
            id: id, date: date, sport: sport, distance: distance, time: time, pace: pace,
            workoutType: workoutType, source: "Test", hasStrokeData: true
        )
        let strokes = (0..<strokeCount).map { i in
            let t = TimeInterval(i) * (time / TimeInterval(max(1, strokeCount - 1)))
            return Stroke(t: t, d: distance * Double(i) / Double(max(1, strokeCount - 1)),
                          pace: pace, cadence: 28, watts: 200)
        }
        return WorkoutDetail(workout: workout, strokes: strokes, splits: [])
    }
}
