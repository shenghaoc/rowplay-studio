import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

// Ported from the web 2D canvas renderer (`src/lib/replay/renderer.ts`, pinned
// commit 4d96480e). The rowing shell and sculler: fixed foot stretcher, sliding
// seat, rotating torso, and two rigid sculls solved through their oarlocks.

/// One straight oar resolved from handle through oarlock to blade tip.
/// Mirrors the web `RigidOar2D`.
struct Replay2DRigidOar {
    var handleX: Double = 0
    var handleY: Double = 0
    var bladeRootX: Double = 0
    var bladeRootY: Double = 0
    var bladeTipX: Double = 0
    var bladeTipY: Double = 0
}

enum Replay2DRowRenderer {
    // MARK: Solvers

    /// Solve a side-profile rowing arm on the rearward elbow branch.
    ///
    /// Rowers face +x, so behind the torso is -x. Resolve both two-bone
    /// branches and retain the one with the smaller x coordinate: at the
    /// near-straight catch the branches converge; once the late arm draw
    /// creates a visible elbow it travels behind the shoulder rather than into
    /// the chest or toward the handle.
    static func solveRowerElbow2D(
        shoulderX: Double, shoulderY: Double,
        handX: Double, handY: Double,
        upperArmLength: Double, forearmLength: Double
    ) -> Replay2DLimbSolution {
        var primary = Replay2DFigure.solveTwoBoneJoint2D(
            shoulderX, shoulderY, handX, handY,
            firstLength: upperArmLength, secondLength: forearmLength, bendDirection: 1
        )
        let alternate = Replay2DFigure.solveTwoBoneJoint2D(
            shoulderX, shoulderY, handX, handY,
            firstLength: upperArmLength, secondLength: forearmLength, bendDirection: -1
        )
        if alternate.jointX < primary.jointX {
            primary.jointX = alternate.jointX
            primary.jointY = alternate.jointY
        }
        return primary
    }

    /// Resolve a continuous oar angle whose rigid inboard grip meets an arm reach.
    static func solveRowerOarAngle2D(
        shoulderX: Double, shoulderY: Double,
        lockX: Double, lockY: Double,
        inboardLength: Double, requestedReach: Double, preferredAngle: Double
    ) -> Double {
        let pinDeltaX = lockX - shoulderX
        let pinDeltaY = lockY - shoulderY
        let amplitude = (pinDeltaX * pinDeltaX + pinDeltaY * pinDeltaY).squareRoot()
        guard amplitude >= 1e-8, inboardLength >= 1e-8 else { return preferredAngle }
        let signedInboard = -inboardLength
        let baseDistanceSquared =
            pinDeltaX * pinDeltaX + pinDeltaY * pinDeltaY + signedInboard * signedInboard
        let cosine = max(
            -1,
            min(
                1,
                (requestedReach * requestedReach - baseDistanceSquared)
                    / (2 * signedInboard * amplitude)
            )
        )
        let center = atan2(pinDeltaY, pinDeltaX)
        let offset = acos(cosine)
        // The +offset branch is the continuous rearward-elbow solution for the
        // side-profile scull; picking the branch nearest the aesthetic sweep
        // let the two circle intersections swap mid-draw.
        return center + offset
    }

    /// Resolve one straight oar from handle through oarlock to blade tip.
    static func solveRigidOar2D(
        lockX: Double, lockY: Double, angle: Double,
        inboardLength: Double, outboardLength: Double, bladeLength: Double
    ) -> Replay2DRigidOar {
        let ux = cos(angle)
        let uy = sin(angle)
        var oar = Replay2DRigidOar()
        oar.handleX = lockX - ux * inboardLength
        oar.handleY = lockY - uy * inboardLength
        oar.bladeRootX = lockX + ux * outboardLength
        oar.bladeRootY = lockY + uy * outboardLength
        oar.bladeTipX = oar.bladeRootX + ux * bladeLength
        oar.bladeTipY = oar.bladeRootY + uy * bladeLength
        return oar
    }

    static func interpolateAngle(from: Double, to: Double, amount: Double) -> Double {
        from + atan2(sin(to - from), cos(to - from)) * amount
    }

    // MARK: Draw

