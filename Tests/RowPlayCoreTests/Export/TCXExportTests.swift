import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import RowPlayCore

final class TCXExportTests: XCTestCase {

    // MARK: - Helpers

    private static let baseDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z

    private func makeWorkout(
        id: Int = 1,
        date: Date = baseDate,
        sport: Sport = .rower,
        distance: Double = 2000,
        time: TimeInterval = 480,
        pace: TimeInterval = 120,
        heartRateAvg: Int? = nil,
        caloriesTotal: Int? = nil,
        workoutType: String = "fixed_distance"
    ) -> Workout {
        Workout(
            id: id, date: date, sport: sport, distance: distance, time: time,
            pace: pace, heartRateAvg: heartRateAvg, caloriesTotal: caloriesTotal,
            workoutType: workoutType, hasStrokeData: true
        )
    }

    private func makeStroke(
        t: TimeInterval,
        d: Double,
        pace: TimeInterval = 120,
        cadence: Double = 28,
        heartRate: Int? = nil,
        watts: Int = 200
    ) -> Stroke {
        Stroke(t: t, d: d, pace: pace, cadence: cadence, heartRate: heartRate, watts: watts)
    }

    private func makeDetail(
        workout: Workout? = nil,
        strokes: [Stroke] = [],
        splits: [Split] = []
    ) -> WorkoutDetail {
        WorkoutDetail(workout: workout ?? makeWorkout(), strokes: strokes, splits: splits)
    }

    /// Parse XML and return true if well-formed.
    private func parseXML(_ xml: String) -> Bool {
        guard let data = xml.data(using: .utf8) else { return false }
        let parser = XMLParser(data: data)
        let delegate = TCXParserDelegate()
        parser.delegate = delegate
        return parser.parse() && delegate.isValid
    }

    // MARK: - XML Well-Formedness

