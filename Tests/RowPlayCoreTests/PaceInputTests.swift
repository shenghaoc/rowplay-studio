import XCTest
@testable import RowPlayCore

final class PaceInputTests: XCTestCase {
    // MARK: - parsePaceInput

    func testParseMinutesColonSeconds() {
        XCTAssertEqual(PaceInput.parsePaceInput("2:00"), 120)
        XCTAssertEqual(PaceInput.parsePaceInput("1:30"), 90)
        XCTAssertEqual(PaceInput.parsePaceInput("7:05"), 425)
    }

    func testParseWithDecimalSeconds() {
        let result = PaceInput.parsePaceInput("2:05.5")
        XCTAssertNotNil(result)
        XCTAssertEqual(result ?? 0, 125.5, accuracy: 0.01)
    }

    func testParseBareSeconds() {
        XCTAssertEqual(PaceInput.parsePaceInput("90"), 90)
        let result = PaceInput.parsePaceInput("120.5")
        XCTAssertNotNil(result)
        XCTAssertEqual(result ?? 0, 120.5, accuracy: 0.01)
    }

    func testParseTrimsWhitespace() {
        XCTAssertEqual(PaceInput.parsePaceInput("  2:00  "), 120)
    }

    func testParseRejectsLongRawInputBeforeTrimming() {
        let padded = String(repeating: " ", count: 1_000) + "2:00"
        XCTAssertNil(PaceInput.parsePaceInput(padded))
    }

    func testParseReturnsNilForInvalid() {
        XCTAssertNil(PaceInput.parsePaceInput(""))
        XCTAssertNil(PaceInput.parsePaceInput("abc"))
        XCTAssertNil(PaceInput.parsePaceInput("0:00"))
        XCTAssertNil(PaceInput.parsePaceInput("-1:30"))
        XCTAssertNil(PaceInput.parsePaceInput("1:60"))
        XCTAssertNil(PaceInput.parsePaceInput("1:90"))
        XCTAssertNil(PaceInput.parsePaceInput("1e2"))
    }

    func testParseReturnsNilForZero() {
        XCTAssertNil(PaceInput.parsePaceInput("0"))
        XCTAssertNil(PaceInput.parsePaceInput("0:00"))
    }

    // MARK: - formatPaceInput

    func testFormatWholeSeconds() {
        XCTAssertEqual(PaceInput.formatPaceInput(120), "2:00")
        XCTAssertEqual(PaceInput.formatPaceInput(90), "1:30")
        XCTAssertEqual(PaceInput.formatPaceInput(425), "7:05")
    }

    func testFormatRoundsToNearestSecond() {
        XCTAssertEqual(PaceInput.formatPaceInput(120.4), "2:00")
        XCTAssertEqual(PaceInput.formatPaceInput(120.6), "2:01")
    }

    func testFormatReturnsEmptyForNonPositive() {
        XCTAssertEqual(PaceInput.formatPaceInput(0), "")
        XCTAssertEqual(PaceInput.formatPaceInput(-5), "")
    }

    func testFormatReturnsEmptyForNonFinite() {
        XCTAssertEqual(PaceInput.formatPaceInput(.infinity), "")
        XCTAssertEqual(PaceInput.formatPaceInput(.nan), "")
    }

    // MARK: - Round-trip

    func testRoundTrip() {
        let inputs = ["1:30", "2:00", "7:05", "10:00", "1:59"]
        for input in inputs {
            guard let parsed = PaceInput.parsePaceInput(input) else {
                XCTFail("Failed to parse: \(input)")
                return
            }
            let formatted = PaceInput.formatPaceInput(parsed)
            let reparsed = PaceInput.parsePaceInput(formatted)
            XCTAssertNotNil(reparsed, "Round-trip failed for \(input) → \(formatted)")
            if let reparsed {
                XCTAssertEqual(reparsed, parsed, accuracy: 0.5,
                               "Round-trip failed for \(input) → \(formatted)")
            }
        }
    }
}
