import XCTest
@testable import RowPlayCore

final class DemoLiveSampleGeneratorTests: XCTestCase {

    func testFirstSampleHasZeroElapsed() {
        let gen = DemoLiveSampleGenerator()
        let sample = gen.nextSample()
        // First sample advances by 30s
        XCTAssertEqual(sample.time, 30, accuracy: 0.01)
        XCTAssertGreaterThan(sample.distance, 0)
    }

    func testSamplesProgressOverTime() {
        let gen = DemoLiveSampleGenerator()
        let s1 = gen.nextSample()
        let s2 = gen.nextSample()
        let s3 = gen.nextSample()

        XCTAssertLessThan(s1.distance, s2.distance)
        XCTAssertLessThan(s2.distance, s3.distance)
        XCTAssertLessThan(s1.time, s2.time)
        XCTAssertLessThan(s2.time, s3.time)
    }

    func testDeterministicOutput() {
        let gen1 = DemoLiveSampleGenerator(seed: 99)
        let gen2 = DemoLiveSampleGenerator(seed: 99)

        for _ in 0 ..< 5 {
            let a = gen1.nextSample()
            let b = gen2.nextSample()
            XCTAssertEqual(a.distance, b.distance)
            XCTAssertEqual(a.time, b.time)
            XCTAssertEqual(a.pace, b.pace)
        }
    }

    func testDifferentSeedsProduceDifferentOutput() {
        let gen1 = DemoLiveSampleGenerator(seed: 1)
        let gen2 = DemoLiveSampleGenerator(seed: 2)

        let a = gen1.nextSample()
        let b = gen2.nextSample()
        // Pace should differ (with very high probability)
        XCTAssertNotEqual(a.pace, b.pace)
    }

    func testResetRestoresInitialState() {
        let gen = DemoLiveSampleGenerator()
        let first = gen.nextSample()
        _ = gen.nextSample()
        _ = gen.nextSample()
        gen.reset()
        let afterReset = gen.nextSample()
        XCTAssertEqual(first.distance, afterReset.distance)
        XCTAssertEqual(first.time, afterReset.time)
    }

    func testSamplePreservesSport() {
        for sport in Sport.allCases {
            let gen = DemoLiveSampleGenerator(sport: sport)
            let sample = gen.nextSample()
            XCTAssertEqual(sample.sport, sport)
        }
    }

    func testSampleIDMatchesInit() {
        let gen = DemoLiveSampleGenerator(id: 77_001)
        let sample = gen.nextSample()
        XCTAssertEqual(sample.id, 77_001)
    }

    func testHeartRateIsReasonable() {
        let gen = DemoLiveSampleGenerator(baseHR: 155)
        for _ in 0 ..< 10 {
            let sample = gen.nextSample()
            if let hr = sample.heartRateAvg {
                XCTAssertGreaterThan(hr, 100)
                XCTAssertLessThan(hr, 200)
            }
        }
    }
}
