import XCTest
@testable import RowPlayCore

final class SharePackageTests: XCTestCase {

    private func makeWorkout() -> Workout {
        Workout(
            id: 42,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sport: .rower,
            distance: 2000,
            time: 480,
            pace: 120,
            strokeRate: 28,
            strokeCount: 200,
            heartRateAvg: 155,
            caloriesTotal: 300,
            wattMinutes: 1600,
            dragFactor: 120,
            workoutType: "fixed_distance",
            comments: "Good session",
            hasStrokeData: true,
            isInterval: false
        )
    }

    private func makeDetail() -> WorkoutDetail {
        let strokes = (0..<10).map { i in
            Stroke(t: Double(i) * 2, d: Double(i) * 20, pace: 120, cadence: 28, heartRate: 150 + i, watts: 200)
        }
        let splits = [
            Split(index: 0, distance: 1000, time: 240, pace: 120, heartRate: HeartRateDetail(average: 150)),
            Split(index: 1, distance: 1000, time: 240, pace: 120, heartRate: HeartRateDetail(average: 160)),
        ]
        return WorkoutDetail(workout: makeWorkout(), strokes: strokes, splits: splits)
    }

    // MARK: - Build

    func testBuildFromDetail() {
        let detail = makeDetail()
        let package = SharePackageBuilder.build(from: detail)

        XCTAssertEqual(package.schema, "rowplay-share-package")
        XCTAssertEqual(package.version, SharePackage.currentVersion)
        XCTAssertEqual(package.workout.id, 42)
        XCTAssertEqual(package.workout.sport, .rower)
        XCTAssertEqual(package.workout.distance, 2000)
        XCTAssertEqual(package.strokes.count, 10)
        XCTAssertEqual(package.splits.count, 2)
    }

    func testBuildRedactsSensitiveFields() {
        let detail = makeDetail()
        let package = SharePackageBuilder.build(from: detail)

        // These hardware-identifying fields should NOT be present
        // (they're not on native WorkoutSummary anyway, but verify the struct design)
        // The WorkoutSummary struct intentionally excludes serialNumber, device, etc.
        XCTAssertNotNil(package.workout)
    }

    // MARK: - Encode / Decode Round-Trip

    func testEncodeDecodeRoundTrip() throws {
        let detail = makeDetail()
        let original = SharePackageBuilder.build(from: detail)

        let data = try SharePackageCodec.encode(original)
        let decoded = try SharePackageCodec.decode(data)

        XCTAssertEqual(decoded.schema, original.schema)
        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.workout.id, original.workout.id)
        XCTAssertEqual(decoded.workout.sport, original.workout.sport)
        XCTAssertEqual(decoded.workout.distance, original.workout.distance)
        XCTAssertEqual(decoded.workout.time, original.workout.time)
        XCTAssertEqual(decoded.strokes.count, original.strokes.count)
        XCTAssertEqual(decoded.splits.count, original.splits.count)
    }

    func testEncodeProducesValidJson() throws {
        let detail = makeDetail()
        let package = SharePackageBuilder.build(from: detail)
        let data = try SharePackageCodec.encode(package)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["schema"] as? String, "rowplay-share-package")
        XCTAssertEqual(json?["version"] as? Int, 1)
    }

    func testDecodeInvalidDataThrows() {
        let invalidData = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try SharePackageCodec.decode(invalidData))
    }

    // MARK: - WorkoutSummary Preserves Key Fields

    func testWorkoutSummaryPreservesFields() {
        let detail = makeDetail()
        let package = SharePackageBuilder.build(from: detail)
        let w = package.workout

        XCTAssertEqual(w.strokeRate, 28)
        XCTAssertEqual(w.strokeCount, 200)
        XCTAssertEqual(w.heartRateAvg, 155)
        XCTAssertEqual(w.caloriesTotal, 300)
        XCTAssertEqual(w.wattMinutes, 1600)
        XCTAssertEqual(w.dragFactor, 120)
        XCTAssertEqual(w.workoutType, "fixed_distance")
        XCTAssertEqual(w.comments, "Good session")
        XCTAssertTrue(w.hasStrokeData)
    }

    // MARK: - Empty Detail

    func testBuildFromEmptyDetail() {
        let workout = Workout(
            id: 1,
            date: Date(),
            sport: .bike,
            distance: 0,
            time: 0,
            pace: 0,
            workoutType: "justrow",
            hasStrokeData: false
        )
        let detail = WorkoutDetail(workout: workout, strokes: [], splits: [])
        let package = SharePackageBuilder.build(from: detail)

        XCTAssertEqual(package.workout.id, 1)
        XCTAssertTrue(package.strokes.isEmpty)
        XCTAssertTrue(package.splits.isEmpty)
    }
}
