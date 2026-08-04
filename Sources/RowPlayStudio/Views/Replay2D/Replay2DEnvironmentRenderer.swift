import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Ported from the web 2D canvas renderer (`src/lib/replay/renderer.ts`, pinned
// commit 4d96480e). Venue environments: sky dome, regatta lake, Nordic stadium,
// and the indoor timber velodrome, with metre-driven material parallax.

/// Thin sport dispatcher. Venue geometry lives in named extensions so
/// palette, sky, and sport-specific redraw work can evolve independently.
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
}
