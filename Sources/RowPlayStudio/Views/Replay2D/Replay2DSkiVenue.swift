import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Nordic stadium and SkiErg venue.
extension Replay2DEnvironmentRenderer {
    // MARK: Ski Venue

    /// The shared alpine massif silhouette used by both the far ridge fill and
    /// its haze veil (identical quads in the web source).
    private static func skiMassifPath(
        width w: Double, horizon: Double, startY: Double
    ) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: startY))
        path.addLine(to: CGPoint(x: 0, y: horizon - 22))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.12, y: horizon - 70),
            control: CGPoint(x: w * 0.06, y: horizon - 56)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.22, y: horizon - 31),
            control: CGPoint(x: w * 0.17, y: horizon - 58)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.38, y: horizon - 90),
            control: CGPoint(x: w * 0.3, y: horizon - 74)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: horizon - 36),
            control: CGPoint(x: w * 0.44, y: horizon - 68)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.68, y: horizon - 78),
            control: CGPoint(x: w * 0.59, y: horizon - 70)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.82, y: horizon - 32),
            control: CGPoint(x: w * 0.75, y: horizon - 60)
        )
        path.addQuadCurve(
            to: CGPoint(x: w, y: horizon - 64),
            control: CGPoint(x: w * 0.93, y: horizon - 54)
        )
        path.addLine(to: CGPoint(x: w, y: horizon + 10))
        return path
    }

    static func drawSkiVenue(
        _ context: GraphicsContext,
        width w: Double, height h: Double, meters: Double,
        palette: Replay2DVenuePalette, darkTheme: Bool, reduceMotion: Bool
    ) {
        let horizon = h * 0.445

        // Two soft alpine ranges create atmospheric scale.
        var farRidge = skiMassifPath(width: w, horizon: horizon, startY: horizon + 10)
        farRidge.closeSubpath()
        context.fill(farRidge, with: .color(palette.ridgeFar))

        // Pale atmospheric haze veil beneath the far ridge.
        var hazeVeil = skiMassifPath(width: w, horizon: horizon, startY: horizon - 10)
        hazeVeil.addLine(to: CGPoint(x: 0, y: horizon + 10))
        hazeVeil.closeSubpath()
        context.fill(hazeVeil, with: .color(palette.haze.opacity(darkTheme ? 0.14 : 0.2)))

        var nearRidge = Path()
        nearRidge.move(to: CGPoint(x: 0, y: horizon + 8))
        nearRidge.addLine(to: CGPoint(x: 0, y: horizon - 10))
        nearRidge.addQuadCurve(
            to: CGPoint(x: w * 0.17, y: horizon - 52),
            control: CGPoint(x: w * 0.09, y: horizon - 38)
        )
        nearRidge.addQuadCurve(
            to: CGPoint(x: w * 0.31, y: horizon - 16),
            control: CGPoint(x: w * 0.24, y: horizon - 33)
        )
        nearRidge.addQuadCurve(
            to: CGPoint(x: w * 0.49, y: horizon - 58),
            control: CGPoint(x: w * 0.39, y: horizon - 50)
        )
        nearRidge.addQuadCurve(
            to: CGPoint(x: w * 0.63, y: horizon - 14),
            control: CGPoint(x: w * 0.57, y: horizon - 34)
        )
        nearRidge.addQuadCurve(
            to: CGPoint(x: w * 0.8, y: horizon - 46),
            control: CGPoint(x: w * 0.72, y: horizon - 36)
        )
        nearRidge.addQuadCurve(
            to: CGPoint(x: w, y: horizon - 8),
            control: CGPoint(x: w * 0.91, y: horizon - 28)
        )
        nearRidge.addLine(to: CGPoint(x: w, y: horizon + 8))
        nearRidge.closeSubpath()
        context.fill(nearRidge, with: .color(palette.ridgeNear))

        // Selective snow caps — wide and soft so they read as snow mantles.
        var caps = Path()
        caps.move(to: CGPoint(x: w * 0.05, y: horizon - 54))
        caps.addQuadCurve(
            to: CGPoint(x: w * 0.125, y: horizon - 68),
            control: CGPoint(x: w * 0.09, y: horizon - 65)
        )
        caps.addQuadCurve(
            to: CGPoint(x: w * 0.18, y: horizon - 47),
            control: CGPoint(x: w * 0.155, y: horizon - 61)
        )
        caps.move(to: CGPoint(x: w * 0.31, y: horizon - 72))
        caps.addQuadCurve(
            to: CGPoint(x: w * 0.385, y: horizon - 88),
            control: CGPoint(x: w * 0.35, y: horizon - 86)
        )
        caps.addQuadCurve(
            to: CGPoint(x: w * 0.45, y: horizon - 56),
            control: CGPoint(x: w * 0.42, y: horizon - 73)
        )
        caps.move(to: CGPoint(x: w * 0.61, y: horizon - 66))
        caps.addQuadCurve(
            to: CGPoint(x: w * 0.685, y: horizon - 76),
            control: CGPoint(x: w * 0.65, y: horizon - 76)
        )
        caps.addQuadCurve(
            to: CGPoint(x: w * 0.75, y: horizon - 51),
            control: CGPoint(x: w * 0.72, y: horizon - 64)
        )
        context.stroke(
            caps,
            with: .color(palette.surfaceHighlight.opacity(0.56)),
            style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
        )

        // Snow-covered valley shoulders close the gap between the massif and
        // the groomed field.
        var shoulders = Path()
        shoulders.move(to: CGPoint(x: 0, y: horizon - 10))
        shoulders.addQuadCurve(
            to: CGPoint(x: w * 0.31, y: horizon + 4),
            control: CGPoint(x: w * 0.14, y: horizon - 28)
        )
        shoulders.addQuadCurve(
            to: CGPoint(x: w * 0.68, y: horizon + 2),
            control: CGPoint(x: w * 0.5, y: horizon + 17)
        )
        shoulders.addQuadCurve(
            to: CGPoint(x: w, y: horizon - 7),
            control: CGPoint(x: w * 0.86, y: horizon - 25)
        )
        shoulders.addLine(to: CGPoint(x: w, y: horizon + 26))
        shoulders.addLine(to: CGPoint(x: 0, y: horizon + 26))
        shoulders.closeSubpath()
        context.fill(shoulders, with: .color(palette.groundMid.opacity(0.9)))
        var shoulderLight = Path()
        shoulderLight.move(to: CGPoint(x: 0, y: horizon - 13))
        shoulderLight.addQuadCurve(
            to: CGPoint(x: w * 0.31, y: horizon + 1),
            control: CGPoint(x: w * 0.14, y: horizon - 31)
        )
        shoulderLight.addQuadCurve(
            to: CGPoint(x: w * 0.68, y: horizon - 2),
            control: CGPoint(x: w * 0.5, y: horizon + 11)
        )
        shoulderLight.addQuadCurve(
            to: CGPoint(x: w, y: horizon - 10),
            control: CGPoint(x: w * 0.86, y: horizon - 29)
        )
        shoulderLight.addLine(to: CGPoint(x: w, y: horizon - 3))
        shoulderLight.addQuadCurve(
            to: CGPoint(x: w * 0.68, y: horizon + 7),
            control: CGPoint(x: w * 0.84, y: horizon - 18)
        )
        shoulderLight.addQuadCurve(
            to: CGPoint(x: w * 0.29, y: horizon + 7),
            control: CGPoint(x: w * 0.48, y: horizon + 21)
        )
        shoulderLight.addQuadCurve(
            to: CGPoint(x: 0, y: horizon - 4),
            control: CGPoint(x: w * 0.14, y: horizon - 20)
        )
        shoulderLight.closeSubpath()
        context.fill(shoulderLight, with: .color(palette.surfaceHighlight.opacity(0.66)))

        // Frost wrap — a very cold, low-opacity wash between sky and snow.
        fillRect(
            context, 0, horizon - 12, w, 16,
            with: linearShading(
                [
                    (0, palette.surfaceHighlight.opacity(0)),
                    (0.45, palette.surfaceHighlight.opacity(0.15)),
                    (1, palette.surfaceHighlight.opacity(0)),
                ],
                from: CGPoint(x: 0, y: horizon - 12), to: CGPoint(x: 0, y: horizon + 4)
            )
        )

        fillRect(
            context, 0, horizon, w, h - horizon,
            with: linearShading(
                [
                    (0, palette.groundTop),
                    (0.28, palette.groundTop.opacity(0.72)),
                    (0.55, palette.groundMid),
                    (1, palette.groundBottom),
                ],
                from: CGPoint(x: 0, y: horizon), to: CGPoint(x: 0, y: h)
            )
        )

        // Snowbank highlights sculpt the field downhill along the course.
        var sweepA = Path()
        sweepA.move(to: CGPoint(x: w * 0.15, y: horizon))
        sweepA.addQuadCurve(
            to: CGPoint(x: w * 0.37, y: h),
            control: CGPoint(x: w * 0.28, y: horizon + h * 0.14)
        )
        sweepA.addLine(to: CGPoint(x: w * 0.22, y: h))
        sweepA.addQuadCurve(
            to: CGPoint(x: w * 0.05, y: horizon),
            control: CGPoint(x: w * 0.16, y: horizon + h * 0.1)
        )
        sweepA.closeSubpath()
        context.fill(sweepA, with: .color(palette.surfaceHighlight.opacity(0.13)))
        var sweepB = Path()
        sweepB.move(to: CGPoint(x: w * 0.58, y: horizon))
        sweepB.addQuadCurve(
            to: CGPoint(x: w * 0.82, y: h),
            control: CGPoint(x: w * 0.72, y: horizon + h * 0.12)
        )
        sweepB.addLine(to: CGPoint(x: w * 0.68, y: h))
        sweepB.addQuadCurve(
            to: CGPoint(x: w * 0.47, y: horizon),
            control: CGPoint(x: w * 0.61, y: horizon + h * 0.08)
        )
        sweepB.closeSubpath()
        context.fill(sweepB, with: .color(palette.surfaceHighlight.opacity(0.09)))

        // Authored conifer stands with deliberate gaps; scenery does not scroll.
        let clusters: [(Int, Double, Int, Double)] = [
            (0, 0.035, 3, 7), (1, 0.17, 2, 9), (2, 0.34, 5, 6),
            (3, 0.62, 3, 8), (4, 0.81, 4, 7), (5, 0.965, 2, 9),
        ]
        for (clusterIndex, center, count, spread) in clusters {
            for tree in 0..<count {
                let x = w * center + (Double(tree) - Double(count - 1) / 2) * spread
                let treeH = 17 + Double((clusterIndex * 3 + tree * 5) % 4) * 4.5
                let trunkY = horizon + 3 - Double((clusterIndex + tree) % 3)
                fillRect(
                    context, x - 1, trunkY - treeH * 0.28, 2, treeH * 0.34,
                    with: .color(palette.structureShade.opacity(0.68))
                )
                drawEvergreen(
                    context, x: x, baseY: trunkY + 1, height: treeH,
                    body: (clusterIndex + tree) % 3 == 0 ? palette.foliageFar : palette.foliageNear,
                    light: palette.surfaceHighlight
                )
            }
        }

        // Nordic stadium timing cabin and paired floodlights.
        let cabinX = w * 0.12
        let landmark = Replay2DVenueLandmark.size(for: .skierg)
        var cabinRoof = Path()
        cabinRoof.move(to: CGPoint(x: cabinX - 7, y: horizon - 20))
        cabinRoof.addLine(to: CGPoint(x: cabinX + 79, y: horizon - 20))
        cabinRoof.addLine(to: CGPoint(x: cabinX + 68, y: horizon - 29))
        cabinRoof.addLine(to: CGPoint(x: cabinX + 4, y: horizon - 29))
        cabinRoof.closeSubpath()
        context.fill(cabinRoof, with: .color(palette.structureShade))
        fillRect(
            context, cabinX, horizon - 20, landmark.width, landmark.height,
            with: .color(palette.structure)
        )
        for i in 0..<5 {
            fillRect(
                context, cabinX + 5 + Double(i) * 13, horizon - 16, 8, 8,
                with: .color(palette.structureLight.opacity(0.82))
            )
        }
        drawFloodlight(context, x: w * 0.07, baseY: horizon + 2, height: h * 0.19, palette: palette, lean: -1)
        drawFloodlight(context, x: w * 0.9, baseY: horizon + 2, height: h * 0.21, palette: palette, lean: 1)

        // Low race fencing gives the snow venue its own Nordic vocabulary.
        let fenceStyle = StrokeStyle(lineWidth: 1.2)
        let fenceColor = palette.safety.opacity(0.7)
        for side in [-1.0, 1.0] {
            let start = side < 0 ? w * 0.02 : w * 0.73
            let end = side < 0 ? w * 0.27 : w * 0.98
            context.stroke(
                Replay2DFigure.linePath(start, horizon + 20, end, horizon + 31),
                with: .color(fenceColor), style: fenceStyle
            )
            for fraction in [0.0, 0.18, 0.43, 0.71, 1.0] {
                let x = start + (end - start) * fraction
                context.stroke(
                    Replay2DFigure.linePath(x, horizon + 17, x, horizon + 31),
                    with: .color(fenceColor), style: fenceStyle
                )
            }
        }

        // Sculpted snowbanks frame the groomed competition field.
        var groomed = Path()
        groomed.move(to: CGPoint(x: 0, y: horizon + 15))
        groomed.addQuadCurve(
            to: CGPoint(x: w * 0.42, y: horizon + 17),
            control: CGPoint(x: w * 0.2, y: horizon + 4)
        )
        groomed.addQuadCurve(
            to: CGPoint(x: w, y: horizon + 11),
            control: CGPoint(x: w * 0.66, y: horizon + 28)
        )
        groomed.addLine(to: CGPoint(x: w, y: horizon + 24))
        groomed.addQuadCurve(
            to: CGPoint(x: w * 0.44, y: horizon + 27),
            control: CGPoint(x: w * 0.72, y: horizon + 37)
        )
        groomed.addQuadCurve(
            to: CGPoint(x: 0, y: horizon + 29),
            control: CGPoint(x: w * 0.2, y: horizon + 15)
        )
        groomed.closeSubpath()
        context.fill(groomed, with: .color(palette.surfaceHighlight.opacity(0.55)))

        // Corduroy grooming rows locked to travelled metres.
        var groomY = horizon + 38
        while groomY < h {
            let shift = materialOffset(meters: meters, factor: 0.24, period: 24, reduceMotion: reduceMotion)
            var rowPath = Path()
            var x = -24.0 + shift
            while x < w + 24 {
                rowPath.move(to: CGPoint(x: x, y: groomY))
                rowPath.addLine(to: CGPoint(x: x + 11, y: groomY))
                x += 24
            }
            context.stroke(
                rowPath,
                with: .color(palette.surfaceShadow.opacity(0.15)),
                style: StrokeStyle(lineWidth: 0.85)
            )
            groomY += 18
        }
    }
}
