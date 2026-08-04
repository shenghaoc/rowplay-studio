import XCTest
@testable import RowPlayCore

final class ReplayStrokePoseAggregatesTests: XCTestCase {
    func testEvenMediansMatchWebParityAndPositiveDistanceDeltas() throws {
        let strokes = [
            stroke(t: 0, d: 0, heartRate: 140, watts: 100),
            stroke(t: 1, d: 9, heartRate: 160, watts: 200),
            stroke(t: 2, d: 20, heartRate: 180, watts: 300),
            stroke(t: 3, d: 33, heartRate: 200, watts: 400),
        ]

        let aggregates = try XCTUnwrap(
            ReplayStrokePoseAggregates(strokes: strokes, sport: .rower)
        )

        XCTAssertEqual(aggregates.context.peakWatts, 400)
        XCTAssertEqual(aggregates.context.medianWatts, 250)
        XCTAssertEqual(aggregates.context.medianDPS, 11, accuracy: 1e-12)
        XCTAssertEqual(aggregates.context.maxHR, 200)
        XCTAssertEqual(aggregates.medianHeartRate, 170)
    }

    func testMedianFiltersNonFiniteValuesAndUsesFallbackWhenNoneRemain() {
        XCTAssertEqual(
            ReplayStrokePoseAggregates.median([.nan, 3, .infinity, 1], fallback: 9),
            2,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            ReplayStrokePoseAggregates.median([.nan, -.infinity], fallback: 9),
            9,
            accuracy: 1e-12
        )
    }

    func testEmptyStrokesReturnNilForRendererFallback() {
        XCTAssertNil(ReplayStrokePoseAggregates(strokes: [], sport: .rower))
    }

    func testNonPositiveAndNonFiniteDeltasUseSportDefaultDistancePerStroke() throws {
        for sport in Sport.allCases {
            let strokes = [
                stroke(t: 0, d: 12, heartRate: nil, watts: 180),
                stroke(t: 1, d: 12, heartRate: nil, watts: 180),
                stroke(t: 2, d: .infinity, heartRate: nil, watts: 180),
            ]
            let aggregates = try XCTUnwrap(
                ReplayStrokePoseAggregates(strokes: strokes, sport: sport)
            )
            XCTAssertEqual(
                aggregates.context.medianDPS,
                ReplayStrokePoseAggregates.defaultDistancePerStroke(for: sport),
                accuracy: 1e-12
            )
            XCTAssertEqual(aggregates.medianHeartRate, 0)
        }
    }

    func testOddMedianUsesMiddleFiniteValue() {
        XCTAssertEqual(
            ReplayStrokePoseAggregates.median([7, 1, 4], fallback: 0),
            4,
            accuracy: 1e-12
        )
    }

    private func stroke(
        t: TimeInterval,
        d: Double,
        heartRate: Int?,
        watts: Int
    ) -> Stroke {
        Stroke(
            t: t,
            d: d,
            pace: 120,
            cadence: 30,
            heartRate: heartRate,
            watts: watts
        )
    }
}