    /// Rowing shell with fixed feet and legs → body → arms drive sequencing.
    static func draw(
        _ context: GraphicsContext,
        avatar a: Replay2DAvatarContext,
        kinematics k: ReplayRowerKinematics
    ) {
        let x = a.x
        let bobY = a.bobY
        let accent = a.accent
        let rim = a.rim
        let foam = a.foam
        let skin = a.skin
        let skinShade = a.skinShade
        let hullLength = 17.0
        let hullHeight = 2.8

        // Resolve the body and both sculling oars before painting so far-side
        // parts sit behind the shell while near-side joints remain readable.
        let seatX = x + 4.2 - k.legExtension * 11.4
        let seatY = bobY - 2
        // A fixed-length torso rotates from a forward catch to a restrained
        // finish layback.
        let torsoAngle = -1.04 - k.bodySwing * 0.58
        let torsoLength = 8.9
        let shX = seatX + cos(torsoAngle) * torsoLength
        let shY = seatY + sin(torsoAngle) * torsoLength
        let footX = x + 10.4
        let footY = bobY - 1
        // Mirror the shared graph's leg → body → arm handle weighting.
        let strokeProgress = k.legExtension * 0.42 + k.bodySwing * 0.32 + k.armDraw * 0.26
        let oarCatchAngle = Double.pi - 0.22
        let oarFinishAngle = 0.7
        let preferredOarAngle = oarCatchAngle - strokeProgress * (oarCatchAngle - oarFinishAngle)
        let oarlockX = x + 0.4
        let oarlockY = bobY - 0.2
        let upperArmLength = 4.3
        let forearmLength = 4.2
        // The shared armDraw channel is already a late, C2-eased curve;
        // consume it directly, matching the procedural/V4 3D path.
        let structuralMaximumReach = upperArmLength + forearmLength - 0.006
        let armClosure = Replay2DStyle.clamp01(k.armDraw)
        let farLockY = oarlockY - 0.65
        let farLongAngle = solveRowerOarAngle2D(
            shoulderX: shX - 0.4, shoulderY: shY - 0.4,
            lockX: oarlockX, lockY: farLockY,
            inboardLength: 7.1, requestedReach: structuralMaximumReach,
            preferredAngle: preferredOarAngle + 0.035
        )
        let farOar = solveRigidOar2D(
            lockX: oarlockX, lockY: farLockY,
            angle: interpolateAngle(from: farLongAngle, to: oarFinishAngle + 0.035, amount: armClosure),
            inboardLength: 7.1, outboardLength: 13.8, bladeLength: 4.0
        )
        let nearLockY = oarlockY + 0.4
        let nearLongAngle = solveRowerOarAngle2D(
            shoulderX: shX, shoulderY: shY + 0.2,
            lockX: oarlockX, lockY: nearLockY,
            inboardLength: 7.1, requestedReach: structuralMaximumReach,
            preferredAngle: preferredOarAngle
        )
        let nearOar = solveRigidOar2D(
            lockX: oarlockX, lockY: nearLockY,
            angle: interpolateAngle(from: nearLongAngle, to: oarFinishAngle, amount: armClosure),
            inboardLength: 7.1, outboardLength: 13.8, bladeLength: 4.0
        )
        let farKit = accent.opacity(0.52)

        // Feathering changes blade thickness only: the oar remains one
        // straight, fixed-length lever from far hand through lock to blade tip.
        Replay2DFigure.limb(
            context, farOar.handleX, farOar.handleY, farOar.bladeRootX, farOar.bladeRootY,
            width: 1.05, color: rim.opacity(0.55)
        )
        Replay2DFigure.taperedLimb(
            context, farOar.bladeRootX, farOar.bladeRootY, farOar.bladeTipX, farOar.bladeTipY,
            proximalWidth: 2.45 - k.bladeFeather * 1.15,
            distalWidth: 3.1 - k.bladeFeather * 1.45,
            color: farKit
        )
        Replay2DFigure.limb(
            context, farOar.bladeRootX, farOar.bladeRootY, farOar.bladeTipX, farOar.bladeTipY,
            width: 0.4, color: foam.opacity(0.34)
        )

        // Hull — long, pointed racing shell on the water.
        var hull = Path()
        hull.move(to: CGPoint(x: x - hullLength, y: bobY))
        hull.addQuadCurve(
            to: CGPoint(x: x + hullLength, y: bobY),
            control: CGPoint(x: x - hullLength * 0.2, y: bobY - hullHeight)
        )
        hull.addQuadCurve(
            to: CGPoint(x: x - hullLength, y: bobY),
            control: CGPoint(x: x - hullLength * 0.2, y: bobY + hullHeight)
        )
        hull.closeSubpath()
        context.fill(hull, with: .color(accent))
        context.stroke(hull, with: .color(rim), style: StrokeStyle(lineWidth: 1))

        // A recessed cockpit, gunwale highlight, and bow deck line turn the
        // shell into a lightweight racing boat rather than a flat capsule.
        context.fill(
            Replay2DFigure.ellipsePath(x - 0.55, bobY + 0.05, hullLength * 0.46, hullHeight * 0.47),
            with: .color(rim.opacity(0.26))
        )
        var gunwale = Path()
        gunwale.move(to: CGPoint(x: x - hullLength * 0.64, y: bobY - hullHeight * 0.43))
        gunwale.addQuadCurve(
            to: CGPoint(x: x + hullLength * 0.75, y: bobY - hullHeight * 0.2),
            control: CGPoint(x: x + hullLength * 0.22, y: bobY - hullHeight * 0.9)
        )
        context.stroke(
            gunwale, with: .color(foam.opacity(0.78)), style: StrokeStyle(lineWidth: 0.48)
        )
        context.fill(
            Replay2DFigure.roundedRectPath(x + hullLength * 0.38, bobY - 0.48, hullLength * 0.23, 0.84, 0.36),
            with: .color(foam.opacity(0.64))
        )

        // The seat rail and foot stretcher keep the lower body visibly
        // supported; both solved ankles terminate at this fixed plate.
        Replay2DFigure.limb(
            context, seatX - 1.4, seatY + 0.65, footX - 0.4, footY + 0.45,
            width: 0.72, color: rim.opacity(0.7)
        )
        Replay2DFigure.limb(context, footX, footY - 2.15, footX, footY + 1.15, width: 1.15, color: rim)
        Replay2DFigure.limb(
            context, footX - 0.65, footY - 1.35, footX + 0.65, footY - 1.35,
            width: 0.72, color: foam.opacity(0.78)
        )

        // Oarlock collars survive feathering and make the lever pivots explicit.
        Replay2DFigure.disc(context, oarlockX, oarlockY - 0.65, 0.86, color: rim.opacity(0.72))
        Replay2DFigure.disc(context, oarlockX, oarlockY - 0.65, 0.36, color: farKit)

        // Far leg and arm establish depth behind the near-side anatomy.
        let farLeg = Replay2DFigure.solveTwoBoneJoint2D(
            seatX - 0.45, seatY - 0.45, footX, footY - 0.5,
            firstLength: 7.85, secondLength: 7.65, bendDirection: -1
        )
        Replay2DFigure.taperedLimb(
            context, seatX - 0.45, seatY - 0.45, farLeg.jointX, farLeg.jointY,
            proximalWidth: 2.8, distalWidth: 2.1, color: farKit
        )
        Replay2DFigure.taperedLimb(
            context, farLeg.jointX, farLeg.jointY, farLeg.endX, farLeg.endY,
            proximalWidth: 2.15, distalWidth: 1.5, color: skinShade
        )
        Replay2DFigure.disc(context, farLeg.jointX, farLeg.jointY, 1.05, color: skinShade)
        Replay2DFigure.drawShoe(
            context,
            ankleX: farLeg.endX, ankleY: farLeg.endY,
            toeX: farLeg.endX + 1.65, toeY: farLeg.endY + 0.05,
            color: a.shoe
        )

        let farArm = solveRowerElbow2D(
            shoulderX: shX - 0.4, shoulderY: shY - 0.4,
            handX: farOar.handleX, handY: farOar.handleY,
            upperArmLength: upperArmLength, forearmLength: forearmLength
        )
        Replay2DFigure.drawShoulderCap(context, shX - 0.4, shY - 0.4, color: farKit, radius: 1.16)
        Replay2DFigure.taperedLimb(
            context, shX - 0.4, shY - 0.4, farArm.jointX, farArm.jointY,
            proximalWidth: 2.2, distalWidth: 1.65, color: farKit
        )
        Replay2DFigure.taperedLimb(
            context, farArm.jointX, farArm.jointY, farArm.endX, farArm.endY,
            proximalWidth: 1.75, distalWidth: 1.25, color: skinShade
        )
        Replay2DFigure.disc(context, farArm.jointX, farArm.jointY, 0.9, color: skinShade)
        Replay2DFigure.disc(context, farArm.endX, farArm.endY, 0.96, color: skinShade)

        // Constant femur/tibia lengths remove the old telescoping knee.
        let nearLeg = Replay2DFigure.solveTwoBoneJoint2D(
            seatX, seatY, footX, footY,
            firstLength: 7.85, secondLength: 7.65, bendDirection: -1
        )
        Replay2DFigure.taperedLimb(
            context, seatX, seatY, nearLeg.jointX, nearLeg.jointY,
            proximalWidth: 3, distalWidth: 2.2, color: accent
        )
        Replay2DFigure.taperedLimb(
            context, nearLeg.jointX, nearLeg.jointY, nearLeg.endX, nearLeg.endY,
            proximalWidth: 2.25, distalWidth: 1.55, color: skin
        )
        Replay2DFigure.disc(context, nearLeg.jointX, nearLeg.jointY, 1.12, color: skin)
        Replay2DFigure.drawShoe(
            context,
            ankleX: nearLeg.endX, ankleY: nearLeg.endY,
            toeX: nearLeg.endX + 1.75, toeY: nearLeg.endY + 0.05,
            color: a.shoe
        )
        Replay2DFigure.disc(context, seatX, seatY, 1.65, color: rim.opacity(0.8))

        Replay2DFigure.shapedTorso(
            context,
            hipX: seatX, hipY: seatY - 0.35, shoulderX: shX, shoulderY: shY,
            hipHalfWidth: 1.95, shoulderHalfWidth: 2.75,
            color: accent, seam: foam.opacity(0.72)
        )
        Replay2DFigure.limb(
            context, seatX + 0.25, seatY - 1.1, shX + 0.35, shY + 0.2,
            width: 0.78, color: foam.opacity(0.78)
        )
        Replay2DFigure.profileHead(context, shoulderX: shX, shoulderY: shY, skin: skin, hair: a.hair)

        // The visible oar is also rigid; the near hand terminates at its handle.
        Replay2DFigure.limb(
            context, nearOar.handleX, nearOar.handleY, nearOar.bladeRootX, nearOar.bladeRootY,
            width: 1.25, color: rim
        )
        Replay2DFigure.taperedLimb(
            context, nearOar.bladeRootX, nearOar.bladeRootY, nearOar.bladeTipX, nearOar.bladeTipY,
            proximalWidth: 2.75 - k.bladeFeather * 1.3,
            distalWidth: 3.45 - k.bladeFeather * 1.65,
            color: accent
        )
        Replay2DFigure.limb(
            context, nearOar.bladeRootX, nearOar.bladeRootY, nearOar.bladeTipX, nearOar.bladeTipY,
            width: 0.48, color: foam.opacity(0.62)
        )
        Replay2DFigure.disc(context, oarlockX, oarlockY + 0.4, 0.96, color: rim)
        Replay2DFigure.disc(context, oarlockX, oarlockY + 0.4, 0.4, color: foam)
        let nearArm = solveRowerElbow2D(
            shoulderX: shX, shoulderY: shY + 0.2,
            handX: nearOar.handleX, handY: nearOar.handleY,
            upperArmLength: upperArmLength, forearmLength: forearmLength
        )
        Replay2DFigure.drawShoulderCap(context, shX, shY + 0.2, color: accent, radius: 1.38)
        Replay2DFigure.taperedLimb(
            context, shX, shY + 0.2, nearArm.jointX, nearArm.jointY,
            proximalWidth: 2.35, distalWidth: 1.75, color: accent
        )
        Replay2DFigure.taperedLimb(
            context, nearArm.jointX, nearArm.jointY, nearArm.endX, nearArm.endY,
            proximalWidth: 1.8, distalWidth: 1.3, color: skin
        )
        Replay2DFigure.disc(context, nearArm.jointX, nearArm.jointY, 0.95, color: skin)
        Replay2DFigure.disc(context, nearArm.endX, nearArm.endY, 1.05, color: skin)
        if !a.reduce && k.bladeDepth > 0.06 {
            // Catch foam plus a lighter mid-drive mist keep the buried blade
            // readable.
            let depth = k.bladeDepth
            Replay2DFigure.disc(context, nearOar.bladeTipX, bobY + 2.8, 1.15 + depth * 0.85, color: foam)
            Replay2DFigure.disc(context, nearOar.bladeTipX + 2.6, bobY + 1.5, 0.85 + depth * 0.55, color: foam)
            Replay2DFigure.disc(context, nearOar.bladeTipX - 1.6, bobY + 1.9, 0.7 + depth * 0.4, color: foam)
            Replay2DFigure.disc(
                context, nearOar.bladeTipX + 0.8, bobY + 3.4, 0.55 + depth * 0.35,
                color: foam.opacity(0.55)
            )
            Replay2DFigure.disc(
                context, farOar.bladeTipX, bobY + 1.8, 0.7 + depth * 0.4,
                color: foam.opacity(0.4)
            )
        }
    }
}
