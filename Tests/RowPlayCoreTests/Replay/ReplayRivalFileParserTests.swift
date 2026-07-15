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
