import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Ported from the web 2D canvas renderer (`src/lib/replay/renderer.ts`, pinned
// commit 4d96480e). The double-poling skier: parallel skis on a depth offset,
// world-locked planted baskets, rigid constant-length poles, and a hand arc
// constrained by the closed arm/pole chain.

enum Replay2DSkiRenderer {
    // MARK: Solvers

    /// Reconstruct the screen-space course point where a 2D SkiErg basket
    /// planted. The athlete advances with workout distance; subtracting the
    /// within-stroke travel keeps the loaded basket in world space instead of
    /// dragging it with the torso. Mirrors the 3D course-anchor reconstruction.
    static func skiPolePlantCourseX2D(
        currentCourseX: Double,
        pixelsPerMeter: Double,
        pose: ReplayStrokePose
    ) -> Double {
        // As the airborne basket begins its final approach it already targets
        // the *next* catch. The anchor changes exactly while poleFlight is one,
        // so the handoff has zero visible weight.
        let approachStart = ReplayMotionGraph.skiPoleApproachStartCycle
        let plantCycle = Double(pose.index) + (pose.cycleFrac >= approachStart ? 1 : 0)
        let currentCycle = Double(pose.index) + pose.cycleFrac
        let distanceSincePlant = (currentCycle - plantCycle) * max(0, pose.strokeMeters)
        let scale = pixelsPerMeter.isFinite ? max(0, pixelsPerMeter) : 0
        return currentCourseX - distanceSincePlant * scale
    }

    // MARK: Equipment

    /// Ski shaft finishing hardware: a grip collar at the hand and a real basket.
    static func drawSkiPoleHardware(
        _ context: GraphicsContext,
        handX: Double, handY: Double, tipX: Double, tipY: Double,
        shaftColor: Color, detailColor: Color
    ) {
        let dx = tipX - handX
        let dy = tipY - handY
        let length = max(1e-5, (dx * dx + dy * dy).squareRoot())
        let ux = dx / length
        let uy = dy / length
        let nx = -uy
        let ny = ux

        // The grip follows the rigid shaft; the hand is painted over its root.
        Replay2DFigure.limb(
            context, handX, handY, handX + ux * 1.8, handY + uy * 1.8,
            width: 1.6, color: detailColor
        )
        // A perpendicular basket makes the planted end legible without spray.
        Replay2DFigure.limb(
            context,
            tipX - nx * 1.05, tipY - ny * 1.05,
            tipX + nx * 1.05, tipY + ny * 1.05,
            width: 0.62, color: shaftColor
        )
        Replay2DFigure.disc(context, tipX, tipY, 0.48, color: detailColor)
        context.stroke(
            Replay2DFigure.ellipsePath(tipX, tipY, 1.18, 0.52, rotation: atan2(uy, ux)),
            with: .color(shaftColor.opacity(0.82)),
            style: StrokeStyle(lineWidth: 0.46)
        )
    }

    /// Short neutral ski with a restrained upturned tip beneath one planted boot.
    static func drawSki(
        _ context: GraphicsContext,
        footX: Double, groundY: Double, bodyColor: Color, tipColor: Color
    ) {
        Replay2DFigure.limb(
            context, footX - 3.1, groundY + 0.35, footX + 2.65, groundY + 0.35,
            width: 1.18, color: bodyColor
        )
        Replay2DFigure.limb(
            context, footX - 2.25, groundY + 0.08, footX + 1.95, groundY + 0.08,
            width: 0.34, color: tipColor.opacity(0.72)
        )
        Replay2DFigure.limb(
            context, footX + 2.65, groundY + 0.35, footX + 3.45, groundY - 0.3,
            width: 1.05, color: tipColor
        )
        context.fill(
            Replay2DFigure.roundedRectPath(footX - 0.82, groundY - 0.55, 1.65, 0.78, 0.28),
            with: .color(bodyColor.opacity(0.78))
        )
    }

    // MARK: Draw

    /// Skier double-poling: arms/poles swing from a high reach to a low back-pull.
    static func draw(
        _ context: GraphicsContext,
        avatar a: Replay2DAvatarContext,
        kinematics k: ReplaySkierKinematics
    ) {
        let x = a.x
        let y = a.y
        let polePlantCourseX = a.polePlantCourseX
        let accent = a.accent
        let rim = a.rim
        let foam = a.foam
        let skin = a.skin
        let skinShade = a.skinShade
        let shoe = a.shoe
        let upperLegLength = 5.25
        let lowerLegLength = 5.05
        // Keep the pelvis in a narrow standing-compression band: the fixed
        // boots, flexed knees and hip hinge carry the complete cycle.
        let hipX = x + k.hipHinge * 2.4
        let hipY = y - 9.2 + k.kneeFlex * 0.35
        let shX = x + 0.6 + k.hipHinge * 6
        // Preserve torso length while the grounded pelvis folds at the hip.
        let shY = hipY - 6.6 + k.hipHinge * 0.4
        let farKit = accent.opacity(0.5)
        // A double-pole cycle uses a narrow parallel stance. In this side
        // profile the lateral lane cannot be drawn literally, so encode it as a
        // small constant depth offset shared by hip, knee, boot and ski.
        let skiStanceHalfWidth = 1.05
        let farHipX = hipX - skiStanceHalfWidth
        let nearHipX = hipX + skiStanceHalfWidth
        let farFootX = x - skiStanceHalfWidth
        let nearFootX = x + skiStanceHalfWidth

        let poleLength = 13.8
        // Keep the wrist on a radius-preserving sagittal arc around the
        // shoulder: early flexion followed by near-extension at pole-off.
        let handReach = 6.6 - k.elbowLoad * 1.65 + k.armExtension * 3.3
        let handAngle = -0.56 + k.poleSweep * 2.56
        let preferredNearHandX = shX + cos(handAngle) * handReach
        let preferredNearHandY = shY + sin(handAngle) * handReach
        let farHandReach = handReach * 0.97
        let preferredFarHandX = shX - 0.45 + cos(handAngle + 0.025) * farHandReach
        let preferredFarHandY = shY - 0.4 + sin(handAngle + 0.025) * farHandReach

        // A recovering pole always trails the hand and stays above the snow.
        // It rotates from the measured shallow pole-off attitude (~23°) back
        // toward a steep plant (~80°); clearance caps the free basket so it
        // cannot drop through the course.
        let freePoleAngle = 1.745 + k.poleSweep * 0.995
        let nearClearance = 0.55 + k.poleLift * 2.8
        let nearRawDy = sin(freePoleAngle) * poleLength
        let nearDy = max(
            -poleLength * 0.985,
            min(nearRawDy, y - nearClearance - preferredNearHandY)
        )
        let nearDx = -max(0, poleLength * poleLength - nearDy * nearDy).squareRoot()
        let nearFreeTipX = preferredNearHandX + nearDx
        let nearFreeTipY = preferredNearHandY + nearDy
        let farAngle = freePoleAngle + 0.025
        let farRawDy = sin(farAngle) * poleLength
        let farDy = max(
            -poleLength * 0.985,
            min(farRawDy, y - 0.75 - k.poleLift * 2.55 - preferredFarHandY)
        )
        let farDx = -max(0, poleLength * poleLength - farDy * farDy).squareRoot()
        let farFreeTipX = preferredFarHandX + farDx
        let farFreeTipY = preferredFarHandY + farDy
        // Place the basket at the catch point, just behind the forward grip.
        let farPlantX = polePlantCourseX + 0.2
        let farPlantY = y - 0.15
        let nearPlantX = polePlantCourseX + 0.8
        let nearPlantY = y
        // Two-stage tip blend: flight toward the free arc, then re-plant.
        let farFlightTipX = farPlantX + (farFreeTipX - farPlantX) * k.poleFlight
        let farFlightTipY = farPlantY + (farFreeTipY - farPlantY) * k.poleFlight
        let nearFlightTipX = nearPlantX + (nearFreeTipX - nearPlantX) * k.poleFlight
        let nearFlightTipY = nearPlantY + (nearFreeTipY - nearPlantY) * k.poleFlight
        let farPoleTipX = farFlightTipX + (farPlantX - farFlightTipX) * k.poleContact
        let farPoleTipY = farFlightTipY + (farPlantY - farFlightTipY) * k.poleContact
        let nearPoleTipX = nearFlightTipX + (nearPlantX - nearFlightTipX) * k.poleContact
        let nearPoleTipY = nearFlightTipY + (nearPlantY - nearFlightTipY) * k.poleContact
        let armMinimumReach = abs(5.2 - 5) + 0.02
        let armMaximumReach = 5.2 + 5 - 0.02
        let farHand = ReplayPlanarRigidContactSolver.solve(
            root: SIMD2(shX - 0.45, shY - 0.4),
            preferred: SIMD2(preferredFarHandX, preferredFarHandY),
            contactCenter: SIMD2(farPoleTipX, farPoleTipY),
            contactLength: poleLength,
            minimumReach: armMinimumReach, maximumReach: armMaximumReach
        )
        let nearHand = ReplayPlanarRigidContactSolver.solve(
            root: SIMD2(shX, shY),
            preferred: SIMD2(preferredNearHandX, preferredNearHandY),
            contactCenter: SIMD2(nearPoleTipX, nearPoleTipY),
            contactLength: poleLength,
            minimumReach: armMinimumReach, maximumReach: armMaximumReach
        )

        // Far pole, arm, and leg establish depth. Both poles stay the same
        // length throughout reach, plant, press, and recovery.
        Replay2DFigure.limb(
            context, farHand.x, farHand.y, farPoleTipX, farPoleTipY,
            width: 1.05, color: rim.opacity(0.55)
        )
        drawSkiPoleHardware(
            context,
            handX: farHand.x, handY: farHand.y, tipX: farPoleTipX, tipY: farPoleTipY,
            shaftColor: rim.opacity(0.55), detailColor: shoe.opacity(0.62)
        )
        // Continuous side-profile SkiErg arm branch (bend +1): a high/forward
        // hand puts the elbow below the shoulder at plant and it migrates
        // rearward through the pull without a discrete swap.
        let farArm = Replay2DFigure.solveTwoBoneJoint2D(
            shX - 0.45, shY - 0.4, farHand.x, farHand.y,
            firstLength: 5.2, secondLength: 5, bendDirection: 1
        )
        Replay2DLimbPainter.draw(
            context,
            root: CGPoint(x: shX - 0.45, y: shY - 0.4),
            solution: farArm,
            upperColor: farKit,
            lowerColor: skinShade,
            style: Replay2DLimbPaintStyle(
                upperProximalWidth: 2.15,
                upperDistalWidth: 1.6,
                lowerProximalWidth: 1.65,
                lowerDistalWidth: 1.2,
                jointRadius: 0.88,
                endRadius: 0.96,
                shoulderRadius: 1.18
            )
        )

        // Skis paint behind both legs and boots — intentionally short and
        // neutral so equipment support reads without dominating the athlete.
        drawSki(context, footX: farFootX, groundY: y - 0.15, bodyColor: shoe.opacity(0.56), tipColor: accent.opacity(0.62))
        drawSki(context, footX: nearFootX, groundY: y, bodyColor: shoe, tipColor: accent)

        let farLeg = Replay2DFigure.solveTwoBoneJoint2D(
            farHipX, hipY - 0.3, farFootX, y - 0.15,
            firstLength: upperLegLength, secondLength: lowerLegLength, bendDirection: -1
        )
        Replay2DFigure.taperedLimb(
            context, farHipX, hipY - 0.3, farLeg.jointX, farLeg.jointY,
            proximalWidth: 2.8, distalWidth: 2.05, color: farKit
        )
        Replay2DFigure.taperedLimb(
            context, farLeg.jointX, farLeg.jointY, farLeg.endX, farLeg.endY,
            proximalWidth: 2.1, distalWidth: 1.5, color: skinShade
        )
        Replay2DFigure.disc(context, farLeg.jointX, farLeg.jointY, 1, color: skinShade)
        Replay2DFigure.drawShoe(
            context,
            ankleX: farLeg.endX, ankleY: farLeg.endY - 0.3,
            toeX: farLeg.endX + 2.1, toeY: farLeg.endY - 0.2,
            color: shoe
        )

        // Both boots remain planted while the knees and hip absorb the press.
        let nearLeg = Replay2DFigure.solveTwoBoneJoint2D(
            nearHipX, hipY, nearFootX, y,
            firstLength: upperLegLength, secondLength: lowerLegLength, bendDirection: -1
        )
        Replay2DFigure.taperedLimb(
            context, nearHipX, hipY, nearLeg.jointX, nearLeg.jointY,
            proximalWidth: 3, distalWidth: 2.2, color: accent
        )
        Replay2DFigure.taperedLimb(
            context, nearLeg.jointX, nearLeg.jointY, nearLeg.endX, nearLeg.endY,
            proximalWidth: 2.25, distalWidth: 1.55, color: skin
        )
        Replay2DFigure.disc(context, nearLeg.jointX, nearLeg.jointY, 1.08, color: skin)
        Replay2DFigure.drawShoe(
            context,
            ankleX: nearLeg.endX, ankleY: nearLeg.endY - 0.25,
            toeX: nearLeg.endX + 2.2, toeY: nearLeg.endY - 0.2,
            color: shoe
        )
        Replay2DFigure.disc(context, hipX, hipY, 1.5, color: rim.opacity(0.7))
        Replay2DFigure.shapedTorso(
            context,
            hipX: hipX, hipY: hipY - 0.3, shoulderX: shX, shoulderY: shY,
            hipHalfWidth: 2.05, shoulderHalfWidth: 2.85,
            color: accent, seam: foam.opacity(0.72)
        )
        Replay2DFigure.limb(
            context, hipX + 0.1, hipY - 1, shX + 0.25, shY + 0.15,
            width: 0.8, color: foam.opacity(0.78)
        )
        Replay2DFigure.profileHead(context, shoulderX: shX, shoulderY: shY, skin: skin, hair: a.hair)

        // Reach → plant → press → recovery. Contact intensity controls the
        // snow burst, while the rigid visual pole keeps a stable length.
        Replay2DFigure.limb(
            context, nearHand.x, nearHand.y, nearPoleTipX, nearPoleTipY,
            width: 1.3, color: rim
        )
        drawSkiPoleHardware(
            context,
            handX: nearHand.x, handY: nearHand.y, tipX: nearPoleTipX, tipY: nearPoleTipY,
            shaftColor: rim, detailColor: shoe
        )
        let nearArm = Replay2DFigure.solveTwoBoneJoint2D(
            shX, shY + 0.2, nearHand.x, nearHand.y,
            firstLength: 5.2, secondLength: 5, bendDirection: 1
        )
        Replay2DLimbPainter.draw(
            context,
            root: CGPoint(x: shX, y: shY + 0.2),
            solution: nearArm,
            upperColor: accent,
            lowerColor: skin,
            style: Replay2DLimbPaintStyle(
                upperProximalWidth: 2.35,
                upperDistalWidth: 1.75,
                lowerProximalWidth: 1.85,
                lowerDistalWidth: 1.3,
                jointRadius: 0.95,
                endRadius: 1.02,
                shoulderRadius: 1.4
            )
        )
        if !a.reduce && k.poleContact > 0.08 {
            let plant = k.poleContact
            Replay2DFigure.disc(context, nearPoleTipX, y, 1 + plant * 0.7, color: foam)
            Replay2DFigure.disc(context, nearPoleTipX + 2.4, y - 1.2, 0.8 + plant * 0.45, color: foam)
            Replay2DFigure.disc(context, nearPoleTipX - 1.8, y - 0.8, 0.65 + plant * 0.35, color: foam)
            Replay2DFigure.disc(
                context, farPoleTipX, y - 0.4, 0.7 + plant * 0.35, color: foam.opacity(0.45)
            )
            Replay2DFigure.disc(
                context, nearPoleTipX + 0.6, y - 2.1, 0.45 + plant * 0.25, color: foam.opacity(0.4)
            )
        }
    }
}
