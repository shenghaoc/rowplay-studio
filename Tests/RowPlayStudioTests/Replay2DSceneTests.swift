import AppKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class Replay2DSceneTests: XCTestCase {
    func testEverySportRendersAVisibleSceneInNormalAndReducedMotion() throws {
        for sport in Sport.allCases {
            for reduceMotion in [false, true] {
                let detail = try XCTUnwrap(
                    DemoWorkoutLibrary.details.first { $0.workout.sport == sport }
                )
                let state = ReplayState(strokes: detail.strokes)
                state.seek(to: state.duration * 0.47)
                let view = Replay2DSceneView(
                    detail: detail,
                    state: .constant(state),
                    rival: nil,
                    distanceUnit: .metric,
                    reduceMotion: reduceMotion,
                    contentRevision: 0
                )
                .frame(width: 960, height: 460)
                .environment(\.colorScheme, .dark)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                renderer.proposedSize = ProposedViewSize(width: 960, height: 460)
                let image = try XCTUnwrap(renderer.nsImage)
                let png = try XCTUnwrap(pngData(from: image))
                XCTAssertGreaterThan(png.count, 25_000, "\(sport.rawValue) scene appears blank")
                XCTAssertGreaterThan(
                    sampledColorCount(in: image),
                    40,
                    "\(sport.rawValue) scene lacks venue/athlete detail"
                )

                if let directory = ProcessInfo.processInfo.environment["ROWPLAY_CAPTURE_2D_QA_DIR"] {
                    let suffix = reduceMotion ? "reduced" : "motion"
                    let url = URL(fileURLWithPath: directory, isDirectory: true)
                        .appendingPathComponent("\(sport.rawValue)-\(suffix).png")
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try png.write(to: url, options: .atomic)
                }
            }
        }
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

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func sampledColorCount(in image: NSImage) -> Int {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return 0
        }
        var colors = Set<UInt32>()
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 12) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 12) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let red = UInt32((color.redComponent * 255).rounded())
                let green = UInt32((color.greenComponent * 255).rounded())
                let blue = UInt32((color.blueComponent * 255).rounded())
                colors.insert((red << 16) | (green << 8) | blue)
            }
        }
        return colors.count
    }
}
