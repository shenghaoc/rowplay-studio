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
        let expectDerivedWatts: Bool?
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
        let expectDerivedWatts: Bool?
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
                if c.expectDerivedWatts == true {
                    XCTAssertTrue(parsed.strokes.dropFirst().allSatisfy { $0.watts > 0 }, c.label)
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

    func testFITCompressedTimestampEqualOffsetDoesNotRollOver() throws {
        let parsed = try ReplayRivalFileParser.parse(
            data: makeEqualOffsetCompressedTimestampFIT(),
            fileName: "equal-offset.fit"
        )
        let finalStroke = try XCTUnwrap(parsed.strokes.last)

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(finalStroke.t, 31, accuracy: 0.001)
        XCTAssertEqual(finalStroke.d, 2, accuracy: 0.001)
    }

    func testFITCompressedTimestampUsesBaseFromNonRecordMessage() throws {
        let parsed = try ReplayRivalFileParser.parse(
            data: makeNonRecordTimestampBaseFIT(),
            fileName: "non-record-base.fit"
        )

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[0].t, 0, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[0].d, 1, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].t, 1, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 2, accuracy: 0.001)
    }

    func testFITContentDetectionOverridesMisleadingCSVExtension() throws {
        let parsed = try ReplayRivalFileParser.parse(
            data: makeCompressedTimestampFIT(),
            fileName: "misleading.csv"
        )

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 1, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 1, accuracy: 0.001)
    }

    func testFITContentDetectionOverridesMisleadingTCXExtension() throws {
        let parsed = try ReplayRivalFileParser.parse(
            data: makeCompressedTimestampFIT(),
            fileName: "misleading.tcx"
        )

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 1, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 1, accuracy: 0.001)
    }

    func testFITSignatureDetectionSupportsNonzeroDataStartIndex() throws {
        var wrapped = Data([0xAA, 0xBB, 0xCC])
        wrapped.append(makeCompressedTimestampFIT())
        let slice = wrapped.dropFirst(3)
        XCTAssertGreaterThan(slice.startIndex, 0)

        let parsed = try ReplayRivalFileParser.parse(data: slice, fileName: "extensionless")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 1, accuracy: 0.001)
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

    func testFITInvalidDefinitionArchitectureIsRejected() {
        var data = makeCompressedTimestampFIT()
        let architectureIndex = data.index(data.startIndex, offsetBy: 16)
        data[architectureIndex] = 2

        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(data: data, fileName: "invalid-architecture.fit")
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

    func testExtensionlessNamespacedTCXIsDetectedFromStartElements() throws {
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

        let parsed = try ReplayRivalFileParser.parse(data: Data(tcx.utf8), fileName: "rival")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 50, accuracy: 0.001)
    }

    func testTCXContentDetectionOverridesMisleadingCSVExtension() throws {
        let tcx = """
        <TrainingCenterDatabase>
          <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
          <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>50</DistanceMeters></Trackpoint>
        </TrainingCenterDatabase>
        """

        let parsed = try ReplayRivalFileParser.parse(
            data: Data(tcx.utf8),
            fileName: "misleading.csv"
        )

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 50, accuracy: 0.001)
    }

    func testTCXContentDetectionOverridesMisleadingFITExtension() throws {
        let tcx = """
        <TrainingCenterDatabase>
          <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
          <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>50</DistanceMeters></Trackpoint>
        </TrainingCenterDatabase>
        """

        let parsed = try ReplayRivalFileParser.parse(
            data: Data(tcx.utf8),
            fileName: "misleading.fit"
        )

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 50, accuracy: 0.001)
    }

    func testExtensionlessUTF16NamespacedTCXIsDetectedFromStartElements() throws {
        let tcx = """
        <?xml version="1.0" encoding="UTF-16"?>
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
        var data = Data([0xFF, 0xFE])
        data.append(try XCTUnwrap(tcx.data(using: .utf16LittleEndian)))

        let parsed = try ReplayRivalFileParser.parse(data: data, fileName: "rival")

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

    func testUTF16TCXDocumentTypeIsRejectedToPreventEntityExpansion() throws {
        let tcx = """
        <?xml version="1.0" encoding="UTF-16"?>
        <!DOCTYPE TrainingCenterDatabase [<!ENTITY distance "50">]>
        <TrainingCenterDatabase>
          <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
          <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>&distance;</DistanceMeters></Trackpoint>
        </TrainingCenterDatabase>
        """
        var data = Data([0xFF, 0xFE])
        data.append(try XCTUnwrap(tcx.data(using: .utf16LittleEndian)))

        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(data: data, fileName: "entities.tcx")
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .malformed)
        }
    }

    func testUTF16TCXBareDocumentTypeIsRejectedWithoutDelegateDeclarations() throws {
        let tcx = """
        <?xml version="1.0" encoding="UTF-16"?>
        <!DOCTYPE TrainingCenterDatabase>
        <TrainingCenterDatabase>
          <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
          <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>50</DistanceMeters></Trackpoint>
        </TrainingCenterDatabase>
        """
        var data = Data([0xFF, 0xFE])
        data.append(try XCTUnwrap(tcx.data(using: .utf16LittleEndian)))

        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(data: data, fileName: "bare-doctype.tcx")
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .malformed)
        }
    }

    func testTCXDocumentTypeIsRejectedAcrossUnicodeByteOrders() throws {
        let encodings: [(name: String, declaration: String, encoding: String.Encoding, bom: [UInt8])] = [
            ("utf16-be", "UTF-16", .utf16BigEndian, [0xFE, 0xFF]),
            ("utf16-le-bomless", "UTF-16", .utf16LittleEndian, []),
            ("utf16-be-bomless", "UTF-16", .utf16BigEndian, []),
            ("utf32-le", "UTF-32", .utf32LittleEndian, [0xFF, 0xFE, 0x00, 0x00]),
            ("utf32-be", "UTF-32", .utf32BigEndian, [0x00, 0x00, 0xFE, 0xFF]),
            ("utf32-le-bomless", "UTF-32", .utf32LittleEndian, []),
            ("utf32-be-bomless", "UTF-32", .utf32BigEndian, []),
        ]

        for candidate in encodings {
            let tcx = """
            <?xml version="1.0" encoding="\(candidate.declaration)"?>
            <!DOCTYPE TrainingCenterDatabase>
            <TrainingCenterDatabase>
              <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
              <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>50</DistanceMeters></Trackpoint>
            </TrainingCenterDatabase>
            """
            var data = Data(candidate.bom)
            data.append(try XCTUnwrap(tcx.data(using: candidate.encoding)))

            XCTAssertThrowsError(
                try ReplayRivalFileParser.parse(
                    data: data,
                    fileName: "bare-doctype-\(candidate.name).tcx"
                ),
                candidate.name
            ) { error in
                XCTAssertEqual(error as? ReplayRivalFileParserError, .malformed, candidate.name)
            }
        }
    }

    func testTCXDocumentTypeScanSupportsNonzeroDataStartIndex() throws {
        let encodings: [(name: String, declaration: String, encoding: String.Encoding, bom: [UInt8])] = [
            ("utf8", "UTF-8", .utf8, []),
            ("utf16-le", "UTF-16", .utf16LittleEndian, [0xFF, 0xFE]),
            ("utf16-be", "UTF-16", .utf16BigEndian, [0xFE, 0xFF]),
            ("utf32-le", "UTF-32", .utf32LittleEndian, [0xFF, 0xFE, 0x00, 0x00]),
            ("utf32-be", "UTF-32", .utf32BigEndian, [0x00, 0x00, 0xFE, 0xFF]),
        ]

        for candidate in encodings {
            let tcx = """
            <?xml version="1.0" encoding="\(candidate.declaration)"?>
            <!DOCTYPE TrainingCenterDatabase>
            <TrainingCenterDatabase>
              <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
              <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>50</DistanceMeters></Trackpoint>
            </TrainingCenterDatabase>
            """
            var wrapped = Data([0xAA, 0xBB, 0xCC])
            wrapped.append(contentsOf: candidate.bom)
            wrapped.append(try XCTUnwrap(tcx.data(using: candidate.encoding)))
            let slice = wrapped.dropFirst(3)
            XCTAssertNotEqual(slice.startIndex, 0, candidate.name)

            XCTAssertThrowsError(
                try ReplayRivalFileParser.parse(
                    data: slice,
                    fileName: "sliced-doctype-\(candidate.name).tcx"
                ),
                candidate.name
            ) { error in
                XCTAssertEqual(error as? ReplayRivalFileParserError, .malformed, candidate.name)
            }
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

    func testNormalizationCollapsesEqualTimestampsToFarthestDistance() throws {
        let csv = """
        time,distance,cadence
        0,0,20
        10,40,22
        10,50,24
        20,100,26
        """

        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "duplicates.csv")

        XCTAssertEqual(parsed.strokes.map(\.t), [0, 10, 20])
        XCTAssertEqual(parsed.strokes.map(\.d), [0, 50, 100])
        XCTAssertEqual(parsed.strokes[1].cadence, 24, accuracy: 0.001)
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
        let cases = [
            "/private/var/folders/xx/secret/rival.csv",
            #"C:\Users\secret\rival.csv"#,
            #"C:\Users\secret/exports\rival.csv"#,
            #"/Users/secret\exports/rival.csv"#,
            "/private/var/folders/xx/secret/rival.csv/",
            #"C:\Users\secret\rival.csv\"#,
        ]

        for fileName in cases {
            let parsed = try ReplayRivalFileParser.parse(
                data: Data(csv.utf8),
                fileName: fileName
            )
            XCTAssertEqual(parsed.fileName, "rival.csv", fileName)
        }
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

    func testCSVPrefersElapsedOverTimestampAndAcceptsDistAlias() throws {
        let csv = """
        timestamp,elapsed,dist,parameter
        2026-01-01T00:00:00Z,0,0,999
        2026-01-01T00:00:10Z,10,50,999
        2026-01-01T00:00:20Z,20,100,999
        """
        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "aliases.csv")
        XCTAssertEqual(parsed.strokes.map(\.t), [0, 10, 20])
        XCTAssertEqual(parsed.strokes.map(\.d), [0, 50, 100])
    }

    func testCSVAcceptsCommonCompoundHeaders() throws {
        let csv = """
        elapsedTime,distanceMeters,avgPace,strokeRate,heartRate,powerWatts,timestamp,parameter
        0,0,2:00,28,140,200,2026-01-01T00:00:00Z,999
        10,50,1:59,29,141,210,2026-01-01T00:00:10Z,999
        """

        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "compound.csv")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 50, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].pace, 119, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].cadence, 29, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].heartRate, 141)
        XCTAssertEqual(parsed.strokes[1].watts, 210)
    }

    func testCSVEuropeanDecimalCommaIsAccepted() throws {
        let csv = "time,distance\n0,0\n10,\"1,5\"\n20,\"3,0\"\n"
        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "eu.csv")
        XCTAssertEqual(parsed.strokes[1].d, 1.5, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[2].d, 3.0, accuracy: 0.001)
    }

    func testCSVUSThousandsCommaStillParsesAsIntegerDistance() throws {
        let csv = "time,distance\n0,0\n10,\"1,000\"\n20,\"2,000\"\n"
        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "us.csv")
        XCTAssertEqual(parsed.strokes[1].d, 1_000, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[2].d, 2_000, accuracy: 0.001)
    }

    func testCSVExtensionIsNotHijackedByEmbeddedFITSignature() throws {
        // Bytes 8-11 of the whole payload are ".FIT", but the surrounding
        // bytes do not form a structurally plausible FIT header.
        let csv = "noteXXXX.FIT,time,distance\nx,0,0\nx,10,50\n"
        let bytes = Array(csv.utf8)
        XCTAssertEqual(Array(bytes[8..<12]), [0x2E, 0x46, 0x49, 0x54])

        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "trap.csv")
        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 50, accuracy: 0.001)
    }

    func testDOCTYPEScanAcceptsSlicedDataWithNonzeroStartIndex() throws {
        let tcx = """
        <?xml version="1.0"?>
        <!DOCTYPE TrainingCenterDatabase>
        <TrainingCenterDatabase>
          <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
          <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>50</DistanceMeters></Trackpoint>
        </TrainingCenterDatabase>
        """
        var padded = Data(repeating: 0x20, count: 32)
        padded.append(contentsOf: tcx.utf8)
        // Range-subscript slices preserve the base startIndex; subdata does not.
        let sliced = padded[32..<padded.count]
        XCTAssertNotEqual(sliced.startIndex, 0)

        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(data: sliced, fileName: "slice.tcx")
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .malformed)
        }
    }

    func testCSVOutOfRangeOptionalMetricsAreSanitized() throws {
        let unrepresentableInt = "9223372036854775808"
        let csv = """
        time,distance,pace,heart_rate,watts
        0,0,2:00,\(unrepresentableInt),\(unrepresentableInt)
        10,50,2:00,\(unrepresentableInt),\(unrepresentableInt)
        """

        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "metrics.csv")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertTrue(parsed.strokes.allSatisfy { $0.heartRate == nil })
        XCTAssertTrue(parsed.strokes.allSatisfy { $0.watts > 0 })
    }

    func testTCXOutOfRangeOptionalMetricsAreSanitized() throws {
        let tcx = """
        <TrainingCenterDatabase>
          <Trackpoint>
            <Time>2026-07-15T10:00:00Z</Time>
            <DistanceMeters>0</DistanceMeters>
            <HeartRateBpm><Value>9223372036854775808</Value></HeartRateBpm>
            <Watts>9223372036854775808</Watts>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-07-15T10:00:10Z</Time>
            <DistanceMeters>50</DistanceMeters>
            <HeartRateBpm><Value>9223372036854775808</Value></HeartRateBpm>
            <Watts>9223372036854775808</Watts>
          </Trackpoint>
        </TrainingCenterDatabase>
        """

        let parsed = try ReplayRivalFileParser.parse(data: Data(tcx.utf8), fileName: "metrics.tcx")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertTrue(parsed.strokes.allSatisfy { $0.heartRate == nil })
        XCTAssertGreaterThan(parsed.strokes[1].watts, 0)
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

    func testCSVUnicodeScalarScannerPreservesUnicodeAndCRLFQuotedFields() throws {
        let csv = "note,time,distance\r\n\"café 🚣\r\nsteady\",0,0\r\n\"Finish\",10,50\r\n"

        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "unicode.csv")

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

    func testCSVHeaderOnlyReportsNoUsableSamples() {
        XCTAssertThrowsError(
            try ReplayRivalFileParser.parse(
                data: Data("time,distance\n".utf8),
                fileName: "header-only.csv"
            )
        ) { error in
            XCTAssertEqual(error as? ReplayRivalFileParserError, .unsupportedOrEmpty)
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

    func testCSVBareTrackpointNoteIsNotMisdetectedAsTCX() throws {
        let csv = "note,time,distance\nTrackpoint,0,0\nSteady,10,50\n"

        let parsed = try ReplayRivalFileParser.parse(data: Data(csv.utf8), fileName: "rival")

        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[1].t, 10, accuracy: 0.001)
        XCTAssertEqual(parsed.strokes[1].d, 50, accuracy: 0.001)
    }

    func testCSVCancellationPropagates() async {
        var csv = "note,time,distance\n\""
        csv.append(String(repeating: "a", count: 4 * 1_024 * 1_024))
        csv.append("\",0,0\nfinish,10,50\n")
        await assertCancellationPropagates(data: Data(csv.utf8), fileName: "cancel.csv")
    }

    func testTCXCancellationPropagates() async {
        var tcx = "<TrainingCenterDatabase><Notes>"
        tcx.append(String(repeating: "a", count: 4 * 1_024 * 1_024))
        tcx.append("""
        </Notes>
        <Trackpoint><Time>2026-07-15T10:00:00Z</Time><DistanceMeters>0</DistanceMeters></Trackpoint>
        <Trackpoint><Time>2026-07-15T10:00:10Z</Time><DistanceMeters>50</DistanceMeters></Trackpoint>
        </TrainingCenterDatabase>
        """)
        await assertCancellationPropagates(data: Data(tcx.utf8), fileName: "cancel.tcx")
    }

    func testFITCancellationPropagates() async {
        await assertCancellationPropagates(data: makeCancellationFIT(), fileName: "cancel.fit")
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

    private func makeEqualOffsetCompressedTimestampFIT() -> Data {
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
            // Normal record at t=1_000 (low five bits = 8), distance 0 cm.
            0x00, 0xE8, 0x03, 0, 0, 0, 0, 0, 0,
            // Equal offset 8 must remain at t=1_000, distance 100 cm.
            0x88, 0x64, 0, 0, 0,
            // Lower offset 7 then rolls over once to t=1_031, distance 200 cm.
            0x87, 0xC8, 0, 0, 0,
        ]
        let dataSize = UInt32(records.count)
        bytes[4] = UInt8(dataSize & 0xFF)
        bytes[5] = UInt8((dataSize >> 8) & 0xFF)
        bytes[6] = UInt8((dataSize >> 16) & 0xFF)
        bytes[7] = UInt8((dataSize >> 24) & 0xFF)
        bytes.append(contentsOf: records)
        return Data(bytes)
    }

    private func makeNonRecordTimestampBaseFIT() -> Data {
        var bytes: [UInt8] = [
            14, 0x10, 0, 0,
            0, 0, 0, 0,
            0x2E, 0x46, 0x49, 0x54,
            0, 0,
        ]
        let records: [UInt8] = [
            // Local 0 is a non-record message whose timestamp establishes the
            // compressed timestamp base shared by subsequent local messages.
            0x40, 0, 0, 21, 0, 1,
            253, 4, 0x86,
            0x00, 0xE8, 0x03, 0, 0,
            // Local 1 is a record message. Compressed records omit field 253.
            0x41, 0, 0, 20, 0, 2,
            253, 4, 0x86,
            5, 4, 0x86,
            // Offsets 9 and 10 resolve to timestamps 1_001 and 1_002.
            0xA9, 0x64, 0, 0, 0,
            0xAA, 0xC8, 0, 0, 0,
        ]
        let dataSize = UInt32(records.count)
        bytes[4] = UInt8(dataSize & 0xFF)
        bytes[5] = UInt8((dataSize >> 8) & 0xFF)
        bytes[6] = UInt8((dataSize >> 16) & 0xFF)
        bytes[7] = UInt8((dataSize >> 24) & 0xFF)
        bytes.append(contentsOf: records)
        return Data(bytes)
    }

    private func makeCancellationFIT() -> Data {
        let definition: [UInt8] = [
            0x40, 0, 0, 20, 0, 2,
            253, 4, 0x86,
            5, 4, 0x86,
        ]
        let record: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0]
        let recordCount = ReplayRivalFileParser.maximumAcceptedSamples
        let dataSize = UInt32(definition.count + record.count * recordCount)
        var bytes: [UInt8] = [
            14, 0x10, 0, 0,
            UInt8(dataSize & 0xFF),
            UInt8((dataSize >> 8) & 0xFF),
            UInt8((dataSize >> 16) & 0xFF),
            UInt8((dataSize >> 24) & 0xFF),
            0x2E, 0x46, 0x49, 0x54,
            0, 0,
        ]
        bytes.reserveCapacity(14 + Int(dataSize))
        bytes.append(contentsOf: definition)
        for _ in 0..<recordCount {
            bytes.append(contentsOf: record)
        }
        return Data(bytes)
    }

    private func assertCancellationPropagates(
        data: Data,
        fileName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let task = Task.detached {
            try ReplayRivalFileParser.parse(data: data, fileName: fileName)
        }
        try? await Task.sleep(for: .milliseconds(1))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError", file: file, line: line)
        } catch is CancellationError {
            // Expected: format-specific cancellation must not be remapped.
        } catch {
            XCTFail("Expected CancellationError, got \(error)", file: file, line: line)
        }
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
        if c.expectDerivedWatts == true {
            XCTAssertTrue(strokes.dropFirst().allSatisfy { $0.watts > 0 }, c.label)
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
