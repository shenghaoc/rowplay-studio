import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Indoor timber velodrome and BikeErg venue.
extension Replay2DEnvironmentRenderer {
    // MARK: Bike Venue

    static func drawBikeVenue(
        _ context: GraphicsContext,
        width w: Double, height h: Double, meters: Double,
        palette: Replay2DVenuePalette, darkTheme: Bool, reduceMotion: Bool
    ) {
        let horizon = h * 0.44

        // Broad daylit roof shell — Canvas and 3D describe the same place.
        fillRect(
            context, 0, 0, w, horizon + 18,
            with: linearShading(
                [(0, palette.skyTop), (0.58, palette.skyHorizon), (1, palette.haze)],
                from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: horizon + 18)
            )
        )

        // Three broad skylights produce actual pools of daylight.
        let skylights: [(Double, Double, Double)] = [
            (0.18, 0.12, 0.66), (0.53, 0.18, 0.78), (0.84, 0.1, 0.58),
        ]
        for (center, width, alpha) in skylights {
            let x = w * center
            let stripW = w * width
            var shaft = Path()
            shaft.move(to: CGPoint(x: x - stripW * 0.5, y: 0))
            shaft.addLine(to: CGPoint(x: x + stripW * 0.5, y: 0))
            shaft.addLine(to: CGPoint(x: x + stripW * 0.2, y: horizon))
            shaft.addLine(to: CGPoint(x: x - stripW * 0.12, y: horizon))
            shaft.closeSubpath()
            context.fill(
                shaft,
                with: linearShading(
                    [(0, palette.sun.opacity(alpha)), (1, palette.sun.opacity(0))],
                    from: CGPoint(x: x, y: 0), to: CGPoint(x: x + stripW * 0.22, y: horizon)
                )
            )
        }

        // Long-span roof trusses cross the hall in a few deliberate bays.
        let trussColor = palette.structureShade.opacity(darkTheme ? 0.72 : 0.48)
        let trussStyle = StrokeStyle(lineWidth: max(2, h * 0.012))
        let trusses: [(Double, Double)] = [
            (w * 0.08, w * 0.14), (w * 0.39, -w * 0.09), (w * 0.72, w * 0.08), (w * 0.94, -w * 0.12),
        ]
        for (x, lean) in trusses {
            context.stroke(
                Replay2DFigure.linePath(x, 0, x + lean, horizon - 7),
                with: .color(trussColor), style: trussStyle
            )
        }
        var ridgeLine = Path()
        ridgeLine.move(to: CGPoint(x: 0, y: h * 0.105))
        ridgeLine.addQuadCurve(
            to: CGPoint(x: w, y: h * 0.11),
            control: CGPoint(x: w * 0.5, y: h * 0.02)
        )
        context.stroke(
            ridgeLine,
            with: .color(palette.structureShade.opacity(0.34)),
            style: StrokeStyle(lineWidth: 1.2)
        )

        // Far arena wall, then two asymmetric seating sectors. Leaving the
        // service side open gives the venue orientation.
        fillRect(context, 0, horizon - 36, w, 45, with: .color(palette.ridgeFar))
        fillRect(context, 0, horizon - 31, w, 2, with: .color(palette.structureShade.opacity(0.18)))
        fillRect(context, 0, horizon - 8, w, 2, with: .color(palette.structureShade.opacity(0.18)))

        var mainStand = Path()
        mainStand.move(to: CGPoint(x: w * 0.04, y: horizon + 4))
        mainStand.addLine(to: CGPoint(x: w * 0.08, y: horizon - 30))
        mainStand.addLine(to: CGPoint(x: w * 0.56, y: horizon - 30))
        mainStand.addLine(to: CGPoint(x: w * 0.62, y: horizon + 4))
        mainStand.closeSubpath()
        context.fill(mainStand, with: .color(palette.ridgeNear))
        var sideStand = Path()
        sideStand.move(to: CGPoint(x: w * 0.78, y: horizon + 4))
        sideStand.addLine(to: CGPoint(x: w * 0.82, y: horizon - 19))
        sideStand.addLine(to: CGPoint(x: w * 0.97, y: horizon - 19))
        sideStand.addLine(to: CGPoint(x: w, y: horizon + 4))
        sideStand.closeSubpath()
        context.fill(sideStand, with: .color(palette.ridgeNear))

        // Seating tiers follow each occupied straight.
        let tierColor = palette.surfaceShadow.opacity(0.48)
        let tierStyle = StrokeStyle(lineWidth: 1)
        let tiers: [(Double, Double, Double, Int)] = [
            (w * 0.09, w * 0.58, horizon - 23, 3),
            (w * 0.82, w * 0.98, horizon - 13, 2),
        ]
        for (x0, x1, top, rows) in tiers {
            for row in 0..<rows {
                let y = top + Double(row) * 7
                context.stroke(
                    Replay2DFigure.linePath(x0 + Double(row) * 4, y, x1 - Double(row) * 4, y + 1),
                    with: .color(tierColor), style: tierStyle
                )
            }
        }

