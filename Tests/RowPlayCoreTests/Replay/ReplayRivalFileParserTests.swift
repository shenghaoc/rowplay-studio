import XCTest
@testable import RowPlayCore

final class ReplayRivalFileParserTests: XCTestCase {
    private struct FixtureFile: Decodable {
        let csv: [TextCase]
        let tcx: [TextCase]
        let fit: [BinaryCase]
        let normalization: [TextCase]
    }

    private struct TextCase: Decodable {
        let label: String
        let fileName: String
        let content: String
        let expectSuccess: Bool
        let minStrokes: Int?
        let expectDerivedPace: Bool?
        let expectHr: Bool?
        let expectCadence: Bool?
        let expectWatts: Bool?
        let expectedPaceAtIndex1: Double?
        let expectedTimeAtIndex0: Double?
        let expectedTimeAtIndex1: Double?
        let expectedTimeAtIndex2: Double?
    }

    private struct BinaryCase: Decodable {
        let label: String
        let fileName: String
        let base64: String
        let expectSuccess: Bool
        let minStrokes: Int?
        let expectedTimeAtIndex0: Double?
        let expectedTimeAtIndex1: Double?
        let expectedDistanceAtIndex1: Double?
        let expectDerivedPace: Bool?
        let expectHr: Bool?
    }

    private static let fixtureResult = Result {
        try ParityFixtureLoader.loadJSON(FixtureFile.self, from: "replay-rival-sources-parity")
    }

    func testCSVParityCases() throws {
        let fixture = try Self.fixtureResult.get()
        for c in fixture.csv {
            let data = Data(c.content.utf8)
            if c.expectSuccess {
                let parsed = try ReplayRivalFileParser.parse(data: data, fileName: c.fileName)
                XCTAssertGreaterThanOrEqual(parsed.strokes.count, c.minStrokes ?? 2, c.label)
                XCTAssertEqual(parsed.fileName, c.fileName, c.label)
                assertOptionalExpectations(c, strokes: parsed.strokes)
            } else {
                XCTAssertThrowsError(
                    try ReplayRivalFileParser.parse(data: data, fileName: c.fileName),
                    c.label
                )
            }
        }
    }

    func testTCXParityCases() throws {
        let fixture = try Self.fixtureResult.get()
        for c in fixture.tcx {
            let data = Data(c.content.utf8)
            if c.expectSuccess {
                let parsed = try ReplayRivalFileParser.parse(data: data, fileName: c.fileName)
                XCTAssertGreaterThanOrEqual(parsed.strokes.count, c.minStrokes ?? 2, c.label)
                assertOptionalExpectations(c, strokes: parsed.strokes)
            } else {
                XCTAssertThrowsError(
                    try ReplayRivalFileParser.parse(data: data, fileName: c.fileName),
                    c.label
                )
            }
        }
    }

    func testTCXTimezoneLessTimestampIsTreatedAsUTC() throws {
        let tcx = """
        <TrainingCenterDatabase><Activities><Activity><Lap><Track>
        <Trackpoint><Time>2026-07-15T10:00:00</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
        <Trackpoint><Time>2026-07-15T10:00:10</Time><DistanceMeters>50</DistanceMeters></Trackpoint>
        </Track></Lap></Activity></Activities></TrainingCenterDatabase>
        """

        let parsed = try ReplayRivalFileParser.parse(data: Data(tcx.utf8), fileName: "naive.tcx")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[0].t, 0, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
    }

    func testFITParityCases() throws {
        let fixture = try Self.fixtureResult.get()
        for c in fixture.fit {
            guard let data = Data(base64Encoded: c.base64) else {
                return XCTFail("Invalid base64 for \(c.label)")
            }
            if c.expectSuccess {
                let parsed = try ReplayRivalFileParser.parse(data: data, fileName: c.fileName)
                XCTAssertGreaterThanOrEqual(parsed.strokes.count, c.minStrokes ?? 2, c.label)
                if let t0 = c.expectedTimeAtIndex0 {
                    XCTAssertEqual(parsed.strokes[0].t, t0, accuracy: 0.001, c.label)
                }
                if let t1 = c.expectedTimeAtIndex1 {
                    XCTAssertEqual(parsed.strokes[1].t, t1, accuracy: 0.001, c.label)
                }
                if let d1 = c.expectedDistanceAtIndex1 {
                    XCTAssertEqual(parsed.strokes[1].d, d1, accuracy: 0.01, c.label)
                }
                if c.expectDerivedPace == true {
                    XCTAssertGreaterThan(parsed.strokes[1].pace, 0, c.label)
                }
                if c.expectHr == true {
                    XCTAssertTrue(parsed.strokes.contains { $0.heartRate != nil }, c.label)
                }
            } else {
                XCTAssertThrowsError(
                    try ReplayRivalFileParser.parse(data: data, fileName: c.fileName),
                    c.label
                )
            }
        }
    }

