import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Outdoor atmospheric dome shared by rowing and SkiErg venues.
extension Replay2DEnvironmentRenderer {
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
}