        // One hospitality suite and one scoreboard give the straight a
        // destination; fixed placement while timber grain scrolls below.
        let suiteX = w * 0.24
        let suiteY = horizon - 42
        let suiteW = min(170, w * 0.27)
        let landmark = Replay2DVenueLandmark.size(for: .bike)
        context.fill(
            Replay2DFigure.roundedRectPath(suiteX, suiteY, suiteW, 22, 2.5),
            with: .color(palette.structure)
        )
        for window in 0..<3 {
            fillRect(
                context, suiteX + 10 + Double(window) * 23, suiteY + 7,
                landmark.width, landmark.height,
                with: .color(palette.structureLight.opacity(0.82))
            )
        }
        context.fill(
            Replay2DFigure.roundedRectPath(w * 0.69, horizon - 45, min(92, w * 0.16), 29, 2.5),
            with: .color(palette.structureShade)
        )
        fillRect(
            context, w * 0.705, horizon - 38, min(71, w * 0.125), 2.5,
            with: .color(palette.safety.opacity(0.9))
        )
        fillRect(
            context, w * 0.705, horizon - 30, min(53, w * 0.09), 2.5,
            with: .color(palette.marker.opacity(0.88))
        )

        // Concrete infield and a compact team-pit block on the service end.
        fillRect(
            context, 0, horizon, w, h - horizon,
            with: linearShading(
                [(0, palette.ridgeFar.opacity(0.96)), (1, palette.foliageFar)],
                from: CGPoint(x: 0, y: horizon), to: CGPoint(x: 0, y: h)
            )
        )
        var pit = Path()
        pit.move(to: CGPoint(x: w * 0.7, y: horizon + 10))
        pit.addLine(to: CGPoint(x: w, y: horizon + 16))
        pit.addLine(to: CGPoint(x: w, y: horizon + 38))
        pit.addLine(to: CGPoint(x: w * 0.67, y: horizon + 30))
        pit.closeSubpath()
        context.fill(pit, with: .color(palette.foliageNear))
        let pitBlocks: [(Double, Double)] = [
            (w * 0.73, w * 0.07), (w * 0.815, w * 0.09), (w * 0.92, w * 0.06),
        ]
        for (x, width) in pitBlocks {
            context.fill(
                Replay2DFigure.roundedRectPath(x, horizon + 15, width, 11, 1.5),
                with: .color(palette.structure.opacity(0.58))
            )
        }

        // Warm timber track, banked toward the far rail.
        var timber = Path()
        timber.move(to: CGPoint(x: 0, y: horizon + 18))
        timber.addQuadCurve(
            to: CGPoint(x: w, y: horizon + 17),
            control: CGPoint(x: w * 0.5, y: horizon + 8)
        )
        timber.addLine(to: CGPoint(x: w, y: h))
        timber.addLine(to: CGPoint(x: 0, y: h))
        timber.closeSubpath()
        context.fill(
            timber,
            with: linearShading(
                [(0, palette.groundTop), (0.42, palette.groundMid), (1, palette.groundBottom)],
                from: CGPoint(x: 0, y: horizon + 7), to: CGPoint(x: 0, y: h)
            )
        )

        // Skylight reflections spread over the boards as broad, soft fields.
        let pools: [(Double, Double, Double)] = [
            (w * 0.21, w * 0.2, 0.16), (w * 0.58, w * 0.27, 0.2), (w * 0.87, w * 0.15, 0.12),
        ]
        for (x, radius, alpha) in pools {
            fillRect(
                context, x - radius, horizon + 8, radius * 2, h - horizon,
                with: radialShading(
                    [
                        (0, palette.structureLight.opacity(alpha)),
                        (1, palette.structureLight.opacity(0)),
                    ],
                    center: CGPoint(x: x, y: horizon + 42), radius: radius
                )
            )
        }

        // Sparse travelling board joints give material motion without props.
        let jointShift = materialOffset(meters: meters, factor: 0.18, period: 96, reduceMotion: reduceMotion)
        for row in 0..<5 {
            let y = horizon + 32 + Double(row) * max(17, h * 0.075)
            var joints = Path()
            var x = -96.0 + jointShift + Double(row) * 19
            while x < w + 96 {
                // Math.round parity: floor(x + 0.5) matches the JS rounding of
                // negative halves toward positive infinity.
                let rounded = Int((x + 0.5).rounded(.down))
                let length = 34 + Double((row * 17 + rounded) % 29)
                joints.move(to: CGPoint(x: x, y: y))
                joints.addLine(to: CGPoint(x: x + length, y: y + (row % 2 == 0 ? 0.4 : -0.35)))
                x += 96
            }
            context.stroke(
                joints,
                with: .color(palette.surfaceShadow.opacity(0.16)),
                style: StrokeStyle(lineWidth: 0.75)
            )
        }

        // Continuous regulation lines, matching the 3D timber track.
        var railLine = Path()
        railLine.move(to: CGPoint(x: 0, y: horizon + 18))
        railLine.addQuadCurve(
            to: CGPoint(x: w, y: horizon + 17),
            control: CGPoint(x: w * 0.5, y: horizon + 8)
        )
        context.stroke(railLine, with: .color(palette.surfaceLine), style: StrokeStyle(lineWidth: 2))
        let regulation: [(Double, Color, Double)] = [
            (horizon + 39, palette.surfaceShadow, 1.2),
            (horizon + 56, palette.safety, 1.4),
            (horizon + 75, palette.marker, 1.3),
        ]
        for (y, color, width) in regulation {
            context.stroke(
                Replay2DFigure.linePath(0, y, w, y + 1.5),
                with: .color(color.opacity(0.78)),
                style: StrokeStyle(lineWidth: width)
            )
        }
    }
}
