import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Regatta lake and rowing venue.
extension Replay2DEnvironmentRenderer {
    // MARK: Rowing Venue

    static func drawRowVenue(
        _ context: GraphicsContext,
        width w: Double, height h: Double, meters: Double,
        palette: Replay2DVenuePalette, darkTheme: Bool, reduceMotion: Bool
    ) {
        let horizon = h * 0.405
        let farShift = materialOffset(meters: meters, factor: 0.018, period: 18, reduceMotion: reduceMotion)
        let midShift = materialOffset(meters: meters, factor: 0.03, period: 26, reduceMotion: reduceMotion)

        // Far valley as stacked translucent mass so ridges do not read as
        // paper cutouts; ridge tops dissolve into haze.
        func drawRidge(top: Double, colour: Color, alpha: Double, points: [(Double, Double)]) {
            var ridge = Path()
            ridge.move(to: CGPoint(x: 0, y: horizon + 10))
            ridge.addLine(to: CGPoint(x: 0, y: horizon - points[0].1))
            for (xf, yf) in points {
                ridge.addLine(to: CGPoint(x: w * xf, y: horizon - yf))
            }
            ridge.addLine(to: CGPoint(x: w, y: horizon + 10))
            ridge.closeSubpath()
            context.fill(ridge, with: .color(colour.opacity(alpha)))
            context.fill(
                ridge,
                with: linearShading(
                    [
                        (0, palette.haze.opacity(darkTheme ? 0.28 : 0.42)),
                        (1, palette.haze.opacity(0)),
                    ],
                    from: CGPoint(x: 0, y: horizon - top),
                    to: CGPoint(x: 0, y: horizon - top * 0.35)
                )
            )
        }
        drawRidge(
            top: 92, colour: palette.ridgeFar, alpha: darkTheme ? 0.55 : 0.72,
            points: [
                (0.08, 62), (0.18, 88), (0.3, 48), (0.44, 96),
                (0.58, 70), (0.72, 84), (0.88, 58), (1, 52),
            ]
        )
        drawRidge(
            top: 70, colour: palette.ridgeFar, alpha: darkTheme ? 0.4 : 0.5,
            points: [(0.12, 42), (0.28, 68), (0.46, 52), (0.64, 74), (0.82, 46), (1, 38)]
        )

        // Mid forest mass — cooler body, still softened by haze at the crown.
        var forest = Path()
        forest.move(to: CGPoint(x: 0, y: horizon + 10))
        forest.addLine(to: CGPoint(x: 0, y: horizon - 20))
        forest.addQuadCurve(
            to: CGPoint(x: w * 0.22, y: horizon - 56),
            control: CGPoint(x: w * 0.12, y: horizon - 50)
        )
        forest.addQuadCurve(
            to: CGPoint(x: w * 0.46, y: horizon - 52),
            control: CGPoint(x: w * 0.34, y: horizon - 36)
        )
        forest.addQuadCurve(
            to: CGPoint(x: w * 0.7, y: horizon - 42),
            control: CGPoint(x: w * 0.58, y: horizon - 64)
        )
        forest.addQuadCurve(
            to: CGPoint(x: w * 0.94, y: horizon - 34),
            control: CGPoint(x: w * 0.84, y: horizon - 58)
        )
        forest.addLine(to: CGPoint(x: w, y: horizon - 28))
        forest.addLine(to: CGPoint(x: w, y: horizon + 10))
        forest.closeSubpath()
        context.fill(forest, with: .color(palette.ridgeNear.opacity(darkTheme ? 0.82 : 0.9)))
        context.fill(
            forest,
            with: linearShading(
                [
                    (0, palette.haze.opacity(darkTheme ? 0.18 : 0.28)),
                    (1, palette.haze.opacity(0)),
                ],
                from: CGPoint(x: 0, y: horizon - 60), to: CGPoint(x: 0, y: horizon - 8)
            )
        )

        // Clumped pine stands — irregular gaps prevent a picket-fence tree line.
        let pineColor = palette.foliageFar.opacity(0.88)
        var pineX = -24.0 + midShift
        while pineX <= w + 28 {
            let i = abs(Int(((pineX - midShift) / 11).rounded(.down)))
            let gap = i % 7 == 3 || i % 11 == 0
            if gap {
                pineX += 18 + Double(i % 3) * 6
                continue
            }
            let stand = 2 + (i % 4)
            for t in 0..<stand {
                let px = pineX + Double(t) * (5 + Double(i % 3))
                let base = horizon - 4 - Double(t % 3) * 2 - Double(i % 2)
                let tip = base - (14 + Double((i + t) % 5) * 3.5)
                let half = 3.6 + Double((i + t) % 3) * 1.1
                var pine = Path()
                pine.move(to: CGPoint(x: px, y: tip))
                pine.addLine(to: CGPoint(x: px + half, y: base + 2))
                pine.addLine(to: CGPoint(x: px - half, y: base + 2))
                pine.closeSubpath()
                context.fill(pine, with: .color(pineColor))
            }
            pineX += 16 + Double(stand) * 3 + Double(i % 5) * 2
        }

        // Near shoreline bank with real vertical rise into the water.
        var bank = Path()
        bank.move(to: CGPoint(x: 0, y: horizon - 8))
        var bankX = -28.0 + farShift
        while bankX <= w + 36 {
            let rise = 8 + Double(abs(Int((bankX / 28).rounded(.down))) % 4) * 3.2
            bank.addQuadCurve(
                to: CGPoint(x: bankX + 16, y: horizon - rise),
                control: CGPoint(x: bankX + 8, y: horizon - rise - 6)
            )
            bank.addQuadCurve(
                to: CGPoint(x: bankX + 28, y: horizon - 4),
                control: CGPoint(x: bankX + 22, y: horizon - 2)
            )
            bankX += 28
        }
        bank.addLine(to: CGPoint(x: w, y: horizon + 14))
        bank.addLine(to: CGPoint(x: 0, y: horizon + 14))
        bank.closeSubpath()
        context.fill(
            bank,
            with: linearShading(
                [
                    (0, palette.foliageNear),
                    (0.45, palette.structureShade),
                    (0.78, palette.groundTop.opacity(0.55)),
                    (1, palette.groundTop.opacity(0.82)),
                ],
                from: CGPoint(x: 0, y: horizon - 18), to: CGPoint(x: 0, y: horizon + 14)
            )
        )

        // Reed beds occupy a handful of natural shore pockets.
        let reedStyle = StrokeStyle(lineWidth: 1, lineCap: .round)
        let reedColor = palette.foliageNear.opacity(0.85)
        let reedClusters: [(Int, Double, Int, Double)] = [
            (0, 0.025, 5, 5), (1, 0.36, 4, 6), (2, 0.62, 7, 4.5), (3, 0.77, 3, 7), (4, 0.97, 5, 5),
        ]
        for (cluster, center, count, spacing) in reedClusters {
            for reed in 0..<count {
                let x = w * center + (Double(reed) - Double(count - 1) / 2) * spacing
                let height = 7 + Double((cluster * 3 + reed * 2) % 5) * 2.1
                var blade = Path()
                blade.move(to: CGPoint(x: x, y: horizon + 6))
                blade.addQuadCurve(
                    to: CGPoint(x: x + 0.9, y: horizon + 6 - height),
                    control: CGPoint(x: x - 1.2, y: horizon + 1)
                )
                context.stroke(blade, with: .color(reedColor), style: reedStyle)
            }
        }

        // Regatta pavilion, dock and timing tower establish a credible venue.
        // Unique architecture stays fixed; only repeating material bands use
        // modulo parallax.
        let pavilionX = max(24, w * 0.105)
        let pavilionY = horizon - 34
        var pavilionRoof = Path()
        pavilionRoof.move(to: CGPoint(x: pavilionX - 8, y: pavilionY + 8))
        pavilionRoof.addLine(to: CGPoint(x: pavilionX + 98, y: pavilionY + 8))
        pavilionRoof.addLine(to: CGPoint(x: pavilionX + 86, y: pavilionY - 8))
        pavilionRoof.addLine(to: CGPoint(x: pavilionX + 6, y: pavilionY - 8))
        pavilionRoof.closeSubpath()
        context.fill(pavilionRoof, with: .color(palette.structureShade))
        context.fill(
            Replay2DFigure.roundedRectPath(pavilionX, pavilionY + 8, 90, 24, 1.8),
            with: .color(palette.structure)
        )
        for i in 0..<7 {
            context.fill(
                Replay2DFigure.roundedRectPath(pavilionX + 6 + Double(i) * 12, pavilionY + 12, 8, 10, 1),
                with: .color(palette.structureLight.opacity(0.78))
            )
        }
        fillRect(context, pavilionX - 14, horizon + 1, 128, 4, with: .color(palette.structureShade))
        fillRect(context, pavilionX + 10, pavilionY + 22, 3.5, 14, with: .color(palette.structureShade))
        fillRect(context, pavilionX + 76, pavilionY + 22, 3.5, 14, with: .color(palette.structureShade))

        // Boathouse mass beside the pavilion for campus depth.
        context.fill(
            Replay2DFigure.roundedRectPath(pavilionX + 102, pavilionY + 14, 36, 18, 1.4),
            with: .color(palette.structure)
        )
        var boathouseRoof = Path()
        boathouseRoof.move(to: CGPoint(x: pavilionX + 98, y: pavilionY + 14))
        boathouseRoof.addLine(to: CGPoint(x: pavilionX + 120, y: pavilionY + 2))
        boathouseRoof.addLine(to: CGPoint(x: pavilionX + 142, y: pavilionY + 14))
        boathouseRoof.closeSubpath()
        context.fill(boathouseRoof, with: .color(palette.structureShade))

        let towerX = w * 0.87
        let landmark = Replay2DVenueLandmark.size(for: .rower)
        fillRect(context, towerX, horizon - 58, 3.5, 59, with: .color(palette.structureShade))
        fillRect(context, towerX + 22, horizon - 58, 3.5, 59, with: .color(palette.structureShade))
        fillRect(
            context, towerX - 4, horizon - 62, landmark.width, landmark.height,
            with: .color(palette.structure)
        )
        fillRect(context, towerX + 2, horizon - 58, 22, 8, with: .color(palette.structureLight.opacity(0.8)))
        fillRect(context, towerX + 6, horizon - 64, 14, 3, with: .color(palette.marker))

        // Water is the racing channel; the mid-course silhouette is a land island.
        fillRect(
            context, 0, horizon, w, h - horizon,
            with: linearShading(
                [
                    (0, palette.groundTop),
                    (0.18, palette.groundTop.opacity(0.78)),
                    (0.4, palette.groundMid),
                    (0.7, palette.groundBottom.opacity(0.85)),
                    (1, palette.groundBottom),
                ],
                from: CGPoint(x: 0, y: horizon), to: CGPoint(x: 0, y: h)
            )
        )
        let islandCx = w * 0.52
        let islandCy = horizon + h * 0.16
        context.fill(
            Replay2DFigure.ellipsePath(islandCx, islandCy, w * 0.11, h * 0.045),
            with: .color(palette.foliageNear)
        )
        context.fill(
            Replay2DFigure.ellipsePath(islandCx, islandCy + 2, w * 0.12, h * 0.018),
            with: .color(palette.structureShade)
        )
        let islandTrees: [(Double, Double)] = [(-18, 14), (-4, 18), (10, 15), (22, 12)]
        for (dx, tip) in islandTrees {
            var tree = Path()
            tree.move(to: CGPoint(x: islandCx + dx, y: islandCy - tip))
            tree.addLine(to: CGPoint(x: islandCx + dx + 7, y: islandCy + 2))
            tree.addLine(to: CGPoint(x: islandCx + dx - 7, y: islandCy + 2))
            tree.closeSubpath()
            context.fill(tree, with: .color(palette.foliageFar))
        }
        // Bright surface meniscus so the waterline reads across the width.
        fillRect(context, 0, horizon, w, 1.5, with: .color(palette.surfaceHighlight.opacity(0.44)))
        fillRect(context, 0, horizon + 1.5, w, 2.5, with: .color(palette.surfaceHighlight.opacity(0.16)))

        // Multi-column sun reflection with staggered taper.
        let reflectionColumns: [(Double, Double, Double)] = [
            (0.77, 1, 0.3), (0.79, 0.58, 0.12), (0.745, 0.42, 0.08),
            (0.81, 0.36, 0.06), (0.755, 0.25, 0.04),
        ]
        for (centerFrac, widthFactor, alpha) in reflectionColumns {
            let rc = w * centerFrac
            let topW = max(1.5, h * 0.012 * widthFactor)
            let bottomW = max(0.5, h * 0.024 * widthFactor)
            var column = Path()
            column.move(to: CGPoint(x: rc - topW, y: horizon))
            column.addLine(to: CGPoint(x: rc + topW, y: horizon))
            column.addLine(to: CGPoint(x: rc + bottomW, y: h))
            column.addLine(to: CGPoint(x: rc - bottomW, y: h))
            column.closeSubpath()
            context.fill(
                column,
                with: linearShading(
                    [
                        (0, palette.sun.opacity(alpha)),
                        (0.4, palette.sun.opacity(alpha * 0.32)),
                        (1, palette.sun.opacity(0)),
                    ],
                    from: CGPoint(x: 0, y: horizon), to: CGPoint(x: 0, y: h)
                )
            )
        }

        // Thin horizontal shimmer lines locked to metres so the water surface
        // responds to both playback transport and passive scrub.
        for row in 0..<5 {
            let yy = horizon + 16 + Double(row) * max(17, h * 0.072)
            let rowAlpha = 0.19 - Double(row) * 0.025
            let offset = materialOffset(
                meters: meters, factor: 0.1 + Double(row) * 0.017, period: 88,
                reduceMotion: reduceMotion
            )
            var shimmer = Path()
            for (segment, fraction) in [0.08, 0.29, 0.52, 0.76, 0.93].enumerated() {
                let x = w * fraction + offset + (row % 2 == 0 ? 8 : -11)
                let length = 13 + Double((row * 7 + segment * 5) % 12)
                shimmer.move(to: CGPoint(x: x, y: yy))
                shimmer.addQuadCurve(
                    to: CGPoint(x: x + length, y: yy),
                    control: CGPoint(x: x + length * 0.46, y: yy - Double(row % 3) * 0.7 - 0.6)
                )
            }
            context.stroke(
                shimmer,
                with: .color(palette.surfaceHighlight.opacity(rowAlpha)),
                style: StrokeStyle(lineWidth: 0.75)
            )
        }

        // Broken pavilion/tower reflection panels.
        for panel in 0..<3 {
            let yy = horizon + 7 + Double(panel) * 6.5
            let spread = 6 + Double(panel) * 2.5
            var panelPath = Path()
            panelPath.move(to: CGPoint(x: pavilionX + 35 - spread, y: yy))
            panelPath.addLine(to: CGPoint(x: pavilionX + 35 + spread, y: yy))
            panelPath.move(to: CGPoint(x: towerX + 11 - spread * 0.34, y: yy + 2))
            panelPath.addLine(to: CGPoint(x: towerX + 11 + spread * 0.34, y: yy + 2))
            context.stroke(
                panelPath,
                with: .color(palette.structureLight.opacity(0.2)),
                style: StrokeStyle(lineWidth: 0.95)
            )
        }
    }

}
