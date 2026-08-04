import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Shared Canvas shading and venue props.
extension Replay2DEnvironmentRenderer {
    // MARK: Shading Helpers

    static func gradient(_ stops: [(Double, Color)]) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.1, location: CGFloat($0.0)) })
    }

    static func linearShading(
        _ stops: [(Double, Color)],
        from start: CGPoint, to end: CGPoint
    ) -> GraphicsContext.Shading {
        .linearGradient(gradient(stops), startPoint: start, endPoint: end)
    }

    static func radialShading(
        _ stops: [(Double, Color)],
        center: CGPoint, radius: Double
    ) -> GraphicsContext.Shading {
        .radialGradient(gradient(stops), center: center, startRadius: 0, endRadius: radius)
    }

    static func fillRect(
        _ context: GraphicsContext,
        _ x: Double, _ y: Double, _ width: Double, _ height: Double,
        with shading: GraphicsContext.Shading
    ) {
        context.fill(Path(CGRect(x: x, y: y, width: width, height: height)), with: shading)
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
