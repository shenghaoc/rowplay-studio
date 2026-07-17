import AppKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayRaceCardTests: XCTestCase {
    func testPNGDataIsNonEmptyWithValidSignature() {
        let report = makeReport(kind: .constantPace, outcome: .playerWon)
        guard let png = ReplayRaceCardRenderer.renderPNG(report: report, colorScheme: .light) else {
            return XCTFail("Expected PNG data")
        }
        XCTAssertFalse(png.isEmpty)
        // PNG signature: 89 50 4E 47 0D 0A 1A 0A
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(png.prefix(8)), signature)
    }

    func testDarkAppearanceAlsoRendersPNG() {
        let report = makeReport(kind: .session, outcome: .tie)
        guard let png = ReplayRaceCardRenderer.renderPNG(report: report, colorScheme: .dark) else {
            return XCTFail("Expected dark PNG data")
        }
        XCTAssertGreaterThan(png.count, 32)
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testJSONReportRoundTripFromCardWorkflow() throws {
        let report = makeReport(kind: .importedFile, outcome: .rivalWon)
        let data = try ReplayRaceReportCodec.encode(report)
        let decoded = try ReplayRaceReportCodec.decode(data)
        XCTAssertEqual(decoded.outcome, .rivalWon)
        XCTAssertEqual(decoded.rival.kind, .importedFile)
        XCTAssertEqual(decoded.rival.label, "Imported rival")
        XCTAssertNotNil(decoded.rival.distance)
        XCTAssertNotNil(decoded.rival.time)
        XCTAssertNotNil(decoded.rival.pace)
    }

    func testForbiddenPrivacyFieldsAbsentFromEncodedReport() throws {
        let player = Workout(
            id: 99,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sport: .rower,
            distance: 2000,
            time: 480,
            pace: 120,
            workoutType: "FixedDistanceIntervals",
            comments: "private note",
            hasStrokeData: true
        )
        let rival = ReplayRival(
            id: "file-x",
            kind: .importedFile,
            displayLabel: "secret-path-workout.fit",
            strokes: [
                Stroke(t: 0, d: 0, pace: 120, cadence: 0, watts: 200),
                Stroke(t: 500, d: 2000, pace: 120, cadence: 0, watts: 200),
            ],
            hasGenuineStrokeData: false,
            localFileName: "secret-path-workout.fit"
        )
        let result = ReplayRaceResult(
            outcome: .playerWon,
            axis: .distance,
            timeMargin: 20,
            distanceMargin: 40
        )
        let report = ReplayRaceReportBuilder.build(player: player, rival: rival, result: result)
        let data = try ReplayRaceReportCodec.encode(report)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("secret-path-workout"))
        XCTAssertFalse(json.contains("private note"))
        XCTAssertFalse(json.contains("comments"))
        XCTAssertFalse(json.contains("localFileName"))
        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.contains("token"))
        XCTAssertFalse(json.contains("http://"))
        XCTAssertFalse(json.contains("https://"))
        XCTAssertFalse(json.contains("workoutID"))
        XCTAssertFalse(json.contains("sessionWorkoutID"))
        XCTAssertEqual(report.rival.label, "Imported rival")
    }

    func testTransferItemsHoldExpectedPayloads() {
        let reportData = Data("{\"schema\":\"rowplay-race-report\"}".utf8)
        let reportItem = ReplayRaceReportTransferItem(
            data: reportData,
            suggestedName: "race-report.json"
        )
        XCTAssertEqual(reportItem.suggestedName, "race-report.json")
        XCTAssertEqual(reportItem.data, reportData)

        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let cardItem = ReplayRaceCardTransferItem(
            data: pngSignature,
            suggestedName: "race-card.png"
        )
        XCTAssertEqual(cardItem.suggestedName, "race-card.png")
        XCTAssertEqual(Array(cardItem.data.prefix(8)), Array(pngSignature))
    }

    func testSuggestedExportFilenamesDoNotContainWorkoutIdentifiers() {
        XCTAssertEqual(ReplayRaceSuggestedFilename.report, "rowplay-race-report.json")
        XCTAssertEqual(ReplayRaceSuggestedFilename.card, "rowplay-race-card.png")
    }

    func testImportedRaceCardShowsSanitizedRivalPerformanceMetrics() {
        let report = makeReport(kind: .importedFile, outcome: .rivalWon)

        let lines = ReplayRaceCardView.rivalLines(for: report)

        XCTAssertTrue(lines.contains { $0.contains("2.00 km") && $0.contains("8:10.0") })
        XCTAssertTrue(lines.contains { $0.contains("Average") && $0.contains("/500m") })
        XCTAssertFalse(lines.joined().contains("should-not-appear"))
        XCTAssertFalse(lines.joined().contains(".fit"))
    }

    func testMetricRichCardKeepsAccentAndFooterInsideCanvas() throws {
        // A session result has the maximum rival-line count (date, result,
        // average pace), while a non-tie also renders both margin lines.
        let report = makeReport(kind: .session, outcome: .rivalWon)
        let png = try XCTUnwrap(ReplayRaceCardRenderer.renderPNG(
            report: report,
            colorScheme: .light
        ))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))

        let hasTopAccent = (0..<min(24, bitmap.pixelsHigh)).contains { y in
            return stride(from: 0, to: bitmap.pixelsWide, by: 8).contains { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    return false
                }
                return color.redComponent > 0.5
                    && color.redComponent > color.greenComponent * 2
            }
        }
        let footerStart = max(0, bitmap.pixelsHigh - 180)
        let hasFooterInk = stride(from: footerStart, to: bitmap.pixelsHigh, by: 2).contains { y in
            stride(from: 0, to: bitmap.pixelsWide, by: 4).contains { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    return false
                }
                return color.redComponent < 0.7
                    && color.greenComponent < 0.7
                    && color.blueComponent < 0.7
            }
        }

        XCTAssertTrue(hasTopAccent, "The top accent must not be clipped")
        XCTAssertTrue(hasFooterInk, "The footer must remain inside the fixed card canvas")
    }

    func testAccessibilityMetricsDoNotSpeakDecorativeSeparator() {
        XCTAssertEqual(
            ReplayRaceCardView.accessibilityText("2.00 km · 8:10.0"),
            "2.00 km, 8:10.0"
        )
    }

    private func makeReport(
        kind: ReplayRivalKind,
        outcome: ReplayRaceOutcome
    ) -> ReplayRaceReport {
        let player = Workout(
            id: 1,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sport: .rower,
            distance: 2000,
            time: 480,
            pace: 120,
            workoutType: "FixedDistanceIntervals",
            hasStrokeData: true
        )
        let rival: ReplayRival
        switch kind {
        case .session:
            rival = ReplayRival(
                id: "session-2",
                kind: .session,
                displayLabel: "2024-01-01",
                strokes: [
                    Stroke(t: 0, d: 0, pace: 125, cadence: 28, watts: 180),
                    Stroke(t: 500, d: 2000, pace: 125, cadence: 28, watts: 180),
                ],
                hasGenuineStrokeData: true,
                sessionWorkoutID: 2
            )
        case .constantPace:
            rival = ReplayRival(
                id: "pace-130",
                kind: .constantPace,
                displayLabel: "2:10/500m",
                strokes: [
                    Stroke(t: 0, d: 0, pace: 130, cadence: 0, watts: 150),
                    Stroke(t: 520, d: 2000, pace: 130, cadence: 0, watts: 150),
                ],
                hasGenuineStrokeData: false,
                targetPace: 130
            )
        case .importedFile:
            rival = ReplayRival(
                id: "file-1",
                kind: .importedFile,
                displayLabel: "Imported rival",
                strokes: [
                    Stroke(t: 0, d: 0, pace: 120, cadence: 0, watts: 200),
                    Stroke(t: 490, d: 2000, pace: 120, cadence: 0, watts: 200),
                ],
                hasGenuineStrokeData: false,
                localFileName: "should-not-appear.fit"
            )
        }
        let rivalFinishTime: TimeInterval = switch kind {
        case .session: 500
        case .constantPace: 520
        case .importedFile: 490
        }
        let result = ReplayRaceResult(
            outcome: outcome,
            axis: .distance,
            timeMargin: outcome == .tie ? 0 : 15,
            distanceMargin: outcome == .tie ? 0 : 50,
            rivalDidNotFinish: false,
            playerFinishTime: 480,
            rivalFinishTime: rivalFinishTime,
            playerDistance: 2000,
            rivalDistance: 2000
        )
        return ReplayRaceReportBuilder.build(
            player: player,
            rival: rival,
            result: result,
            sessionDate: kind == .session ? Date(timeIntervalSince1970: 1_600_000_000) : nil
        )
    }
}
