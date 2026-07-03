import XCTest
@testable import RowPlayCore

final class ComparabilityGuardTests: XCTestCase {
    // MARK: - classifyAxis

    func testClassifyAxisDefaultsToDistanceForNil() {
        XCTAssertEqual(ComparabilityGuard.classifyAxis(workoutType: nil), .distance)
    }

    func testClassifyAxisDefaultsToDistanceForUnknownType() {
        XCTAssertEqual(ComparabilityGuard.classifyAxis(workoutType: "2000m test"), .distance)
    }

    func testClassifyAxisReturnsTimeForJustRow() {
        XCTAssertEqual(ComparabilityGuard.classifyAxis(workoutType: "JustRow"), .time)
    }

    func testClassifyAxisReturnsTimeForFixedTime() {
        XCTAssertEqual(ComparabilityGuard.classifyAxis(workoutType: "FixedTimeSplits"), .time)
    }

    func testClassifyAxisIsCaseInsensitive() {
        XCTAssertEqual(ComparabilityGuard.classifyAxis(workoutType: "justrow"), .time)
        XCTAssertEqual(ComparabilityGuard.classifyAxis(workoutType: "FIXEDTIME"), .time)
    }

    // MARK: - areComparable

    func testAreComparableRequiresSameSport() {
        let a = ComparableContext(sport: .rower, distance: 2000, time: 480)
        let b = ComparableContext(sport: .skierg, distance: 2000, time: 480)
        XCTAssertFalse(ComparabilityGuard.areComparable(a, b))
    }

    func testAreComparableRequiresSameAxis() {
        let a = ComparableContext(sport: .rower, distance: 2000, time: 480, workoutType: "2000m test")
        let b = ComparableContext(sport: .rower, distance: 7500, time: 1800, workoutType: "JustRow")
        XCTAssertFalse(ComparabilityGuard.areComparable(a, b))
    }

    func testAreComparableMatchesSameDistanceBand() {
        let a = ComparableContext(sport: .rower, distance: 2000, time: 480)
        let b = ComparableContext(sport: .rower, distance: 2010, time: 490)
        XCTAssertTrue(ComparabilityGuard.areComparable(a, b))
    }

    func testAreComparableRejectsDifferentDistanceBand() {
        let a = ComparableContext(sport: .rower, distance: 2000, time: 480)
        let b = ComparableContext(sport: .rower, distance: 5000, time: 1200)
        XCTAssertFalse(ComparabilityGuard.areComparable(a, b))
    }

    func testAreComparableMatchesSameDurationBand() {
        let a = ComparableContext(sport: .rower, distance: 7500, time: 1800, workoutType: "JustRow")
        let b = ComparableContext(sport: .rower, distance: 7200, time: 1760, workoutType: "JustRow")
        XCTAssertTrue(ComparabilityGuard.areComparable(a, b))
    }
}