    func testFITCompressedTimestampRecordsAreImported() throws {
        let parsed = try ReplayRivalFileParser.parse(
            data: makeCompressedTimestampFIT(),
            fileName: "compressed.fit"
        )

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[0].t, 0, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].t, 1, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 1, accuracy: 0.001)
    }

    func testFITDeclaredPayloadTruncationIsRejected() {
        var truncated = makeCompressedTimestampFIT()
        truncated.removeLast()

        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(data: truncated, fileName: "truncated.fit")
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .malformed)
        }
    }

    func testTCXPrefixedTrackpointsAreNamespaceInsensitive() throws {
        let tcx = """
        <?xml version="1.0"?>
        <tcx:TrainingCenterDatabase xmlns:tcx="urn:garmin:tcx">
          <tcx:Trackpoint>
            <tcx:Time>2026-07-15T10:00:00Z</tcx:Time>
            <tcx:DistanceMeters>0</tcx:DistanceMeters>
          </tcx:Trackpoint>
          <tcx:Trackpoint>
            <tcx:Time>2026-07-15T10:00:10Z</tcx:Time>
            <tcx:DistanceMeters>50</tcx:DistanceMeters>
          </tcx:Trackpoint>
        </tcx:TrainingCenterDatabase>
        """

        let parsed = try ReplayRivalFileParser.parse(data: Data(tcx.utf8), fileName: "prefixed.tcx")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 50, accuracy: 0.001)
    }

    func testTCXOutOfOrderTrackpointsAreSortedBeforeNormalization() throws {
        let tcx = """
        <TrainingCenterDatabase>
          <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>50</DistanceMeters></Trackpoint>
          <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
        </TrainingCenterDatabase>
        """

        let parsed = try ReplayRivalFileParser.parse(data: Data(tcx.utf8), fileName: "unordered.tcx")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[0].t, 0, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[0].d, 0, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 50, accuracy: 0.001)
    }

    func testMalformedTCXIsRejectedInsteadOfPartiallyImported() {
        let tcx = """
        <TrainingCenterDatabase>
          <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
          <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>50</DistanceMeters>
        </TrainingCenterDatabase>
        """

        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(data: Data(tcx.utf8), fileName: "broken.tcx")
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .malformed)
        }
    }

    func testTCXDocumentTypeIsRejectedToPreventEntityExpansion() {
        let tcx = """
        <?xml version="1.0"?>
        <!DOCTYPE TrainingCenterDatabase [<!ENTITY distance "50">]>
        <TrainingCenterDatabase>
          <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
          <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>&distance;</DistanceMeters></Trackpoint>
        </TrainingCenterDatabase>
        """

        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(data: Data(tcx.utf8), fileName: "entities.tcx")
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .malformed)
        }
    }

    func testNormalizationParityCases() throws {
        let fixture = try Self.fixtureResult.get()
        for c in fixture.normalization {
            let parsed = try ReplayRivalFileParser.parse(
                data: Data(c.content.utf8),
                fileName: c.fileName
            )
            assertOptionalExpectations(c, strokes: parsed.strokes)
        }
    }

    func testFileTooLargeRejected() {
        // Avoid allocating 25 MiB+ in CI: craft a data object and temporarily
        // rely on count check by using a small data with manual expectation
        // of the constant, then test with empty oversized simulated path.
        XCTAssertEqual(ReplayRivalFileParser.maximumFileSizeBytes, 25 * 1024 * 1024)
        // Create slightly oversized Data without filling content page-by-page when possible.
        let oversize = Data(count: ReplayRivalFileParser.maximumFileSizeBytes + 1)
        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(data: oversize, fileName: "huge.csv")
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .fileTooLarge)
        }
    }

    func testCSVSampleLimitIsEnforcedDuringStreamingScan() {
        var csv = "time,distance\n"
        csv.reserveCapacity(3_000_000)
        for index in 0...ReplayRivalFileParser.maximumAcceptedSamples {
            csv.append("\(index),\(index)\n")
        }

        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "too-many.csv")
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .tooManySamples)
        }
    }

    func testLastPathComponentOnlyInResult() throws {
        let csv = "time,distance\n0,0\n10,50\n20,100\n"
        let parsed = try ReplayRivalFileParser.parse(
            data: Data(csv.utf8),
            fileName: "/private/var/folders/xx/secret/rival.csv"
        )
        XCTAssertEqual(parsed.fileName, "rival.csv")
    }

    func testDerivedWattsFromPace() throws {
        let csv = "time,distance,pace\n0,0,2:00\n10,50,2:00\n20,100,2:00\n"
        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "w.csv")
        XCTAssertGreaterThan(parsed.strokes[1].watts, 0)
    }

    func testCSVStrokeRateNotMaskedByHeartRateColumn() throws {
        // heart_rate appears before a generic "rate" column; stroke rate must still bind.
        let csv = "time,distance,heart_rate,rate\n0,0,140,28\n10,50,145,30\n20,100,150,32\n"
        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "rate.csv")
        XCTAssertEqual(parsed.strokes[1].heartRate, 145)
        XCTAssertEqual(parsed.strokes[1].cadence, 30, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[2].cadence, 32, accuracy: 0.001)
    }

    func testCSVQuotedCommasAndEscapedQuotesPreserveColumns() throws {
        let csv = "note,time,distance\n\"First, steady\",0,0\n\"He said \"\"go\"\"\",10,\"1,000\"\n"
        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "quoted.csv")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 1_000, accuracy: 0.001)
    }

    func testCSVQuotedNewlinePreservesRecordBoundaries() throws {
        let csv = """
        note,time,distance
        "First
        steady",0,0
        "Finish",10,50
        """

        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "multiline.csv")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 50, accuracy: 0.001)
    }

    func testCSVUnbalancedQuoteIsRejected() {
        let csv = "time,distance,note\n0,0,\"unterminated\n10,50,still quoted\n"

        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "broken.csv")
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .malformed)
        }
    }

    func testCSVInvalidClockShapesAreRejected() {
        let invalidClocks = [
            ":",
            "::",
            "1:",
            ":30",
            "1::2",
            "1:2:3:4",
            "-1:30",
            "1.5:30",
            "1:2.5:30",
            "1:60",
            "1:60:00",
            "1:02:60",
        ]

        for clock in invalidClocks {
            let csv = "time,distance\n\(clock),0\n0:10,50\n"
            XCTAssertThrowsError(
                try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "invalid-clock.csv"),
                clock
            ) { error in
                XCTAssertEqual(error as? ReplayRivalFileParserError, .tooFewSamples, clock)
            }
        }
    }

    private func makeCompressedTimestampFIT() -> Data {
        var bytes: [UInt8] = [
            14, 0x10, 0, 0,
            0, 0, 0, 0,
            0x2E, 0x46, 0x49, 0x54,
            0, 0,
        ]
        let records: [UInt8] = [
            // Local-message definition: record (20), timestamp then distance.
            0x40, 0, 0, 20, 0, 2,
            253, 4, 0x86,
            5, 4, 0x86,
            // Normal record at t=1_000 with distance 0 cm.
            0x00, 0xE8, 0x03, 0, 0, 0, 0, 0, 0,
            // Compressed timestamp offset 9 => t=1_001, distance 100 cm.
            0x89, 0x64, 0, 0, 0,
        ]
        let dataSize = UInt32(records.count)
        bytes[4] = UInt8(dataSize & 0xFF)
        bytes[5] = UInt8((dataSize >> 8) & 0xFF)
        bytes[6] = UInt8((dataSize >> 16) & 0xFF)
        bytes[7] = UInt8((dataSize >> 24) & 0xFF)
        bytes.append(contentsOf: records)
        return Data(bytes)
    }

    private func assertOptionalExpectations(_ c: TextCase, strokes: [Stroke]) {
        if let t0 = c.expectedTimeAtIndex0 {
            XCTAssertEqual(strokes[0].t, t0, accuracy: 0.001, c.label)
        }
        if let t1 = c.expectedTimeAtIndex1 {
            XCTAssertEqual(strokes[1].t, t1, accuracy: 0.001, c.label)
        }
        if let t2 = c.expectedTimeAtIndex2 {
            XCTAssertEqual(strokes[2].t, t2, accuracy: 0.001, c.label)
        }
        if let pace = c.expectedPaceAtIndex1 {
            XCTAssertEqual(strokes[1].pace, pace, accuracy: 0.1, c.label)
        }
        if c.expectDerivedPace == true {
            for s in strokes.dropFirst() {
                XCTAssertTrue(s.pace.isFinite, c.label)
            }
        }
        if c.expectHr == true {
            XCTAssertTrue(strokes.contains { $0.heartRate != nil }, c.label)
        }
        if c.expectCadence == true {
            XCTAssertTrue(strokes.contains { $0.cadence > 0 }, c.label)
        }
        if c.expectWatts == true {
            XCTAssertTrue(strokes.contains { $0.watts > 0 }, c.label)
        }
    }
}
