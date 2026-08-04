import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Ported from the web 2D canvas renderer (`src/lib/replay/renderer.ts`, pinned
// commit 4d96480e). Participant styling: the shared canvas colour tables, the
// layout constants, and the figure-drawing primitives every sport avatar uses.

// MARK: - Hex Colors

extension Color {
    /// `#rrggbb` parser for the verbatim palette tables copied from renderer.ts.
    init?(replay2DHex hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    /// Palette literals are programmer-owned data and must never silently
    /// turn into the user's accent colour when mistyped.
    static func requiredReplay2DHex(
        _ hex: String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Color {
        guard let color = Color(replay2DHex: hex) else {
            preconditionFailure("Invalid replay palette hex at \(file):\(line)")
        }
        return color
    }
}

// MARK: - Canvas Colors

/// Runtime subset of the web `CanvasColors` interface. Source-only palette
/// fields stay sealed in the parity fixture until a native drawing consumer
/// exists; they are not carried as dead production state.
struct Replay2DCanvasColors {
    let tickText: Color
    let laneLine: Color
    let labelText: Color
    let live: Color
    let ghost: Color
    let foam: Color
    let skin: Color
    let skinShade: Color
    let hair: Color
    let shoe: Color

    /// Web `COLORS_LIGHT` — values verbatim.
    static let light = Replay2DCanvasColors(
        tickText: Color.requiredReplay2DHex("#4a6470"),
        laneLine: Color.requiredReplay2DHex("#bed0d7"),
        labelText: Color.requiredReplay2DHex("#0f2a36"),
        live: Color.requiredReplay2DHex("#5240ce"),
        ghost: Color.requiredReplay2DHex("#176b8c"),
        foam: Color.requiredReplay2DHex("#ffffff"),
        skin: Color.requiredReplay2DHex("#bb7053"),
        skinShade: Color.requiredReplay2DHex("#8e4f3d"),
        hair: Color.requiredReplay2DHex("#263840"),
        shoe: Color.requiredReplay2DHex("#172a33")
    )

    /// Web `COLORS_DARK` — values verbatim.
    static let dark = Replay2DCanvasColors(
        tickText: Color.requiredReplay2DHex("#8aa2ac"),
        laneLine: Color.requiredReplay2DHex("#3d505a"),
        labelText: Color.requiredReplay2DHex("#dce6ea"),
        live: Color.requiredReplay2DHex("#8c7cf0"),
        ghost: Color.requiredReplay2DHex("#3aa8cc"),
        foam: Color.requiredReplay2DHex("#bcd3dd"),
        skin: Color.requiredReplay2DHex("#e2a27f"),
        skinShade: Color.requiredReplay2DHex("#ad6c54"),
        hair: Color.requiredReplay2DHex("#78919c"),
        shoe: Color.requiredReplay2DHex("#d9e4e8")
    )

    static func palette(darkTheme: Bool) -> Replay2DCanvasColors {
        darkTheme ? .dark : .light
    }
}

// MARK: - Layout Constants

/// Layout and participant constants ported one-for-one from renderer.ts.
enum Replay2DStyle {
    static let padLeading: Double = 58
    static let padTrailing: Double = 30
    static let bobAmplitude: Double = 4.6
    /// Keep the athlete as the primary read inside the taller authored venue.
    static let athleteScale: Double = 2.32
    static let bikeWheelSpokeCount = 6
    /// Stable mid-drive pose used when decorative athlete motion is reduced.
    static let reducedPosePhase = Double.pi * 0.5
    /// Ghost label and HUD comparison-ink transparency.
    static let ghostLaneAlpha: Double = 0.76
    /// Ghost avatar transparency.
    static let ghostAvatarAlpha: Double = 0.82
    /// Neutral backing for small Canvas HUD text across every venue palette.
    static let hudBackdropOpacity: Double = 0.86
    static let hudBackdrop = Color.black.opacity(hudBackdropOpacity)
    static let hudText = Color.white
    static let hudRivalText = Color.requiredReplay2DHex("#c8f3ff")
    static let hudTrack = Color.white.opacity(0.36)
    static let hudProgress = Color.requiredReplay2DHex("#7fdef8")

    /// Forward/back hull surge per stroke (px), per sport. Bike pedals smoothly.
    static func surgePixels(for sport: Sport) -> Double {
        switch sport {
        case .rower: 6.4
        case .skierg: 8.2
        case .bike: 0
        }
    }

    /// Approximate scaled silhouette height above the contact line for HUD clearance.
    static func athleteTopClearance(for sport: Sport) -> Double {
        switch sport {
        case .rower: 50
        case .skierg: 57
        case .bike: 62
        }
    }

    /// One shared readable pose per sport when decorative motion is reduced.
    /// Mirrors the web `REDUCED_REPLAY_POSES` (rates rower 30 / ski 34 / bike 85).
    static func reducedPose(for sport: Sport) -> ReplayStrokePose {
        let rate: Double = switch sport {
        case .rower: 30
        case .skierg: 34
        case .bike: 85
        }
        return ReplayStrokePose.fallback(sport: sport, phase: reducedPosePhase, rate: rate)
    }

    static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, min(1, value))
    }
}

// MARK: - Avatar Draw Context

/// Mirrors the web `AvatarDrawCtx`.
struct Replay2DAvatarContext {
    var x: Double
    /// Course-space athlete X at this stroke's SkiErg pole plant.
    var polePlantCourseX: Double
    /// Waterline / ground.
    var y: Double
    /// Bobbing centre for floating parts.
    var bobY: Double
    /// Cumulative course distance, used for distance-locked wheel rotation.
    var meters: Double
    var accent: Color
    var rim: Color
    var foam: Color
    var skin: Color
    var skinShade: Color
    var hair: Color
    var shoe: Color
    var reduce: Bool
}

// MARK: - Figure Primitives

/// Shared figure painters and solver adapters used by all three sport avatars.
enum Replay2DFigure {
    // MARK: Paths

    static func roundedRectPath(
        _ x: Double, _ y: Double, _ width: Double, _ height: Double, _ radius: Double
    ) -> Path {
        Path(
            roundedRect: CGRect(x: x, y: y, width: width, height: height),
            cornerRadius: radius
        )
    }

    static func ellipsePath(
        _ centerX: Double, _ centerY: Double, _ radiusX: Double, _ radiusY: Double,
        rotation: Double = 0
    ) -> Path {
        let base = Path(ellipseIn: CGRect(
            x: -radiusX, y: -radiusY, width: radiusX * 2, height: radiusY * 2
        ))
        let transform = CGAffineTransform(translationX: centerX, y: centerY)
            .rotated(by: rotation)
        return base.applying(transform)
    }

    static func linePath(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        return path
    }

    // MARK: Solver Adapters

    /// Scalar adapter over the shared fixed-length two-bone solver.
    static func solveTwoBoneJoint2D(
        _ startX: Double, _ startY: Double,
        _ endX: Double, _ endY: Double,
        firstLength: Double, secondLength: Double, bendDirection: Double
    ) -> ReplayPlanarLimbSolution {
        let solved = ReplayTwoBoneSolver.solve2D(
            root: SIMD2(startX, startY),
            target: SIMD2(endX, endY),
            firstLength: firstLength,
            secondLength: secondLength,
            bendDirection: bendDirection
        )
        return ReplayPlanarLimbSolution(joint: solved.joint, end: solved.end)
    }

    // MARK: Painters

    /// Rounded limb / machine strut segment.
    static func limb(
        _ context: GraphicsContext,
        _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
        width: Double, color: Color
    ) {
        context.stroke(
            linePath(x1, y1, x2, y2),
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }

    /// Filled tapered anatomical segment, wider at its proximal end.
    static func taperedLimb(
        _ context: GraphicsContext,
        _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
        proximalWidth: Double, distalWidth: Double, color: Color
    ) {
        let dx = x2 - x1
        let dy = y2 - y1
        let length = (dx * dx + dy * dy).squareRoot()
        guard length >= 1e-5 else { return }
        let nx = -dy / length
        let ny = dx / length
        let p = proximalWidth * 0.5
        let d = distalWidth * 0.5
        let curveX = dx * 0.26
        let curveY = dy * 0.26

        var path = Path()
        path.move(to: CGPoint(x: x1 + nx * p, y: y1 + ny * p))
        // Retain paired straight distal edges so the visual segment terminates
        // on its solved contact point, while the shaft remains softly contoured.
        path.addQuadCurve(
            to: CGPoint(x: x2 + nx * d, y: y2 + ny * d),
            control: CGPoint(
                x: x1 + curveX + nx * (p * 0.92 + d * 0.08),
                y: y1 + curveY + ny * (p * 0.92 + d * 0.08)
            )
        )
        path.addLine(to: CGPoint(x: x2 - nx * d, y: y2 - ny * d))
        path.addQuadCurve(
            to: CGPoint(x: x1 - nx * p, y: y1 - ny * p),
            control: CGPoint(
                x: x1 + curveX - nx * (p * 0.92 + d * 0.08),
                y: y1 + curveY - ny * (p * 0.92 + d * 0.08)
            )
        )
        path.addQuadCurve(
            to: CGPoint(x: x1 + nx * p, y: y1 + ny * p),
            control: CGPoint(x: x1 - dx * 0.075, y: y1 - dy * 0.075)
        )
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }

    /// Filled disc (hub / anatomical joint).
    static func disc(
        _ context: GraphicsContext,
        _ x: Double, _ y: Double, _ radius: Double, color: Color
    ) {
        context.fill(
            Path(ellipseIn: CGRect(
                x: x - radius, y: y - radius, width: radius * 2, height: radius * 2
            )),
            with: .color(color)
        )
    }

    /// Shoulder-tapered jersey rather than a single stick through the torso.
    static func shapedTorso(
        _ context: GraphicsContext,
        hipX: Double, hipY: Double, shoulderX: Double, shoulderY: Double,
        hipHalfWidth: Double, shoulderHalfWidth: Double,
        color: Color, seam: Color
    ) {
        let dx = shoulderX - hipX
        let dy = shoulderY - hipY
        let length = max(1e-5, (dx * dx + dy * dy).squareRoot())
        let nx = -dy / length
        let ny = dx / length
        let midX = (hipX + shoulderX) * 0.5
        let midY = (hipY + shoulderY) * 0.5
        let waistHalfWidth = min(hipHalfWidth, shoulderHalfWidth) * 0.74

        var body = Path()
        body.move(to: CGPoint(x: hipX + nx * hipHalfWidth, y: hipY + ny * hipHalfWidth))
        body.addQuadCurve(
            to: CGPoint(
                x: shoulderX + nx * shoulderHalfWidth,
                y: shoulderY + ny * shoulderHalfWidth
            ),
            control: CGPoint(x: midX + nx * waistHalfWidth, y: midY + ny * waistHalfWidth)
        )
        body.addQuadCurve(
            to: CGPoint(
                x: shoulderX - nx * shoulderHalfWidth,
                y: shoulderY - ny * shoulderHalfWidth
            ),
            control: CGPoint(x: shoulderX + dx * 0.05, y: shoulderY + dy * 0.05)
        )
        body.addQuadCurve(
            to: CGPoint(x: hipX - nx * hipHalfWidth, y: hipY - ny * hipHalfWidth),
            control: CGPoint(x: midX - nx * waistHalfWidth, y: midY - ny * waistHalfWidth)
        )
        body.closeSubpath()
        context.fill(body, with: .color(color))

        // A tiny shoulder-to-waist panel establishes fabric direction along the
        // torso axis so it reads in every stroke pose.
        var panel = Path()
        panel.move(to: CGPoint(
            x: hipX + nx * waistHalfWidth * 0.55, y: hipY + ny * waistHalfWidth * 0.55
        ))
        panel.addQuadCurve(
            to: CGPoint(
                x: shoulderX + nx * shoulderHalfWidth * 0.57,
                y: shoulderY + ny * shoulderHalfWidth * 0.57
            ),
            control: CGPoint(
                x: midX + nx * waistHalfWidth * 0.72, y: midY + ny * waistHalfWidth * 0.72
            )
        )
        context.stroke(
            panel,
            with: .color(seam.opacity(0.7)),
            style: StrokeStyle(lineWidth: 0.52, lineCap: .round)
        )

        context.stroke(
            linePath(hipX, hipY, shoulderX, shoulderY),
            with: .color(seam),
            style: StrokeStyle(lineWidth: 0.65, lineCap: .round)
        )
    }

    /// Side-profile head with a jaw, nose, neck, and either hair or a helmet.
    static func profileHead(
        _ context: GraphicsContext,
        shoulderX: Double, shoulderY: Double,
        skin: Color, hair: Color, helmet: Color? = nil
    ) {
        let headX = shoulderX + 0.85
        let headY = shoulderY - 3.55
        taperedLimb(
            context,
            shoulderX + 0.15, shoulderY - 0.35, headX - 0.25, headY + 1.85,
            proximalWidth: 1.65, distalWidth: 1.35, color: skin
        )
        context.fill(
            ellipsePath(headX, headY, 2.35, 2.75, rotation: -0.12),
            with: .color(skin)
        )

        // One cheek shade, ear, and facing eye keep the head from resolving
        // into a featureless circle while staying a generic illustration.
        context.fill(
            ellipsePath(headX + 0.72, headY + 0.72, 1.05, 0.78, rotation: -0.08),
            with: .color(hair.opacity(0.32))
        )
        disc(context, headX - 1.72, headY + 0.28, 0.42, color: skin.opacity(0.76))
        disc(context, headX + 1.36, headY - 0.34, 0.28, color: hair)
        // Jaw and brow give the head a facing direction from the side profile.
        // (The web source inherits the eye's hair fill for both marks.)
        context.fill(
            ellipsePath(headX + 0.15, headY + 1.1, 1.55, 1.05, rotation: -0.08),
            with: .color(hair)
        )
        var nose = Path()
        nose.move(to: CGPoint(x: headX + 1.8, y: headY - 0.55))
        nose.addLine(to: CGPoint(x: headX + 3.05, y: headY + 0.08))
        nose.addLine(to: CGPoint(x: headX + 1.7, y: headY + 0.55))
        nose.closeSubpath()
        context.fill(nose, with: .color(hair))

        var cap = Path()
        cap.move(to: CGPoint(x: headX - 2.1, y: headY - 0.1))
        cap.addQuadCurve(
            to: CGPoint(x: headX + 1.45, y: headY - 2.4),
            control: CGPoint(x: headX - 1.2, y: headY - 3.25)
        )
        cap.addQuadCurve(
            to: CGPoint(x: headX + 1.95, y: headY - 1.15),
            control: CGPoint(x: headX + 2.35, y: headY - 1.85)
        )
        cap.addQuadCurve(
            to: CGPoint(x: headX - 2.1, y: headY - 0.1),
            control: CGPoint(x: headX - 0.1, y: headY - 1.85)
        )
        cap.closeSubpath()
        context.fill(cap, with: .color(helmet ?? hair))
        if let helmet {
            limb(context, headX + 0.35, headY + 1.4, headX + 1.8, headY + 1.65, width: 0.6, color: hair)
            limb(context, headX + 1.25, headY - 1.2, headX + 2.85, headY - 0.95, width: 0.75, color: helmet)
            limb(
                context, headX - 0.7, headY - 2.05, headX + 0.8, headY - 2.5,
                width: 0.45, color: skin.opacity(0.55)
            )
        }
    }

    static func drawShoe(
        _ context: GraphicsContext,
        ankleX: Double, ankleY: Double, toeX: Double, toeY: Double, color: Color
    ) {
        taperedLimb(
            context, ankleX, ankleY, toeX, toeY,
            proximalWidth: 1.55, distalWidth: 2.15, color: color
        )
        disc(context, toeX, toeY, 0.85, color: color)
    }

    /// Compact shoulder mass that keeps the upper arm attached at replay scale.
    static func drawShoulderCap(
        _ context: GraphicsContext,
        _ x: Double, _ y: Double, color: Color, radius: Double = 1.28
    ) {
        context.fill(
            ellipsePath(x, y, radius, radius * 0.82, rotation: -0.16),
            with: .color(color)
        )
    }
}
