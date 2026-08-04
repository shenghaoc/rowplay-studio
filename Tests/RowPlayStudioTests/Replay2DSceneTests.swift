import AppKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class Replay2DSceneTests: XCTestCase {
    /// Fixed snapshot dimensions mirror the pinned web QA viewport. These ROI
    /// counts catch missing or collapsed geometry; they do not claim human
    /// visual approval of anatomy, depth, or palette quality.
    private let renderWidth = 960.0
    private let renderHeight = 460.0
    private let minimumParticipantInkPixels = 180
    private let minimumReducedMotionDifferencePixels = 60
    private let minimumIndependentRivalInkPixels = 160
    private let minimumVisibleColorDelta = 24.0

    func testEverySportPaintsParticipantPixelsBeyondVenue() throws {
        for sport in Sport.allCases {
            let (detail, state) = try replayFixture(sport: sport)
            let full = try renderScene(detail: detail, state: state, rival: nil, reduceMotion: false)
            let venue = try renderVenue(
                sport: sport,
                meters: state.currentFrame.d,
                reduceMotion: false
            )
            let mask = differenceMask(
                full,
                venue,
                canvasROI: participantROI(sport: sport, centerX: liveX)
            )
            XCTAssertGreaterThan(
                mask.count,
                minimumParticipantInkPixels,
                "\(sport.rawValue) participant renderer added no meaningful pixels"
            )

            if let directory = ProcessInfo.processInfo.environment["ROWPLAY_CAPTURE_2D_QA_DIR"],
               let png = full.representation(using: .png, properties: [:]) {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                    .appendingPathComponent("\(sport.rawValue)-motion.png")
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try png.write(to: url, options: .atomic)
            }
        }
    }

    func testNormalAndReducedMotionProduceDifferentParticipantMasks() throws {
        for sport in Sport.allCases {
            let (detail, state) = try replayFixture(sport: sport)
            let roi = participantROI(sport: sport, centerX: liveX)
            let normal = differenceMask(
                try renderScene(detail: detail, state: state, rival: nil, reduceMotion: false),
                try renderVenue(sport: sport, meters: state.currentFrame.d, reduceMotion: false),
                canvasROI: roi
            )
            let reduced = differenceMask(
                try renderScene(detail: detail, state: state, rival: nil, reduceMotion: true),
                try renderVenue(sport: sport, meters: state.currentFrame.d, reduceMotion: true),
                canvasROI: roi
            )
            XCTAssertGreaterThan(
                normal.symmetricDifference(reduced).count,
                minimumReducedMotionDifferencePixels,
                "\(sport.rawValue) reduced motion did not change participant articulation"
            )
        }
    }

    func testEverySportPaintsIndependentGenuineRival() throws {
        for sport in Sport.allCases {
            let (detail, state) = try replayFixture(sport: sport)
            let rival = ReplayRival(
                id: "roi-rival-\(sport.rawValue)",
                kind: .session,
                displayLabel: "Rival",
                strokes: detail.strokes.map {
                    Stroke(
                        t: $0.t,
                        d: $0.d + 180,
                        pace: $0.pace,
                        cadence: $0.cadence,
                        heartRate: $0.heartRate,
                        watts: $0.watts
                    )
                },
                hasGenuineStrokeData: true,
                sessionWorkoutID: detail.id
            )
            let ghostDistance = ReplayRaceGap.ghostDistance(
                elapsed: state.time,
                strokes: rival.strokes
            )
            let pixelsPerMeter = max(
                0.12,
                min(0.7, renderWidth / max(500, detail.workout.distance))
            )
            let ghostX = max(
                Replay2DStyle.padLeading,
                min(
                    renderWidth - Replay2DStyle.padTrailing,
                    liveX + (ghostDistance - state.currentFrame.d) * pixelsPerMeter
                )
            )
            let withRival = try renderScene(
                detail: detail,
                state: state,
                rival: rival,
                reduceMotion: false
            )
            let solo = try renderScene(
                detail: detail,
                state: state,
                rival: nil,
                reduceMotion: false
            )
            XCTAssertGreaterThan(
                differenceMask(
                    withRival,
                    solo,
                    canvasROI: participantROI(sport: sport, centerX: ghostX)
                ).count,
                minimumIndependentRivalInkPixels,
                "\(sport.rawValue) genuine rival did not render independently"
            )
        }
    }

    func testCanvasAccessibilitySemanticsIncludeMotionAndRivalGap() {
        let frame = ReplayFrame(
            t: 65.4,
            d: 1_234.5,
            pace: 120,
            cadence: 28,
            watts: 220,
            progress: 0.5
        )
        XCTAssertEqual(
            Replay2DSceneView.canvasAccessibilityLabel(for: .rower),
            "\(Sport.rower.displayName) workout replay"
        )
        XCTAssertEqual(
            Replay2DSceneView.canvasAccessibilityValue(
                sport: .rower,
                frame: frame,
                distanceUnit: .metric,
                reduceMotion: false,
                ghostDistance: nil
            ),
            "Time \(RowPlayFormatting.time(frame.t, tenths: true)), "
                + "Distance \(RowPlayFormatting.distance(frame.d, unit: .metric)), "
                + "Animated \(Sport.rower.displayName) athlete"
        )
        let ghostDistance = 1_250.0
        let gap = ReplayRaceGap.raceGapMeters(
            playerDistance: frame.d,
            ghostDistance: ghostDistance
        )
        XCTAssertEqual(
            Replay2DSceneView.canvasAccessibilityValue(
                sport: .rower,
                frame: frame,
                distanceUnit: .metric,
                reduceMotion: true,
                ghostDistance: ghostDistance
            ),
            "Time \(RowPlayFormatting.time(frame.t, tenths: true)), "
                + "Distance \(RowPlayFormatting.distance(frame.d, unit: .metric)), "
                + "Reduced motion, \(ReplayRivalGapFormatting.metersLabel(gap, unit: .metric))"
        )
    }

    func testReplay2DHexParserRejectsMalformedPaletteValues() {
        XCTAssertNil(Color(replay2DHex: "#12345"))
        XCTAssertNil(Color(replay2DHex: "#12zz89"))
        XCTAssertNotNil(Color(replay2DHex: "#abcdef"))
        _ = Replay2DCanvasColors.light
        _ = Replay2DCanvasColors.dark
        for sport in Sport.allCases {
            _ = Replay2DVenueCatalog.palette(for: sport, darkTheme: false)
            _ = Replay2DVenueCatalog.palette(for: sport, darkTheme: true)
        }
    }

    func testVenueLandmarksAndPalettesRemainSportDistinct() {
        XCTAssertNotEqual(
            Replay2DVenueLandmark.size(for: .rower),
            Replay2DVenueLandmark.size(for: .skierg)
        )
        XCTAssertNotEqual(
            Replay2DVenueLandmark.size(for: .rower),
            Replay2DVenueLandmark.size(for: .bike)
        )
        XCTAssertNotEqual(
            Replay2DVenueLandmark.size(for: .skierg),
            Replay2DVenueLandmark.size(for: .bike)
        )

        for darkTheme in [false, true] {
            let rower = Replay2DVenueCatalog.palette(for: .rower, darkTheme: darkTheme)
            let skierg = Replay2DVenueCatalog.palette(for: .skierg, darkTheme: darkTheme)
            let bike = Replay2DVenueCatalog.palette(for: .bike, darkTheme: darkTheme)
            XCTAssertNotEqual(rower.skyTop, skierg.skyTop)
            XCTAssertNotEqual(rower.skyTop, bike.skyTop)
            XCTAssertNotEqual(skierg.skyTop, bike.skyTop)
            XCTAssertNotEqual(rower.groundTop, skierg.groundTop)
            XCTAssertNotEqual(rower.groundTop, bike.groundTop)
            XCTAssertNotEqual(skierg.groundTop, bike.groundTop)
        }
    }

    func testMissingCachedAggregatesSelectDeterministicFallback() throws {
        let context = ReplayStrokePoseContext(
            sport: .rower,
            peakWatts: 300,
            medianWatts: 220,
            medianDPS: 11,
            maxHR: 180
        )
        let aggregates = ReplayStrokePoseAggregates(
            context: context,
            medianHeartRate: 150
        )

        XCTAssertEqual(
            Replay2DStrokeArticulation.select(
                cachedAggregates: nil,
                hasUsableStrokeData: true
            ),
            .fallback
        )
        XCTAssertEqual(
            Replay2DStrokeArticulation.select(
                cachedAggregates: aggregates,
                hasUsableStrokeData: false
            ),
            .fallback
        )
        XCTAssertEqual(
            Replay2DStrokeArticulation.select(
                cachedAggregates: aggregates,
                hasUsableStrokeData: true
            ),
            .genuine(aggregates)
        )
    }

    func testBikeRotationPointPreservesRadiusAndOpposition() {
        let center = CGPoint(x: 12, y: 18)
        let near = Replay2DBikeRenderer.rotationPoint(
            centerX: center.x,
            centerY: center.y,
            radius: 3.1,
            angle: 0.73
        )
        let far = Replay2DBikeRenderer.rotationPoint(
            centerX: center.x,
            centerY: center.y,
            radius: 3.1,
            angle: 0.73 + .pi
        )
        XCTAssertEqual(hypot(near.x - center.x, near.y - center.y), 3.1, accuracy: 1e-10)
        XCTAssertEqual(near.x + far.x, center.x * 2, accuracy: 1e-10)
        XCTAssertEqual(near.y + far.y, center.y * 2, accuracy: 1e-10)
    }

    private var liveX: Double {
        max(
            Replay2DStyle.padLeading,
            min(renderWidth * 0.62, renderWidth - Replay2DStyle.padTrailing)
        )
    }

    private func replayFixture(sport: Sport) throws -> (WorkoutDetail, ReplayState) {
        let detail = try XCTUnwrap(
            DemoWorkoutLibrary.details.first { $0.workout.sport == sport }
        )
        let state = ReplayState(strokes: detail.strokes)
        state.seek(to: state.duration * 0.47)
        return (detail, state)
    }

    private func renderScene(
        detail: WorkoutDetail,
        state: ReplayState,
        rival: ReplayRival?,
        reduceMotion: Bool
    ) throws -> NSBitmapImageRep {
        try renderBitmap(
            Replay2DSceneView(
                detail: detail,
                state: .constant(state),
                rival: rival,
                distanceUnit: .metric,
                reduceMotion: reduceMotion,
                contentRevision: 0
            )
            .frame(width: renderWidth, height: renderHeight)
            .environment(\.colorScheme, .dark)
        )
    }

    private func renderVenue(
        sport: Sport,
        meters: Double,
        reduceMotion: Bool
    ) throws -> NSBitmapImageRep {
        try renderBitmap(
            Canvas { context, size in
                Replay2DEnvironmentRenderer.drawBackground(
                    context,
                    width: Double(size.width),
                    height: Double(size.height),
                    sport: sport,
                    meters: meters,
                    darkTheme: true,
                    reduceMotion: reduceMotion
                )
            }
            .frame(width: renderWidth, height: renderHeight)
        )
    }

    private func renderBitmap<Content: View>(_ content: Content) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: renderWidth, height: renderHeight)
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff))
    }

    private func participantROI(sport: Sport, centerX: Double) -> CGRect {
        let courseY = renderHeight * 0.79
        let top = courseY
            - Replay2DStyle.athleteTopClearance(for: sport) * Replay2DStyle.athleteScale
        return CGRect(
            x: centerX - 110,
            y: top + 20,
            width: 220,
            height: courseY + 12 - (top + 20)
        )
    }

    private func differenceMask(
        _ first: NSBitmapImageRep,
        _ second: NSBitmapImageRep,
        canvasROI: CGRect
    ) -> Set<Int> {
        precondition(first.pixelsWide == second.pixelsWide)
        precondition(first.pixelsHigh == second.pixelsHigh)
        let minX = max(0, Int(canvasROI.minX.rounded(.down)))
        let maxX = min(first.pixelsWide, Int(canvasROI.maxX.rounded(.up)))
        let minY = max(0, Int(canvasROI.minY.rounded(.down)))
        let maxY = min(first.pixelsHigh, Int(canvasROI.maxY.rounded(.up)))
        var mask = Set<Int>()
        for canvasY in minY..<maxY {
            // NSBitmapImageRep produced by ImageRenderer uses the same
            // top-leading raster origin as this Canvas snapshot.
            let pixelY = canvasY
            for x in minX..<maxX {
                guard let a = first.colorAt(x: x, y: pixelY)?.usingColorSpace(.deviceRGB),
                      let b = second.colorAt(x: x, y: pixelY)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let delta = abs(a.redComponent - b.redComponent)
                    + abs(a.greenComponent - b.greenComponent)
                    + abs(a.blueComponent - b.blueComponent)
                    + abs(a.alphaComponent - b.alphaComponent)
                if delta * 255 > minimumVisibleColorDelta {
                    mask.insert(pixelY * first.pixelsWide + x)
                }
            }
        }
        return mask
    }
}