    func testTCXIsWellFormedXML() {
        let detail = makeDetail()
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml), "TCX output must be well-formed XML")
    }

    func testTCXWithStrokesIsWellFormedXML() {
        let strokes = [
            makeStroke(t: 1, d: 4.2),
            makeStroke(t: 2, d: 8.3),
            makeStroke(t: 3, d: 12.5),
        ]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml), "TCX with strokes must be well-formed XML")
    }

    // MARK: - Namespace and Schema

    func testTCXHasCorrectNamespace() {
        let xml = WorkoutExport.tcx(makeDetail())
        XCTAssertTrue(xml.contains("xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\""))
    }

    func testTCXHasXsiNamespace() {
        let xml = WorkoutExport.tcx(makeDetail())
        XCTAssertTrue(xml.contains("xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""))
    }

    func testTCXHasSchemaLocation() {
        let xml = WorkoutExport.tcx(makeDetail())
        XCTAssertTrue(xml.contains("xsi:schemaLocation=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd\""))
    }

    // MARK: - Required Hierarchy

    func testTCXHasRequiredHierarchy() {
        let strokes = [makeStroke(t: 1, d: 4.2)]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<TrainingCenterDatabase"))
        XCTAssertTrue(xml.contains("<Activities>"))
        XCTAssertTrue(xml.contains("<Activity Sport="))
        XCTAssertTrue(xml.contains("<Lap StartTime="))
        XCTAssertTrue(xml.contains("<Track>"))
        XCTAssertTrue(xml.contains("<Trackpoint>"))
        XCTAssertTrue(xml.contains("</Trackpoint>"))
        XCTAssertTrue(xml.contains("</Track>"))
        XCTAssertTrue(xml.contains("</Lap>"))
        XCTAssertTrue(xml.contains("</Activity>"))
        XCTAssertTrue(xml.contains("</Activities>"))
        XCTAssertTrue(xml.contains("</TrainingCenterDatabase>"))
    }

    // MARK: - Activity ID and Lap StartTime

    func testTCXActivityIdIsUTCISO8601() {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        let detail = makeDetail(workout: makeWorkout(date: date))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<Id>2023-11-14T22:13:20Z</Id>"))
    }

    func testTCXLapStartTimeMatchesActivityId() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let detail = makeDetail(workout: makeWorkout(date: date))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<Lap StartTime=\"2023-11-14T22:13:20Z\">"))
    }

    // MARK: - Sport Mapping

    func testTCXSportRowerIsOther() {
        let detail = makeDetail(workout: makeWorkout(sport: .rower))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("Sport=\"Other\""))
    }

    func testTCXSportSkiErgIsOther() {
        let detail = makeDetail(workout: makeWorkout(sport: .skierg))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("Sport=\"Other\""))
    }

    func testTCXSportBikeErgIsBiking() {
        let detail = makeDetail(workout: makeWorkout(sport: .bike))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("Sport=\"Biking\""))
    }

    // MARK: - Summary Values

    func testTCXTotalTimeSeconds() {
        let detail = makeDetail(workout: makeWorkout(time: 600))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<TotalTimeSeconds>600.00</TotalTimeSeconds>"))
    }

    func testTCXTotalTimeSecondsPreservesFractionalDuration() {
        let detail = makeDetail(workout: makeWorkout(time: 480.7))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<TotalTimeSeconds>480.70</TotalTimeSeconds>"))
    }

    func testTCXDistanceMeters() {
        let detail = makeDetail(workout: makeWorkout(distance: 5000))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<DistanceMeters>5000.00</DistanceMeters>"))
    }

    func testTCXCaloriesPresent() {
        let detail = makeDetail(workout: makeWorkout(caloriesTotal: 150))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<Calories>150</Calories>"))
    }

    func testTCXCaloriesDefaultZeroWhenAbsent() {
        let detail = makeDetail(workout: makeWorkout(caloriesTotal: nil))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<Calories>0</Calories>"))
    }

    func testTCXAverageHeartRateBpmWhenPresent() {
        let detail = makeDetail(workout: makeWorkout(heartRateAvg: 145))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<AverageHeartRateBpm><Value>145</Value></AverageHeartRateBpm>"))
    }

    func testTCXNoAverageHeartRateBpmWhenAbsent() {
        let detail = makeDetail(workout: makeWorkout(heartRateAvg: nil))
        let xml = WorkoutExport.tcx(detail)
        XCTAssertFalse(xml.contains("AverageHeartRateBpm"))
    }

    func testTCXOmitsAverageHeartRateOutsideValidRange() {
        for heartRate in [0, 256] {
            let detail = makeDetail(workout: makeWorkout(heartRateAvg: heartRate))
            let xml = WorkoutExport.tcx(detail)
            XCTAssertFalse(xml.contains("AverageHeartRateBpm"))
        }
    }

    func testTCXIntensityIsManual() {
        let xml = WorkoutExport.tcx(makeDetail())
        XCTAssertTrue(xml.contains("<Intensity>Active</Intensity>"))
        XCTAssertTrue(xml.contains("<TriggerMethod>Manual</TriggerMethod>"))
    }

    // MARK: - Trackpoints

    func testTCXTrackpointsOrderedByTime() {
        let strokes = [
            makeStroke(t: 3, d: 12.5),
            makeStroke(t: 1, d: 4.2),
            makeStroke(t: 2, d: 8.3),
        ]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)

        let time1 = "2023-11-14T22:13:21.000Z"
        let time2 = "2023-11-14T22:13:22.000Z"
        let time3 = "2023-11-14T22:13:23.000Z"

        let idx1 = xml.range(of: time1)!.lowerBound
        let idx2 = xml.range(of: time2)!.lowerBound
        let idx3 = xml.range(of: time3)!.lowerBound

        XCTAssertTrue(idx1 < idx2)
        XCTAssertTrue(idx2 < idx3)
    }

    func testTCXTrackpointAbsoluteTimestamps() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let strokes = [makeStroke(t: 1, d: 4.2)]
        let detail = makeDetail(workout: makeWorkout(date: date), strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<Time>2023-11-14T22:13:21.000Z</Time>"))
    }

    func testTCXPreservesDistinctSubSecondTrackpoints() {
        let strokes = [
            makeStroke(t: 1.1, d: 4.2),
            makeStroke(t: 1.2, d: 4.6),
        ]
        let xml = WorkoutExport.tcx(makeDetail(strokes: strokes))

        XCTAssertEqual(xml.components(separatedBy: "<Trackpoint>").count - 1, 2)
        XCTAssertTrue(xml.contains("<Time>2023-11-14T22:13:21.100Z</Time>"))
        XCTAssertTrue(xml.contains("<Time>2023-11-14T22:13:21.200Z</Time>"))
    }

    func testTCXTrackpointDistance() {
        let strokes = [makeStroke(t: 1, d: 4.20)]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<DistanceMeters>4.20</DistanceMeters>"))
    }

    func testTCXTrackpointHeartRate() {
        let strokes = [makeStroke(t: 1, d: 4.2, heartRate: 130)]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<HeartRateBpm><Value>130</Value></HeartRateBpm>"))
    }

    func testTCXTrackpointCadence() {
        let strokes = [makeStroke(t: 1, d: 4.2, cadence: 28.7)]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<Cadence>29</Cadence>")) // rounded
    }

    func testTCXTrackpointNoHeartRateWhenZero() {
        let strokes = [makeStroke(t: 1, d: 4.2, heartRate: 0)]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        // The trackpoint should not have HeartRateBpm for HR=0
        let trackpointSection = xml.components(separatedBy: "<Trackpoint>").dropFirst().joined()
        XCTAssertFalse(trackpointSection.contains("HeartRateBpm"))
    }

    func testTCXTrackpointNoHeartRateWhenAbsent() {
        let strokes = [makeStroke(t: 1, d: 4.2, heartRate: nil)]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        let trackpointSection = xml.components(separatedBy: "<Trackpoint>").dropFirst().joined()
        XCTAssertFalse(trackpointSection.contains("HeartRateBpm"))
    }

    // MARK: - Missing HR/Calories

    func testTCXNoHeartRateElementsWhenAllNil() {
        let strokes = [
            makeStroke(t: 1, d: 4.2, heartRate: nil),
            makeStroke(t: 2, d: 8.3, heartRate: nil),
        ]
        let detail = makeDetail(
            workout: makeWorkout(heartRateAvg: nil),
            strokes: strokes
        )
        let xml = WorkoutExport.tcx(detail)
        XCTAssertFalse(xml.contains("HeartRateBpm"))
    }

    // MARK: - No-Stroke Workout

    func testTCXNoStrokeWorkoutHasNoTrack() {
        let detail = makeDetail(strokes: [])
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml))
        XCTAssertFalse(xml.contains("<Track>"))
        XCTAssertTrue(xml.contains("<TotalTimeSeconds>"))
        XCTAssertTrue(xml.contains("<DistanceMeters>"))
    }

    // MARK: - Invalid/Non-Finite Samples

    func testTCXSkipsNaNTimestamp() {
        let strokes = [
            makeStroke(t: .nan, d: 4.2),
            makeStroke(t: 1, d: 4.2),
        ]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml))
        XCTAssertFalse(xml.contains("NaN"))
        XCTAssertFalse(xml.contains("nan"))
        XCTAssertFalse(xml.contains("Infinity"))
    }

    func testTCXSkipsInfinityTimestamp() {
        let strokes = [
            makeStroke(t: .infinity, d: 4.2),
            makeStroke(t: 1, d: 4.2),
        ]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml))
        XCTAssertFalse(xml.contains("Infinity"))
        XCTAssertFalse(xml.contains("inf"))
    }

    func testTCXSkipsNegativeTimestamp() {
        let strokes = [
            makeStroke(t: -1, d: 4.2),
            makeStroke(t: 1, d: 4.2),
        ]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml))
        // Should have exactly one trackpoint
        XCTAssertEqual(xml.components(separatedBy: "<Trackpoint>").count - 1, 1)
    }

    func testTCXSkipsNaNDistance() {
        let strokes = [
            makeStroke(t: 1, d: .nan),
            makeStroke(t: 2, d: 4.2),
        ]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml))
        XCTAssertFalse(xml.contains("NaN"))
    }

    func testTCXSkipsNegativeDistance() {
        let strokes = [
            makeStroke(t: 1, d: -5),
            makeStroke(t: 2, d: 4.2),
        ]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml))
        XCTAssertEqual(xml.components(separatedBy: "<Trackpoint>").count - 1, 1)
    }

    func testTCXNoNaNOrInfinityInOutput() {
        let strokes = [
            makeStroke(t: .nan, d: .nan),
            makeStroke(t: .infinity, d: .infinity),
            makeStroke(t: -1, d: -1),
            makeStroke(t: 1, d: 4.2, cadence: .nan),
            makeStroke(t: 2, d: 8.3, heartRate: 256), // out of range
        ]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        let lower = xml.lowercased()
        XCTAssertFalse(lower.contains("nan"))
        XCTAssertFalse(lower.contains("inf"))
        XCTAssertTrue(parseXML(xml))
    }

    // MARK: - Non-Finite Workout Summary

    func testTCXHandlesNonFiniteWorkoutTime() {
        // Int(NaN) would crash — verify we produce valid XML instead
        let w = Workout(
            id: 1, date: Self.baseDate, sport: .rower, distance: 2000,
            time: .nan, pace: 120, workoutType: "fixed_distance", hasStrokeData: true
        )
        let detail = makeDetail(workout: w)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml))
        XCTAssertTrue(xml.contains("<TotalTimeSeconds>0.00</TotalTimeSeconds>"))
        XCTAssertFalse(xml.lowercased().contains("nan"))
    }

    func testTCXHandlesInfiniteWorkoutTime() {
        let w = Workout(
            id: 1, date: Self.baseDate, sport: .rower, distance: 2000,
            time: .infinity, pace: 120, workoutType: "fixed_distance", hasStrokeData: true
        )
        let detail = makeDetail(workout: w)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml))
        XCTAssertTrue(xml.contains("<TotalTimeSeconds>0.00</TotalTimeSeconds>"))
        XCTAssertFalse(xml.lowercased().contains("inf"))
    }

    func testTCXHandlesNonFiniteWorkoutDistance() {
        let w = Workout(
            id: 1, date: Self.baseDate, sport: .rower, distance: .nan,
            time: 480, pace: 120, workoutType: "fixed_distance", hasStrokeData: true
        )
        let detail = makeDetail(workout: w)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(parseXML(xml))
        XCTAssertTrue(xml.contains("<DistanceMeters>0.00</DistanceMeters>"))
        XCTAssertFalse(xml.lowercased().contains("nan"))
    }

    func testTCXOmitsTrackWhenWorkoutSummaryIsNonFinite() {
        let strokes = [makeStroke(t: 1, d: 4.2)]
        let invalidSummaries = [
            makeWorkout(distance: .infinity),
            makeWorkout(time: .infinity),
        ]

        for workout in invalidSummaries {
            let xml = WorkoutExport.tcx(makeDetail(workout: workout, strokes: strokes))
            XCTAssertFalse(xml.contains("<Track>"))
        }
    }

    // MARK: - Duplicate Timestamp Handling

    func testTCXDeduplicatesIdenticalTimestamps() {
        // Two strokes at same offset t=1 → same absolute timestamp
        let strokes = [
            makeStroke(t: 1, d: 4.2, heartRate: 130),
            makeStroke(t: 1, d: 4.2, heartRate: 140), // duplicate
        ]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertEqual(xml.components(separatedBy: "<Trackpoint>").count - 1, 1)
        // First occurrence wins
        XCTAssertTrue(xml.contains("<Value>130</Value>"))
    }

    // MARK: - Deterministic Output

    func testTCXOutputIsDeterministic() {
        let strokes = [
            makeStroke(t: 1, d: 4.2),
            makeStroke(t: 2, d: 8.3),
            makeStroke(t: 3, d: 12.5),
        ]
        let detail = makeDetail(strokes: strokes)
        let xml1 = WorkoutExport.tcx(detail)
        let xml2 = WorkoutExport.tcx(detail)
        XCTAssertEqual(xml1, xml2)
    }

    // MARK: - Privacy Exclusions

    func testTCXContainsNoComments() {
        let w = makeWorkout()
        // Workout has comments field but TCX should not include it
        let detail = makeDetail(workout: w)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertFalse(xml.contains("<Notes>"))
        XCTAssertFalse(xml.contains("<comments"))
    }

    func testTCXContainsNoSourceOrHardwareMetadata() {
        let xml = WorkoutExport.tcx(makeDetail())
        XCTAssertFalse(xml.contains("<Creator"))
        XCTAssertFalse(xml.contains("<Author"))
        XCTAssertFalse(xml.contains("<Device"))
        XCTAssertFalse(xml.contains("<UnitId"))
        XCTAssertFalse(xml.contains("<ProductID"))
        XCTAssertFalse(xml.contains("<SerialNumber"))
        XCTAssertFalse(xml.contains("<Source"))
    }

    func testTCXContainsNoExtensions() {
        let xml = WorkoutExport.tcx(makeDetail())
        XCTAssertFalse(xml.contains("<Extensions"))
        XCTAssertFalse(xml.contains("<LX ")) // Garmin extensions
    }

    func testTCXContainsNoGPSOrAltitude() {
        let strokes = [makeStroke(t: 1, d: 4.2)]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertFalse(xml.contains("<Position"))
        XCTAssertFalse(xml.contains("<LatitudeDegrees"))
        XCTAssertFalse(xml.contains("<LongitudeDegrees"))
        XCTAssertFalse(xml.contains("<AltitudeMeters"))
    }

    // MARK: - Cadence Clamping

    func testTCXCadenceClampedToMax255() {
        let strokes = [makeStroke(t: 1, d: 4.2, cadence: 300)]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        XCTAssertTrue(xml.contains("<Cadence>255</Cadence>"))
    }

    func testTCXCadenceNegativeSkipped() {
        let strokes = [makeStroke(t: 1, d: 4.2, cadence: -5)]
        let detail = makeDetail(strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        let trackpointSection = xml.components(separatedBy: "<Trackpoint>").dropFirst().joined()
        XCTAssertFalse(trackpointSection.contains("<Cadence>"))
    }

    // MARK: - Distance Clamping

    func testTCXDistanceClampedToWorkoutDistance() {
        let strokes = [
            makeStroke(t: 1, d: 4.2),
            makeStroke(t: 2, d: 3000), // exceeds workout distance 2000
        ]
        let detail = makeDetail(workout: makeWorkout(distance: 2000), strokes: strokes)
        let xml = WorkoutExport.tcx(detail)
        // Should clamp to 2000
        XCTAssertTrue(xml.contains("<DistanceMeters>2000.00</DistanceMeters>"))
    }

    // MARK: - Filenames

    func testTCXExportFilename() {
        let filename = WorkoutExport.workoutExportFilename(id: 42, ext: "tcx")
        XCTAssertEqual(filename, "rowplay-workout-42.tcx")
    }
}

// MARK: - XML Parser Delegates

private class TCXParserDelegate: NSObject, XMLParserDelegate {
    var isValid = true
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        isValid = false
    }
}
