import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Ported from the web 2D canvas renderer (`src/lib/replay/renderer.ts`, pinned
// commit 4d96480e). Venue environments: sky dome, regatta lake, Nordic stadium,
// and the indoor timber velodrome, with metre-driven material parallax.

// MARK: - Venue Palettes

/// Environment colours are deliberately independent of the two racer accents.
/// Live/ghost colours identify athletes; these colours identify real materials
/// and venue depth.
struct Replay2DVenuePalette {
    let skyTop: Color
    let skyHorizon: Color
    let haze: Color
    let sun: Color
    let ridgeFar: Color
    let ridgeNear: Color
    let foliageFar: Color
    let foliageNear: Color
    let structure: Color
    let structureShade: Color
    let structureLight: Color
    let groundTop: Color
    let groundMid: Color
    let groundBottom: Color
    let surfaceLine: Color
    let surfaceHighlight: Color
    let surfaceShadow: Color
    let marker: Color
    let safety: Color
    let safetyLight: Color

    init(_ hex: [String]) {
        precondition(hex.count == 20, "Venue palette requires 20 hex fields")
        skyTop = Color(replay2DHex: hex[0])
        skyHorizon = Color(replay2DHex: hex[1])
        haze = Color(replay2DHex: hex[2])
        sun = Color(replay2DHex: hex[3])
        ridgeFar = Color(replay2DHex: hex[4])
        ridgeNear = Color(replay2DHex: hex[5])
        foliageFar = Color(replay2DHex: hex[6])
        foliageNear = Color(replay2DHex: hex[7])
        structure = Color(replay2DHex: hex[8])
        structureShade = Color(replay2DHex: hex[9])
        structureLight = Color(replay2DHex: hex[10])
        groundTop = Color(replay2DHex: hex[11])
        groundMid = Color(replay2DHex: hex[12])
        groundBottom = Color(replay2DHex: hex[13])
        surfaceLine = Color(replay2DHex: hex[14])
        surfaceHighlight = Color(replay2DHex: hex[15])
        surfaceShadow = Color(replay2DHex: hex[16])
        marker = Color(replay2DHex: hex[17])
        safety = Color(replay2DHex: hex[18])
        safetyLight = Color(replay2DHex: hex[19])
    }
}

/// Footprint of each sport's signature fixed venue mass (web `VENUE_LANDMARK_2D`).
enum Replay2DVenueLandmark {
    static func size(for sport: Sport) -> CGSize {
        switch sport {
        case .rower: CGSize(width: 34, height: 18)
        case .skierg: CGSize(width: 70, height: 22)
        case .bike: CGSize(width: 14, height: 7)
        }
    }
}

/// Web `VENUES_LIGHT` / `VENUES_DARK` tables — hex values verbatim.
enum Replay2DVenueCatalog {
    private static let lightRower = Replay2DVenuePalette([
        "#4d86a8", "#f2d29a", "#f3e2bc", "#ffe7b0", "#9aae90", "#4a6d56",
        "#5a7a62", "#2a5244", "#ece6d9", "#8c7b67", "#ffd68a", "#4a92a3",
        "#1d6172", "#0c3a48", "#9fd6df", "#e8f6f7", "#082a37", "#ef5b42",
        "#d9e7e7", "#ffffff",
    ])
    private static let lightSkierg = Replay2DVenuePalette([
        "#357db3", "#dcecf5", "#f6fbfd", "#fff5cf", "#b8cedb", "#66899e",
        "#43675d", "#244a42", "#e7edf1", "#607887", "#fff1b2", "#f2f7fa",
        "#d5e4ee", "#b0c9d8", "#8eb5c8", "#ffffff", "#6f96ab", "#6d5ef5",
        "#1e6292", "#f5fbfd",
    ])
    private static let lightBike = Replay2DVenuePalette([
        "#edf3f4", "#cbd8da", "#f8f4e8", "#fff7d8", "#b6c2c4", "#87969b",
        "#6f817a", "#4e6d63", "#d9e1e2", "#596970", "#fff6d4", "#e0c39a",
        "#c99b68", "#91623e", "#f3eee4", "#fff8e8", "#503c2f", "#c83f38",
        "#2f7298", "#f8f5ed",
    ])
    private static let darkRower = Replay2DVenuePalette([
        "#071724", "#294f62", "#7a9499", "#f0c67b", "#3a5654", "#1d3f39",
        "#2a4d44", "#12332d", "#8c908c", "#3b4648", "#f0b65c", "#1f5a6c",
        "#0f3644", "#061c26", "#5aa3b4", "#b6dce2", "#03141c", "#ef6a4e",
        "#60777c", "#c8d9db",
    ])
    private static let darkSkierg = Replay2DVenuePalette([
        "#061522", "#28516a", "#7795a5", "#e8d5a1", "#60798a", "#334f60",
        "#28473f", "#142f2b", "#71838c", "#293c47", "#ffe099", "#cfe3ec",
        "#9fbfd0", "#6e93a6", "#6f9eb3", "#f1f7f9", "#456c80", "#8b7cf5",
        "#1f5f85", "#d7e8ee",
    ])
    private static let darkBike = Replay2DVenuePalette([
        "#1b2934", "#40515b", "#66767b", "#f2c981", "#45535a", "#2c3b43",
        "#3d514a", "#26473e", "#849198", "#25333c", "#f4d38c", "#9f7650",
        "#775337", "#3f2d23", "#d9d4ca", "#ebddc5", "#171412", "#ef5f53",
        "#5fa4c4", "#e8e3d8",
    ])

    static func palette(for sport: Sport, darkTheme: Bool) -> Replay2DVenuePalette {
        switch (sport, darkTheme) {
        case (.rower, false): lightRower
        case (.skierg, false): lightSkierg
        case (.bike, false): lightBike
        case (.rower, true): darkRower
        case (.skierg, true): darkSkierg
        case (.bike, true): darkBike
        }
    }
}

// MARK: - Environment Renderer

enum Replay2DEnvironmentRenderer {
    /// A bounded, scrub-safe parallax offset. Reduced motion keeps scenery still.
    static func materialOffset(
        meters: Double, factor: Double, period: Double, reduceMotion: Bool
    ) -> Double {
        if reduceMotion || !meters.isFinite { return 0 }
        let scaled = meters * factor
        let distance = (scaled.truncatingRemainder(dividingBy: period) + period)
            .truncatingRemainder(dividingBy: period)
        return -distance
    }

    /// Canvas applies lineDashOffset opposite to direct x translation. Keep this
    /// adapter explicit so repeating road/snow marks travel backwards beneath a
    /// forward-moving athlete.
    static func dashMaterialOffset(
        meters: Double, factor: Double, period: Double, reduceMotion: Bool
    ) -> Double {
        -materialOffset(meters: meters, factor: factor, period: period, reduceMotion: reduceMotion)
    }

    // MARK: Shading Helpers

    private static func gradient(_ stops: [(Double, Color)]) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.1, location: CGFloat($0.0)) })
    }

    private static func linearShading(
        _ stops: [(Double, Color)],
        from start: CGPoint, to end: CGPoint
    ) -> GraphicsContext.Shading {
        .linearGradient(gradient(stops), startPoint: start, endPoint: end)
    }

    private static func radialShading(
        _ stops: [(Double, Color)],
        center: CGPoint, radius: Double
    ) -> GraphicsContext.Shading {
        .radialGradient(gradient(stops), center: center, startRadius: 0, endRadius: radius)
    }

    private static func fillRect(
        _ context: GraphicsContext,
        _ x: Double, _ y: Double, _ width: Double, _ height: Double,
        with shading: GraphicsContext.Shading
    ) {
        context.fill(Path(CGRect(x: x, y: y, width: width, height: height)), with: shading)
    }

    // MARK: Background

    static func drawBackground(
        _ context: GraphicsContext,
        width w: Double, height h: Double,
        sport: Sport, meters: Double,
        darkTheme: Bool, reduceMotion: Bool
    ) {
        let palette = Replay2DVenueCatalog.palette(for: sport, darkTheme: darkTheme)
        var clipped = context
        clipped.clip(to: Replay2DFigure.roundedRectPath(0, 0, w, h, 5))

        if sport == .bike {
            // BikeErg is an indoor velodrome. Let the venue own the full
            // backdrop instead of painting an outdoor sky first.
            drawBikeVenue(
                clipped, width: w, height: h, meters: meters,
                palette: palette, darkTheme: darkTheme, reduceMotion: reduceMotion
            )
        } else {
            drawSky(clipped, width: w, height: h, palette: palette, darkTheme: darkTheme)
            if sport == .skierg {
                drawSkiVenue(
                    clipped, width: w, height: h, meters: meters,
                    palette: palette, darkTheme: darkTheme, reduceMotion: reduceMotion
                )
            } else {
                drawRowVenue(
                    clipped, width: w, height: h, meters: meters,
                    palette: palette, darkTheme: darkTheme, reduceMotion: reduceMotion
                )
            }

            // Atmospheric fog veil — pulls the horizon away from the course
            // without washing out the venue silhouettes.
            fillRect(
                clipped, 0, h * 0.31, w, h * 0.17,
                with: linearShading(
                    [
                        (0, palette.haze.opacity(0)),
                        (0.55, palette.haze.opacity(darkTheme ? 0.23 : 0.28)),
                        (1, palette.haze.opacity(0)),
                    ],
                    from: CGPoint(x: 0, y: h * 0.31), to: CGPoint(x: 0, y: h * 0.48)
                )
            )
        }

        // A restrained frame vignette supplies depth without obscuring the race.
        fillRect(
            clipped, 0, 0, w, h,
            with: linearShading(
                [
                    (0, palette.surfaceShadow.opacity(0.22)),
                    (0.08, palette.surfaceShadow.opacity(0)),
                    (0.92, palette.surfaceShadow.opacity(0)),
                    (1, palette.surfaceShadow.opacity(0.18)),
                ],
                from: CGPoint(x: 0, y: 0), to: CGPoint(x: w, y: 0)
            )
        )
    }

    // MARK: Sky

    static func drawSky(
        _ context: GraphicsContext,
        width w: Double, height h: Double,
        palette: Replay2DVenuePalette, darkTheme: Bool
    ) {
        // Richer atmospheric dome: five stops keep the zenith, mid-sky,
        // horizon, and haze layers visually distinct.
        fillRect(
            context, 0, 0, w, h,
            with: linearShading(
                [
                    (0, palette.skyTop),
                    (0.28, palette.skyTop.opacity(0.85)),
                    (0.55, palette.skyHorizon.opacity(0.92)),
                    (0.78, palette.skyHorizon),
                    (1, palette.haze),
                ],
                from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: h * 0.62)
            )
        )

        // Low-opacity high-altitude vapour wisps.
        let highCloudAlpha = darkTheme ? 0.06 : 0.12
        var wisps = Path()
        wisps.addPath(Replay2DFigure.ellipsePath(w * 0.08, h * 0.06, w * 0.2, h * 0.015, rotation: -0.02))
        wisps.addPath(Replay2DFigure.ellipsePath(w * 0.4, h * 0.08, w * 0.16, h * 0.013, rotation: 0.04))
        wisps.addPath(Replay2DFigure.ellipsePath(w * 0.7, h * 0.04, w * 0.22, h * 0.014, rotation: -0.015))
        context.fill(wisps, with: .color(palette.surfaceHighlight.opacity(highCloudAlpha)))

        // Mid-altitude cumulus banks — a darker base plus a lighter top per
        // bank creates a quick aerial illusion.
        let cloudAlpha = darkTheme ? 0.09 : 0.2
        let cloudBase = (darkTheme ? palette.haze : palette.skyHorizon).opacity(cloudAlpha)
        let cloudTop = palette.surfaceHighlight.opacity(cloudAlpha * 0.7)
        let banks: [(Double, Double, Double, Double)] = [
            (w * 0.15, h * 0.14, w * 0.18, h * 0.028),
            (w * 0.36, h * 0.16, w * 0.13, h * 0.022),
            (w * 0.62, h * 0.11, w * 0.17, h * 0.025),
            (w * 0.88, h * 0.13, w * 0.11, h * 0.019),
            (w * 0.24, h * 0.18, w * 0.095, h * 0.016),
            (w * 0.5, h * 0.2, w * 0.14, h * 0.017),
        ]
        for (cx, cy, rx, ry) in banks {
            context.fill(
                Replay2DFigure.ellipsePath(cx, cy, rx, ry, rotation: -0.03),
                with: .color(cloudBase)
            )
            context.fill(
                Replay2DFigure.ellipsePath(cx, cy - ry * 0.35, rx * 0.78, ry * 0.65, rotation: -0.03),
                with: .color(cloudTop)
            )
        }

        // Single long horizon haze strip.
        fillRect(
            context, 0, h * 0.38, w, h * 0.12,
            with: linearShading(
                [
                    (0, palette.haze.opacity(0)),
                    (0.55, palette.haze.opacity(darkTheme ? 0.22 : 0.38)),
                    (1, palette.haze.opacity(0)),
                ],
                from: CGPoint(x: 0, y: h * 0.38), to: CGPoint(x: 0, y: h * 0.5)
            )
        )

        // Multi-ring sun glow: a small bright core with three concentric halos.
        let sunX = w * 0.77
        let sunY = h * 0.17
        let haloRadius = h * 0.24
        let rings: [(Double, Double)] = [
            (haloRadius * 0.35, 0.42),
            (haloRadius * 0.62, 0.19),
            (haloRadius, 0.08),
            (haloRadius * 1.38, 0.028),
        ]
        for (radius, opacity) in rings {
            fillRect(
                context, sunX - radius, sunY - radius, radius * 2, radius * 2,
                with: radialShading(
                    [
                        (0, palette.sun.opacity(opacity)),
                        (0.48, palette.sun.opacity(opacity * 0.35)),
                        (1, palette.sun.opacity(0)),
                    ],
                    center: CGPoint(x: sunX, y: sunY), radius: radius
                )
            )
        }
        Replay2DFigure.disc(
            context, sunX, sunY, max(2.5, h * 0.016), color: palette.sun.opacity(0.92)
        )

        // Subtle light motes suggesting atmospheric dust.
        let moteAlpha = darkTheme ? 0.14 : 0.22
        let moteColor = palette.sun.opacity(moteAlpha)
        let motes: [(Double, Double, Double)] = [
            (sunX - h * 0.12, sunY - h * 0.04, 0.6),
            (sunX + h * 0.08, sunY - h * 0.06, 0.45),
            (sunX - h * 0.05, sunY + h * 0.07, 0.5),
            (sunX + h * 0.1, sunY + h * 0.02, 0.38),
            (sunX - h * 0.15, sunY + h * 0.01, 0.52),
            (sunX + h * 0.14, sunY - h * 0.02, 0.42),
        ]
        for (mx, my, mr) in motes where mx > 0 && my > 0 {
            Replay2DFigure.disc(context, mx, my, mr, color: moteColor)
        }
    }

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

    // MARK: Props

    static func drawFloodlight(
        _ context: GraphicsContext,
        x: Double, baseY: Double, height: Double,
        palette: Replay2DVenuePalette, lean: Double
    ) {
        let headX = x + lean * 3
        let headY = baseY - height
        context.stroke(
            Replay2DFigure.linePath(x, baseY, headX, headY),
            with: .color(palette.structureShade),
            style: StrokeStyle(lineWidth: 2)
        )
        context.fill(
            Replay2DFigure.roundedRectPath(headX - 10, headY - 4, 20, 7, 1.5),
            with: .color(palette.structureShade)
        )
        for lamp in 0..<4 {
            fillRect(
                context, headX - 7.5 + Double(lamp) * 4.5, headY - 2, 3, 3,
                with: .color(palette.structureLight.opacity(0.94))
            )
        }
    }

    /// A soft, asymmetric evergreen silhouette rather than a repeated triangle.
    static func drawEvergreen(
        _ context: GraphicsContext,
        x: Double, baseY: Double, height: Double, body: Color, light: Color
    ) {
        let half = height * 0.21
        var tree = Path()
        tree.move(to: CGPoint(x: x, y: baseY - height))
        tree.addQuadCurve(
            to: CGPoint(x: x - half * 0.58, y: baseY - height * 0.61),
            control: CGPoint(x: x - half * 0.36, y: baseY - height * 0.72)
        )
        tree.addQuadCurve(
            to: CGPoint(x: x - half * 0.82, y: baseY - height * 0.31),
            control: CGPoint(x: x - half * 1.08, y: baseY - height * 0.39)
        )
        tree.addQuadCurve(
            to: CGPoint(x: x - half, y: baseY),
            control: CGPoint(x: x - half * 1.3, y: baseY - height * 0.12)
        )
        tree.addLine(to: CGPoint(x: x + half, y: baseY))
        tree.addQuadCurve(
            to: CGPoint(x: x + half * 0.72, y: baseY - height * 0.31),
            control: CGPoint(x: x + half * 1.2, y: baseY - height * 0.12)
        )
        tree.addQuadCurve(
            to: CGPoint(x: x + half * 0.42, y: baseY - height * 0.6),
            control: CGPoint(x: x + half, y: baseY - height * 0.43)
        )
        tree.addQuadCurve(
            to: CGPoint(x: x, y: baseY - height),
            control: CGPoint(x: x + half * 0.22, y: baseY - height * 0.79)
        )
        tree.closeSubpath()
        context.fill(tree, with: .color(body))

        var sheen = Path()
        sheen.move(to: CGPoint(x: x - height * 0.025, y: baseY - height * 0.87))
        sheen.addQuadCurve(
            to: CGPoint(x: x - half * 0.36, y: baseY - height * 0.16),
            control: CGPoint(x: x - half * 0.52, y: baseY - height * 0.49)
        )
        sheen.addLine(to: CGPoint(x: x - half * 0.05, y: baseY - height * 0.12))
        sheen.addQuadCurve(
            to: CGPoint(x: x - height * 0.025, y: baseY - height * 0.87),
            control: CGPoint(x: x + half * 0.07, y: baseY - height * 0.52)
        )
        sheen.closeSubpath()
        context.fill(sheen, with: .color(light.opacity(0.36)))
    }
}
