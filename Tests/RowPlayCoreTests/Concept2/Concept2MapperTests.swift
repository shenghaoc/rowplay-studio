import Foundation
import XCTest
@testable import RowPlayCore

final class Concept2MapperTests: XCTestCase {
    func testMapWorkoutNormalizesSummaryFieldsAndDefaults() {
        let raw = Concept2RawResult(
            id: 42,
            date: "2024-06-15 10:30:00",
            type: "bike",
            distance: 10_000,
            time: 18_000,
            strokeRate: 90,
            strokeCount: 420,
            dragFactor: 115,
            caloriesTotal: 300,
            wattMinutes: 125.5,
            workoutType: nil,
            comments: "steady state",
            strokeData: nil,
            source: "logbook",
            verified: nil,
            restTime: nil,
            restDistance: nil,
            heartRate: .object(Concept2RawHeartRate(average: 150, min: 142, max: 158)),
            workout: Concept2RawWorkout(
                splits: nil,
                intervals: [
                    Concept2RawSplit(
                        distance: 1_000,
                        time: 1_800,
                        strokeRate: 90,
                        heartRate: nil,
                        type: nil,
                        restTime: nil,
                        restDistance: nil,
                        machine: nil
                    )
                ]
            ),
            metadata: nil
        )

        let workout = Concept2Mapper.mapWorkout(raw)

        XCTAssertEqual(workout.id, 42)
        XCTAssertEqual(workout.date, expectedDate("2024-06-15 10:30:00"))
        XCTAssertEqual(workout.sport, .bike)
        XCTAssertEqual(workout.distance, 10_000)
        XCTAssertEqual(workout.time, 1_800, accuracy: 0.001)
        XCTAssertEqual(workout.pace, 90, accuracy: 0.001)
        XCTAssertEqual(workout.strokeRate, 90)
        XCTAssertEqual(workout.strokeCount, 420)
        XCTAssertEqual(workout.heartRateAvg, 150)
        XCTAssertEqual(workout.caloriesTotal, 300)
        XCTAssertEqual(workout.wattMinutes, 125.5)
        XCTAssertEqual(workout.dragFactor, 115)
        XCTAssertEqual(workout.workoutType, "JustRow")
        XCTAssertEqual(workout.comments, "steady state")
        XCTAssertEqual(workout.source, "logbook")
        XCTAssertTrue(workout.verified)
        XCTAssertFalse(workout.hasStrokeData)
        XCTAssertTrue(workout.isInterval)
    }

    func testMapHeartRateValueHandlesNumberAndObjectShapes() {
        let number = Concept2Mapper.mapHeartRateValue(.number(154))
        XCTAssertEqual(number, HeartRateDetail(average: 154))

        let object = Concept2Mapper.mapHeartRateValue(
            .object(Concept2RawHeartRate(average: 155, min: 148, max: 162))
        )
        XCTAssertEqual(object, HeartRateDetail(average: 155, min: 148, max: 162))

        XCTAssertNil(Concept2Mapper.mapHeartRateValue(nil))
    }

    func testMapStrokesNormalizesBikePaceAndAccumulatesIntervalOffsets() {
        let raw = [
            Concept2RawStroke(t: 100, d: 500, p: 1_200, spm: 90, hr: 140),
            Concept2RawStroke(t: 200, d: 1_000, p: 1_200, spm: 92, hr: nil),
            Concept2RawStroke(t: 50, d: 200, p: 1_200, spm: 88, hr: 138),
        ]

        let strokes = Concept2Mapper.mapStrokes(raw, sport: .bike)

        XCTAssertEqual(strokes.count, 3)
        XCTAssertEqual(strokes[0].t, 10, accuracy: 0.001)
        XCTAssertEqual(strokes[0].d, 50, accuracy: 0.001)
        XCTAssertEqual(strokes[0].pace, 60, accuracy: 0.001)
        XCTAssertEqual(strokes[0].watts, 203)
        XCTAssertEqual(strokes[0].heartRate, 140)

        XCTAssertEqual(strokes[1].t, 20, accuracy: 0.001)
        XCTAssertEqual(strokes[1].d, 100, accuracy: 0.001)
        XCTAssertEqual(strokes[1].pace, 60, accuracy: 0.001)

        XCTAssertEqual(strokes[2].t, 25, accuracy: 0.001)
        XCTAssertEqual(strokes[2].d, 120, accuracy: 0.001)
        XCTAssertEqual(strokes[2].pace, 60, accuracy: 0.001)
        XCTAssertEqual(strokes[2].watts, 203)
        XCTAssertEqual(strokes[2].heartRate, 138)
    }

    func testMapSplitsFallsBackToIntervalsAndMarksRestSegments() {
        let raw = Concept2RawResult(
            id: 77,
            date: "2024-06-15 10:30:00",
            type: "rower",
            distance: 2_000,
            time: 5400,
            strokeRate: nil,
            strokeCount: nil,
            dragFactor: nil,
            caloriesTotal: nil,
            wattMinutes: nil,
            workoutType: "Intervals",
            comments: nil,
            strokeData: nil,
            source: nil,
            verified: nil,
            restTime: nil,
            restDistance: nil,
            heartRate: nil,
            workout: Concept2RawWorkout(
                splits: nil,
                intervals: [
                    Concept2RawSplit(
                        distance: 500,
                        time: 1_200,
                        strokeRate: 30,
                        heartRate: .number(160),
                        type: nil,
                        restTime: nil,
                        restDistance: nil,
                        machine: nil
                    ),
                    Concept2RawSplit(
                        distance: 0,
                        time: 300,
                        strokeRate: nil,
                        heartRate: nil,
                        type: nil,
                        restTime: 300,
                        restDistance: 0,
                        machine: nil
                    ),
                ]
            ),
            metadata: nil
        )

        let splits = Concept2Mapper.mapSplits(raw)

        XCTAssertEqual(splits.count, 2)

        XCTAssertEqual(splits[0].index, 0)
        XCTAssertEqual(splits[0].distance, 500)
        XCTAssertEqual(splits[0].time, 120, accuracy: 0.001)
        XCTAssertEqual(splits[0].pace, 120, accuracy: 0.001)
        XCTAssertEqual(splits[0].cadence, 30)
        XCTAssertEqual(splits[0].heartRate, HeartRateDetail(average: 160))
        XCTAssertEqual(splits[0].isRest, false)

        XCTAssertEqual(splits[1].index, 1)
        XCTAssertEqual(splits[1].distance, 0)
        XCTAssertEqual(splits[1].time, 30, accuracy: 0.001)
        XCTAssertEqual(splits[1].pace, 0, accuracy: 0.001)
        XCTAssertNil(splits[1].cadence)
        XCTAssertNil(splits[1].heartRate)
        XCTAssertEqual(splits[1].isRest, true)
    }

    func testPaceToWattsAppliesBikeAdjustmentAfterNormalization() {
        XCTAssertEqual(Concept2Mapper.paceToWatts(sport: .rower, pace: 120), 203)
        XCTAssertEqual(Concept2Mapper.paceToWatts(sport: .skierg, pace: 120), 203)
        XCTAssertEqual(Concept2Mapper.paceToWatts(sport: .bike, pace: 120), 25)
        XCTAssertEqual(Concept2Mapper.paceToWatts(sport: .bike, pace: 0), 0)
    }

    private func expectedDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: value)!
    }
}
