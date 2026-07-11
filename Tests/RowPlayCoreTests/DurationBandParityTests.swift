import XCTest
@testable import RowPlayCore

/// Direct parity tests for `WorkoutAnalytics.durationBand(for:)`.
/// Asserts native output matches web-verified values from `src/lib/analytics.ts`.
final class DurationBandParityTests: XCTestCase {
    private struct Fixture: Decodable {
        let name: String
        let inputSeconds: Double
        let expectedKey: String
        let expectedLabel: String
        let expectedNominalSeconds: Double
    }

    private var fixtures: [Fixture] = []

    override func setUpWithError() throws {
        fixtures = try ParityFixtureLoader.loadJSON([Fixture].self, from: "duration-band-parity")
    }

    // MARK: - Fixture loading

    func testFixturesLoaded() {
        XCTAssertFalse(fixtures.isEmpty, "Should load at least one duration-band fixture")
    }

    // MARK: - Fixture-driven parity

    func testDurationBandParity() {
        for fixture in fixtures {
            let band = WorkoutAnalytics.durationBand(for: fixture.inputSeconds)

            XCTAssertEqual(
                band.key, fixture.expectedKey,
                "\(fixture.name) [\(fixture.inputSeconds)s]: key '\(band.key)' != expected '\(fixture.expectedKey)'"
            )
            XCTAssertEqual(
                band.label, fixture.expectedLabel,
                "\(fixture.name) [\(fixture.inputSeconds)s]: label '\(band.label)' != expected '\(fixture.expectedLabel)'"
            )
            XCTAssertEqual(
                band.nominalSeconds, fixture.expectedNominalSeconds, accuracy: 0.0001,
                "\(fixture.name) [\(fixture.inputSeconds)s]: nominal \(band.nominalSeconds) != expected \(fixture.expectedNominalSeconds)"
            )
        }
    }

    // MARK: - Non-finite direct tests

    func testDurationBandNegativeInput() {
        let band = WorkoutAnalytics.durationBand(for: -1)
        XCTAssertEqual(band.key, "other", "negative input: key should be 'other'")
        XCTAssertEqual(band.label, "Other", "negative input: label should be 'Other'")
        XCTAssertEqual(band.nominalSeconds, -1, accuracy: 0.0001, "negative input: nominal should preserve input")
    }

    func testDurationBandNaN() {
        let band = WorkoutAnalytics.durationBand(for: .nan)
        XCTAssertEqual(band.key, "other", "NaN input: key should be 'other'")
        XCTAssertEqual(band.label, "Other", "NaN input: label should be 'Other'")
        XCTAssertTrue(band.nominalSeconds.isNaN, "NaN input: nominal should be NaN")
    }

    func testDurationBandPositiveInfinity() {
        let band = WorkoutAnalytics.durationBand(for: .infinity)
        XCTAssertEqual(band.key, "other", "+Infinity input: key should be 'other'")
        XCTAssertEqual(band.label, "Other", "+Infinity input: label should be 'Other'")
        XCTAssertEqual(band.nominalSeconds, .infinity, "+Infinity input: nominal should be +Infinity")
    }

    // MARK: - ComparabilityGuard integration

    func testComparabilityGuardConsumesDurationBandKey() {
        // Two 30-min JustRow workouts within the same standard window
        let a = ComparableContext(sport: .rower, distance: 7500, time: 1800, workoutType: "JustRow")
        let b = ComparableContext(sport: .rower, distance: 7200, time: 1760, workoutType: "JustRow")

        // Both should snap to the "1800" duration band
        XCTAssertEqual(
            WorkoutAnalytics.durationBand(for: a.time).key, "1800",
            "30min workout A should snap to key '1800'"
        )
        XCTAssertEqual(
            WorkoutAnalytics.durationBand(for: b.time).key, "1800",
            "30min workout B (1760s) should snap to key '1800'"
        )

        // areComparable should return true because both share the same duration-band key
        XCTAssertTrue(
            ComparabilityGuard.areComparable(a, b),
            "Two time-axis workouts in the same duration band should be comparable"
        )
    }
}
