import Foundation

/// Compact rower projection retained for equipment and fallback-rig consumers.
/// The V4 motion graph remains the single source of choreography.
public struct ReplayRowerKinematics: Equatable, Sendable {
    public let legExtension: Double
    public let bodySwing: Double
    public let armDraw: Double
    public let bladeDepth: Double
    public let bladeFeather: Double
    public let surge: Double
    public let vertical: Double
}

/// Compact SkiErg projection retained for equipment and fallback-rig consumers.
public struct ReplaySkierKinematics: Equatable, Sendable {
    public let cycle: Double
    public let armPress: Double
    public let hipHinge: Double
    public let kneeFlex: Double
    public let poleContact: Double
    public let poleSweep: Double
    public let elbowLoad: Double
    public let armExtension: Double
    public let poleLift: Double
    public let poleFlight: Double
    public let rebound: Double
    public let surge: Double
}

/// Sagittal elbow-plane branch direction for a SkiErg two-bone solve.
public struct ReplaySkierElbowDirection: Equatable, Sendable {
    public let vertical: Double
    public let foreAft: Double

    public init(vertical: Double, foreAft: Double) {
        self.vertical = vertical
        self.foreAft = foreAft
    }
}

/// Compact bike projection retained for equipment and fallback-rig consumers.
public struct ReplayBikeKinematics: Equatable, Sendable {
    public let crankAngle: Double
    public let torsoSway: Double
    public let hipRock: Double
    public let anklePitchLeft: Double
    public let anklePitchRight: Double
}

/// Compatibility projections ported from merged RowPlay V4 `sportKinematics.ts`.
public enum ReplaySportKinematics {
    public static func solveRower(_ pose: ReplayStrokePose) -> ReplayRowerKinematics {
        let graph = ReplayMotionGraph.sampleRower(pose: pose)
        return ReplayRowerKinematics(
            legExtension: graph.body.legExtension.value,
            bodySwing: graph.body.spineHinge.value,
            armDraw: graph.body.armDraw.value,
            bladeDepth: graph.contacts.bladeWater.value,
            bladeFeather: graph.contacts.bladeFeather.value,
            surge: graph.accents.surge.value,
            vertical: graph.accents.vertical.value
        )
    }

    public static func solveSkier(_ pose: ReplayStrokePose) -> ReplaySkierKinematics {
        let graph = ReplayMotionGraph.sampleSkier(pose: pose)
        return ReplaySkierKinematics(
            cycle: graph.timing.cycle,
            armPress: graph.body.armPress.value,
            hipHinge: graph.body.pelvisHinge.value,
            kneeFlex: graph.body.kneeFlex.value,
            poleContact: graph.contacts.polePlant.value,
            poleSweep: graph.body.poleSweep.value,
            elbowLoad: graph.body.elbowLoad.value,
            armExtension: graph.body.armExtension.value,
            poleLift: graph.body.poleLift.value,
            poleFlight: graph.body.poleFlight.value,
            rebound: graph.accents.rebound.value,
            surge: graph.accents.surge.value
        )
    }

    public static func solveBike(_ pose: ReplayStrokePose) -> ReplayBikeKinematics {
        let graph = ReplayMotionGraph.sampleBike(pose: pose)
        let effort = secondaryScale(pose.intensity)
        return ReplayBikeKinematics(
            crankAngle: graph.crank.angle,
            torsoSway: graph.body.torsoSway.value * 0.34 * effort,
            hipRock: graph.body.pelvisRock.value * 0.3 * effort,
            anklePitchLeft: -0.05 + graph.leftPedal.ankleFlex.value * 0.3,
            anklePitchRight: -0.05 + graph.rightPedal.ankleFlex.value * 0.3
        )
    }

    /// Resolve the continuous down → back → recovery SkiErg elbow branch.
    public static func solveSkierElbowDirection(
        _ kinematics: ReplaySkierKinematics
    ) -> ReplaySkierElbowDirection {
        let sweep = clampUnit(kinematics.poleSweep)
        let angle: Double
        if kinematics.cycle <= ReplayMotionGraph.skiPoleOffCycle {
            angle = .pi + sweep * (.pi / 2)
        } else {
            angle = .pi * 1.5 - (1 - sweep) * (.pi / 2)
        }
        return ReplaySkierElbowDirection(vertical: cos(angle), foreAft: sin(angle))
    }

    private static func secondaryScale(_ intensity: Double) -> Double {
        0.9 + clampUnit(intensity.isFinite ? intensity : 0.5) * 0.1
    }

    private static func clampUnit(_ value: Double) -> Double {
        value.isFinite ? max(0, min(1, value)) : 0
    }
}
