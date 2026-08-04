import CoreGraphics
import RowPlayCore
import SwiftUI

/// Width/radius tokens for one two-segment anatomical limb.
struct Replay2DLimbPaintStyle {
    let upperProximalWidth: Double
    let upperDistalWidth: Double
    let lowerProximalWidth: Double
    let lowerDistalWidth: Double
    let jointRadius: Double
    let endRadius: Double
    let shoulderRadius: Double?
}

/// Shared arm/leg painter. Sport renderers own pose and palette decisions;
/// this type owns the common shoulder → joint → contact drawing order.
enum Replay2DLimbPainter {
    static func draw(
        _ context: GraphicsContext,
        root: CGPoint,
        solution: ReplayPlanarLimbSolution,
        upperColor: Color,
        lowerColor: Color,
        style: Replay2DLimbPaintStyle
    ) {
        if let shoulderRadius = style.shoulderRadius {
            Replay2DFigure.drawShoulderCap(
                context,
                root.x,
                root.y,
                color: upperColor,
                radius: shoulderRadius
            )
        }
        Replay2DFigure.taperedLimb(
            context,
            root.x,
            root.y,
            solution.jointX,
            solution.jointY,
            proximalWidth: style.upperProximalWidth,
            distalWidth: style.upperDistalWidth,
            color: upperColor
        )
        Replay2DFigure.taperedLimb(
            context,
            solution.jointX,
            solution.jointY,
            solution.endX,
            solution.endY,
            proximalWidth: style.lowerProximalWidth,
            distalWidth: style.lowerDistalWidth,
            color: lowerColor
        )
        if style.jointRadius > 0 {
            Replay2DFigure.disc(
                context,
                solution.jointX,
                solution.jointY,
                style.jointRadius,
                color: lowerColor
            )
        }
        if style.endRadius > 0 {
            Replay2DFigure.disc(
                context,
                solution.endX,
                solution.endY,
                style.endRadius,
                color: lowerColor
            )
        }
    }
}
