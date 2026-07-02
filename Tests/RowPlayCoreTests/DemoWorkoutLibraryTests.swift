import XCTest
@testable import RowPlayCore

final class DemoWorkoutLibraryTests: XCTestCase {
    func testDemoLibraryMatchesWebSeedShape() {
        let details = DemoWorkoutLibrary.details

        XCTAssertEqual(details.count, 17)
        XCTAssertEqual(details.first?.id, DemoWorkoutLibrary.defaultWorkoutID)
        XCTAssertEqual(details.first?.workout.sport, .rower)
        XCTAssertEqual(details.first?.workout.hasStrokeData, true)
        XCTAssertGreaterThanOrEqual(details.first?.strokes.count ?? 0, 200)
        XCTAssertEqual(details.first?.strokes.last?.d ?? 0, 2_000, accuracy: 0.1)
    }

    func testNoStrokeFixtureStillHasSplits() {
        let detail = DemoWorkoutLibrary.details.first { $0.id == 9001 }

        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.workout.hasStrokeData, false)
        XCTAssertTrue(detail?.strokes.isEmpty ?? false)
        XCTAssertFalse(detail?.splits.isEmpty ?? true)
    }

    func testBikeWattsUseConcept2NormalizedPaceDivisor() {
        let rowerWatts = RowPlayFormatting.paceToWatts(for: .rower, pacePer500m: 100)
        let bikeWatts = RowPlayFormatting.paceToWatts(for: .bike, pacePer500m: 100)

        XCTAssertEqual(bikeWatts, rowerWatts / RowPlayFormatting.bikeWattsFromNormalizedPaceDivisor, accuracy: 0.0001)
    }
}
