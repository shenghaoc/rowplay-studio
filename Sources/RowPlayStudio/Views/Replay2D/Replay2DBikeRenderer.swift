import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Ported from the web 2D canvas renderer (`src/lib/replay/renderer.ts`, pinned
// commit 4d96480e). The crank is cadence driven; wheel rotation is distance
// driven so gearing changes never make the tyres slide against the course.
enum Replay2DBikeRenderer {
    static func rotationPoint(
        centerX: Double,
        centerY: Double,
        radius: Double,
        angle: Double
    ) -> CGPoint {
        CGPoint(
            x: centerX + cos(angle) * radius,
            y: centerY + sin(angle) * radius
        )
    }

    static func draw(
        _ context: GraphicsContext,
        avatar a: Replay2DAvatarContext,
        kinematics k: ReplayBikeKinematics
    ) {
        let wheelRadius = 5.4
        let rearX = a.x - 8.5
        let frontX = a.x + 8.5
        let wheelY = a.y - wheelRadius
        let wheelSpin = a.reduce ? 0.3 : a.meters / 0.34

        drawWheel(
            context, x: rearX, y: wheelY, radius: wheelRadius,
            angle: wheelSpin, markerOffset: 0.28, avatar: a
        )
        drawWheel(
            context, x: frontX, y: wheelY, radius: wheelRadius,
            angle: wheelSpin, markerOffset: 1.12, avatar: a
        )

        let bottomBracket = CGPoint(x: a.x, y: wheelY + 1)
        let seat = CGPoint(x: a.x - 3.2, y: wheelY - 7.4)
        let bar = CGPoint(x: frontX - 1.2, y: wheelY - 6.4)
        let hipLift = a.reduce ? 0 : k.hipRock * 28
        let torsoShift = a.reduce ? 0 : k.torsoSway * 26
        let hip = CGPoint(x: seat.x + torsoShift * 0.25, y: seat.y + hipLift)
        let shoulder = CGPoint(x: a.x + 1.2 + torsoShift, y: wheelY - 12.5 + hipLift * 0.4)
        let farKit = a.accent.opacity(0.5)
        let farDrive = a.shoe.opacity(0.48)

        let nearPedal = rotationPoint(
            centerX: bottomBracket.x, centerY: bottomBracket.y,
            radius: 3.1, angle: k.crankAngle
        )
        let farPedal = rotationPoint(
            centerX: bottomBracket.x, centerY: bottomBracket.y,
            radius: 3.1, angle: k.crankAngle + .pi
        )

        Replay2DFigure.limb(
            context, bottomBracket.x, bottomBracket.y, farPedal.x, farPedal.y,
            width: 1.15, color: farDrive
        )
        drawPedal(context, at: farPedal, color: farDrive, width: 0.72)

        drawLeg(
            context,
            hip: CGPoint(x: hip.x - 0.45, y: hip.y - 0.25),
            pedal: farPedal,
            anklePitch: k.anklePitchRight,
            upperColor: farKit,
            lowerColor: a.skinShade,
            shoe: a.shoe.opacity(0.65),
            near: false
        )

        // Drivetrain and frame sit between the far and near anatomy.
        Replay2DFigure.limb(
            context, rearX + 0.65, wheelY - 0.65,
            bottomBracket.x - 1.15, bottomBracket.y - 1.85,
            width: 0.62, color: farDrive
        )
        Replay2DFigure.limb(
            context, rearX + 0.65, wheelY + 0.65,
            bottomBracket.x - 1.15, bottomBracket.y + 1.85,
            width: 0.62, color: farDrive
        )
        drawFrameTube(context, from: CGPoint(x: rearX, y: wheelY), to: bottomBracket, avatar: a)
        drawFrameTube(context, from: bottomBracket, to: seat, avatar: a)
        drawFrameTube(context, from: seat, to: bar, avatar: a)
        drawFrameTube(context, from: bottomBracket, to: bar, avatar: a)
        drawFrameTube(context, from: CGPoint(x: frontX, y: wheelY), to: bar, avatar: a)

        Replay2DFigure.limb(
            context, seat.x - 2.2, seat.y + 0.2, seat.x + 1.2, seat.y + 0.2,
            width: 1.35, color: a.rim
        )
        Replay2DFigure.disc(context, seat.x, seat.y, 0.72, color: a.rim.opacity(0.72))
        Replay2DFigure.disc(context, bar.x, bar.y, 0.62, color: a.rim.opacity(0.72))
        Replay2DFigure.limb(
            context, bar.x - 1.2, bar.y - 0.35, bar.x + 0.72, bar.y - 0.35,
            width: 1.02, color: farDrive
        )
        Replay2DFigure.limb(
            context, bar.x - 0.8, bar.y, bar.x + 1.08, bar.y,
            width: 1.18, color: a.rim
        )

        Replay2DFigure.disc(
            context, bottomBracket.x, bottomBracket.y, 2.38,
            color: a.rim.opacity(0.32)
        )
        Replay2DFigure.disc(context, bottomBracket.x, bottomBracket.y, 0.68, color: a.shoe)
        Replay2DFigure.limb(
            context, bottomBracket.x, bottomBracket.y, nearPedal.x, nearPedal.y,
            width: 1.45, color: a.rim
        )
        drawPedal(context, at: nearPedal, color: a.rim, width: 1.02)

        drawArm(
            context,
            shoulder: CGPoint(x: shoulder.x - 0.4, y: shoulder.y - 0.35),
            hand: CGPoint(x: bar.x - 0.45, y: bar.y - 0.35),
            upperColor: farKit,
            lowerColor: a.skinShade,
            bend: 1
        )
        drawLeg(
            context,
            hip: hip,
            pedal: nearPedal,
            anklePitch: k.anklePitchLeft,
            upperColor: a.accent,
            lowerColor: a.skin,
            shoe: a.shoe,
            near: true
        )
        drawPedal(context, at: nearPedal, color: a.shoe, width: 0.62)
        Replay2DFigure.disc(context, nearPedal.x, nearPedal.y, 0.48, color: a.rim)

        Replay2DFigure.disc(context, hip.x, hip.y, 2, color: a.rim.opacity(0.82))
        Replay2DFigure.shapedTorso(
            context,
            hipX: hip.x, hipY: hip.y - 0.35,
            shoulderX: shoulder.x, shoulderY: shoulder.y,
            hipHalfWidth: 2.05, shoulderHalfWidth: 2.8,
            color: a.accent, seam: a.foam.opacity(0.72)
        )
        drawArm(
            context,
            shoulder: CGPoint(x: shoulder.x, y: shoulder.y + 0.2),
            hand: bar,
            upperColor: a.accent,
            lowerColor: a.skin,
            bend: 1
        )
        Replay2DFigure.profileHead(
            context,
            shoulderX: shoulder.x, shoulderY: shoulder.y,
            skin: a.skin, hair: a.hair, helmet: a.accent
        )
    }

    private static func drawFrameTube(
        _ context: GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        avatar: Replay2DAvatarContext
    ) {
        Replay2DFigure.limb(
            context, from.x, from.y, to.x, to.y,
            width: 2.5, color: avatar.shoe.opacity(0.34)
        )
        Replay2DFigure.limb(
            context, from.x, from.y, to.x, to.y,
            width: 1.7, color: avatar.accent
        )
    }

    private static func drawPedal(
        _ context: GraphicsContext,
        at point: CGPoint,
        color: Color,
        width: Double
    ) {
        Replay2DFigure.limb(
            context, point.x - 1.25, point.y + 0.12,
            point.x + 1.25, point.y - 0.12,
            width: width, color: color
        )
        Replay2DFigure.disc(
            context, point.x, point.y, max(0.36, width * 0.42), color: color
        )
    }

    private static func drawWheel(
        _ context: GraphicsContext,
        x: Double,
        y: Double,
        radius: Double,
        angle: Double,
        markerOffset: Double,
        avatar: Replay2DAvatarContext
    ) {
        let tyre = Replay2DFigure.ellipsePath(x, y, radius, radius)
        context.stroke(tyre, with: .color(avatar.shoe.opacity(0.72)), lineWidth: 2.15)
        context.stroke(
            Replay2DFigure.ellipsePath(x, y, radius - 0.55, radius - 0.55),
            with: .color(avatar.accent), lineWidth: 1.1
        )
        for spoke in 0..<Replay2DStyle.bikeWheelSpokeCount {
            let point = rotationPoint(
                centerX: x, centerY: y, radius: radius,
                angle: angle + Double(spoke) * .pi * 2 / Double(Replay2DStyle.bikeWheelSpokeCount)
            )
            Replay2DFigure.limb(
                context, x, y, point.x, point.y,
                width: 0.62, color: avatar.rim.opacity(0.74)
            )
        }
        let marker = rotationPoint(
            centerX: x, centerY: y, radius: radius * 0.82,
            angle: angle + markerOffset
        )
        Replay2DFigure.disc(context, marker.x, marker.y, 0.58, color: avatar.accent)
        Replay2DFigure.disc(context, x, y, 1.1, color: avatar.accent)
    }

    private static func drawLeg(
        _ context: GraphicsContext,
        hip: CGPoint,
        pedal: CGPoint,
        anklePitch: Double,
        upperColor: Color,
        lowerColor: Color,
        shoe: Color,
        near: Bool
    ) {
        let solved = Replay2DFigure.solveTwoBoneJoint2D(
            hip.x, hip.y, pedal.x, pedal.y,
            firstLength: 7.35, secondLength: 7.05, bendDirection: -1
        )
        Replay2DFigure.taperedLimb(
            context, hip.x, hip.y, solved.jointX, solved.jointY,
            proximalWidth: near ? 3.2 : 3, distalWidth: near ? 2.25 : 2.1,
            color: upperColor
        )
        Replay2DFigure.taperedLimb(
            context, solved.jointX, solved.jointY, solved.endX, solved.endY,
            proximalWidth: near ? 2.3 : 2.15, distalWidth: near ? 1.55 : 1.45,
            color: lowerColor
        )
        Replay2DFigure.disc(
            context, solved.jointX, solved.jointY, near ? 1.12 : 1.02,
            color: lowerColor
        )
        Replay2DFigure.drawShoe(
            context,
            ankleX: solved.endX, ankleY: solved.endY,
            toeX: solved.endX + cos(anklePitch) * (near ? 1.9 : 1.8),
            toeY: solved.endY + sin(anklePitch) * (near ? 1.9 : 1.8),
            color: shoe
        )
    }

    private static func drawArm(
        _ context: GraphicsContext,
        shoulder: CGPoint,
        hand: CGPoint,
        upperColor: Color,
        lowerColor: Color,
        bend: Double
    ) {
        let solved = Replay2DFigure.solveTwoBoneJoint2D(
            shoulder.x, shoulder.y, hand.x, hand.y,
            firstLength: 4.92, secondLength: 4.62, bendDirection: bend
        )
        Replay2DLimbPainter.draw(
            context,
            root: shoulder,
            solution: solved,
            upperColor: upperColor,
            lowerColor: lowerColor,
            style: Replay2DLimbPaintStyle(
                upperProximalWidth: 2.3,
                upperDistalWidth: 1.7,
                lowerProximalWidth: 1.75,
                lowerDistalWidth: 1.25,
                jointRadius: 0.95,
                endRadius: 1.02,
                shoulderRadius: 1.28
            )
        )
    }
}
