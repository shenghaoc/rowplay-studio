import Foundation

/// A scalar choreography channel evaluated at one deterministic replay phase.
///
/// Values are coordinate-neutral; velocity and acceleration are expressed per
/// second.  Keeping all three together means a renderer never has to
/// numerically differentiate a wrapped phase at a contact boundary.
public struct ReplayMotionChannel: Equatable, Sendable {
    public let value: Double
    public let velocity: Double
    public let acceleration: Double

    public init(value: Double, velocity: Double, acceleration: Double) {
        self.value = value
        self.velocity = velocity
        self.acceleration = acceleration
    }
}

/// Circular state for a crank or other continuously rotating mechanism.
public struct ReplayCircularMotion: Equatable, Sendable {
    public let angle: Double
    public let sin: Double
    public let cos: Double
    public let angularVelocity: Double
    public let angularAcceleration: Double

    public init(
        angle: Double,
        sin: Double,
        cos: Double,
        angularVelocity: Double,
        angularAcceleration: Double
    ) {
        self.angle = angle
        self.sin = sin
        self.cos = cos
        self.angularVelocity = angularVelocity
        self.angularAcceleration = angularAcceleration
    }
}

/// Cycle timing reconstructed from a `ReplayStrokePose`.
public struct ReplayMotionTiming: Equatable, Sendable {
    public let cycleIndex: Int
    public let cycle: Double
    public let phase: Double
    public let secondsPerCycle: Double
    public let phaseVelocity: Double
    public let phaseAcceleration: Double
    public let driveFraction: Double
    public let driveProgress: Double
    public let recoveryProgress: Double

    public init(
        cycleIndex: Int,
        cycle: Double,
        phase: Double,
        secondsPerCycle: Double,
        phaseVelocity: Double,
        phaseAcceleration: Double,
        driveFraction: Double,
        driveProgress: Double,
        recoveryProgress: Double
    ) {
        self.cycleIndex = cycleIndex
        self.cycle = cycle
        self.phase = phase
        self.secondsPerCycle = secondsPerCycle
        self.phaseVelocity = phaseVelocity
        self.phaseAcceleration = phaseAcceleration
        self.driveFraction = driveFraction
        self.driveProgress = driveProgress
        self.recoveryProgress = recoveryProgress
    }
}

public struct ReplayRowerMotionBody: Equatable, Sendable {
    public let seatTravel: ReplayMotionChannel
    public let pelvisTravel: ReplayMotionChannel
    public let legExtension: ReplayMotionChannel
    public let torsoSwing: ReplayMotionChannel
    public let spineHinge: ReplayMotionChannel
    public let torsoReach: ReplayMotionChannel
    public let armDraw: ReplayMotionChannel
    public let shoulderSet: ReplayMotionChannel
    public let handleTravel: ReplayMotionChannel
    public let headBob: ReplayMotionChannel
}

public struct ReplayRowerMotionContacts: Equatable, Sendable {
    public let footPressure: ReplayMotionChannel
    public let handleGrip: ReplayMotionChannel
    public let bladeWater: ReplayMotionChannel
    public let bladeFeather: ReplayMotionChannel
    public let oarlockLoad: ReplayMotionChannel
}

public struct ReplayRowerMotionAccents: Equatable, Sendable {
    public let surge: ReplayMotionChannel
    public let vertical: ReplayMotionChannel
}

public struct ReplayRowerMotionGraph: Equatable, Sendable {
    public let timing: ReplayMotionTiming
    public let body: ReplayRowerMotionBody
    public let contacts: ReplayRowerMotionContacts
    public let accents: ReplayRowerMotionAccents
}

public struct ReplaySkierMotionBody: Equatable, Sendable {
    public let armPress: ReplayMotionChannel
    public let shoulderDrop: ReplayMotionChannel
    public let hipHinge: ReplayMotionChannel
    public let pelvisHinge: ReplayMotionChannel
    public let kneeFlex: ReplayMotionChannel
    public let poleSweep: ReplayMotionChannel
    public let elbowLoad: ReplayMotionChannel
    public let armExtension: ReplayMotionChannel
    public let poleLift: ReplayMotionChannel
    public let poleFlight: ReplayMotionChannel
    public let reach: ReplayMotionChannel
    public let torsoCompression: ReplayMotionChannel
    public let spineHinge: ReplayMotionChannel
    public let headRise: ReplayMotionChannel
}

public struct ReplaySkierMotionContacts: Equatable, Sendable {
    public let poleGrip: ReplayMotionChannel
    public let polePlant: ReplayMotionChannel
    public let poleLoad: ReplayMotionChannel
    public let footPressure: ReplayMotionChannel
}

public struct ReplaySkierMotionAccents: Equatable, Sendable {
    public let surge: ReplayMotionChannel
    public let rebound: ReplayMotionChannel
}

public struct ReplaySkierMotionGraph: Equatable, Sendable {
    public let timing: ReplayMotionTiming
    public let body: ReplaySkierMotionBody
    public let contacts: ReplaySkierMotionContacts
    public let accents: ReplaySkierMotionAccents
}

public struct ReplayPedalMotion: Equatable, Sendable {
    public let rotation: ReplayCircularMotion
    public let legExtension: ReplayMotionChannel
    public let kneeLift: ReplayMotionChannel
    public let ankleFlex: ReplayMotionChannel
    public let drive: ReplayMotionChannel
    public let pedalLock: ReplayMotionChannel
}

public struct ReplayBikeMotionBody: Equatable, Sendable {
    public let torsoSway: ReplayMotionChannel
    public let hipRock: ReplayMotionChannel
    public let pelvisRock: ReplayMotionChannel
    public let spineLean: ReplayMotionChannel
    public let shoulderCounterRotation: ReplayMotionChannel
    public let headStabilization: ReplayMotionChannel
}

public struct ReplayBikeMotionContacts: Equatable, Sendable {
    public let handlebarGrip: ReplayMotionChannel
    public let saddleContact: ReplayMotionChannel
}

public struct ReplayBikeMotionGraph: Equatable, Sendable {
    public let timing: ReplayMotionTiming
    public let crank: ReplayCircularMotion
    public let body: ReplayBikeMotionBody
    public let leftPedal: ReplayPedalMotion
    public let rightPedal: ReplayPedalMotion
    public let contacts: ReplayBikeMotionContacts
}

/// Native port of RowPlay's merged V4 `motionGraph.ts` public sampler.
///
/// This is intentionally pure and portable.  RealityKit, SwiftUI, and the
/// bundled USDZ adapter consume its result but cannot add a second timing or
/// choreography truth.
public enum ReplayMotionGraph: Equatable, Sendable {
    case rower(ReplayRowerMotionGraph)
    case skierg(ReplaySkierMotionGraph)
    case bike(ReplayBikeMotionGraph)

    public static let skiElbowLoadCycle = 0.11
    public static let skiPoleReleaseStartCycle = 0.245
    public static let skiPoleOffCycle = 0.29
    public static let skiPoleApproachStartCycle = 0.88
    public static let skiPreplantStartCycle = 0.94

    public static func sample(sport: Sport, pose: ReplayStrokePose) -> ReplayMotionGraph {
        switch sport {
        case .rower:
            .rower(sampleRower(pose: pose))
        case .skierg:
            .skierg(sampleSkier(pose: pose))
        case .bike:
            .bike(sampleBike(pose: pose))
        }
    }

    public static func sampleRower(pose: ReplayStrokePose) -> ReplayRowerMotionGraph {
        let timing = timing(for: .rower, pose: pose)
        let cycle = timing.cycle
        let drive = timing.driveFraction
        let recovery = 1 - drive

        let legs = pulse(cycle, 0, drive * 0.56, drive + recovery * 0.34, 1)
        let torso = pulse(
            cycle,
            drive * 0.12,
            drive * 0.82,
            drive + recovery * 0.13,
            drive + recovery * 0.66
        )
        let arms = add(
            cruiseRamp(cycle, drive * 0.78, drive * 0.995),
            scale(quinticRamp(cycle, drive, drive + recovery * 0.34), -1)
        )
        let handle = add(scale(legs, 0.42), scale(torso, 0.32), scale(arms, 0.26))
        let shoulders = add(scale(torso, 0.45), scale(arms, 0.55))
        let driveBladeWater = pulse(cycle, -drive * 0.1, 0, drive * 0.78, drive * 0.95)
        let preCatchBladeWater = quinticRamp(cycle, drive + recovery * 0.82, 1)
        let bladeWater = add(driveBladeWater, preCatchBladeWater)
        let bladeFeather = pulse(
            cycle,
            drive + recovery * 0.025,
            drive + recovery * 0.13,
            drive + recovery * 0.75,
            1
        )
        let footPressure = pulse(cycle, drive * 0.02, drive * 0.17, drive * 0.63, drive * 0.86)
        let oarlockLoad = multiply(bladeWater, footPressure)
        let vertical = add(scale(centered(legs), 0.1), scale(centered(torso), 0.055))
        let headBob = add(scale(centered(handle), 0.09), scale(vertical, 0.22))
        let effort = intensityScale(pose)

        return ReplayRowerMotionGraph(
            timing: timing,
            body: ReplayRowerMotionBody(
                seatTravel: channel(legs, timing),
                pelvisTravel: channel(legs, timing),
                legExtension: channel(legs, timing),
                torsoSwing: channel(torso, timing),
                spineHinge: channel(torso, timing),
                torsoReach: channel(invert(torso), timing),
                armDraw: channel(arms, timing),
                shoulderSet: channel(shoulders, timing),
                handleTravel: channel(handle, timing),
                headBob: channel(headBob, timing)
            ),
            contacts: ReplayRowerMotionContacts(
                footPressure: channel(footPressure, timing),
                handleGrip: channel(constant(1), timing),
                bladeWater: channel(bladeWater, timing),
                bladeFeather: channel(bladeFeather, timing),
                oarlockLoad: channel(oarlockLoad, timing)
            ),
            accents: ReplayRowerMotionAccents(
                surge: channel(scale(centered(handle), effort), timing),
                vertical: channel(scale(vertical, effort), timing)
            )
        )
    }

    public static func sampleSkier(pose: ReplayStrokePose) -> ReplaySkierMotionGraph {
        let timing = timing(for: .skierg, pose: pose)
        let cycle = timing.cycle
        let arms = pulse(cycle, 0, skiPoleOffCycle, 0.305, 0.8)
        let hips = pulse(cycle, 0.025, 0.31, 0.325, 0.74)
        let knees = pulse(cycle, 0.06, 0.32, 0.34, 0.69)
        let poleSweep = add(
            cruiseRamp(cycle, 0, skiPoleOffCycle),
            scale(quinticRamp(cycle, skiPoleOffCycle, 1), -1)
        )
        let elbowLoad = pulse(cycle, 0, skiElbowLoadCycle, skiElbowLoadCycle, skiPoleOffCycle)
        let armExtension = add(
            cruiseRamp(cycle, skiElbowLoadCycle, skiPoleOffCycle),
            scale(quinticRamp(cycle, 0.72, 1), -1)
        )
        let poleLift = bump(cycle, skiPoleOffCycle, 1)
        let poleFlight = pulse(cycle, skiPoleOffCycle, 0.42, skiPoleApproachStartCycle, 1)
        let polePlant = add(
            invert(quinticRamp(cycle, skiPoleReleaseStartCycle, skiPoleOffCycle)),
            quinticRamp(cycle, skiPreplantStartCycle, 1)
        )
        let poleLoad = pulse(cycle, 0.012, 0.095, 0.17, 0.275)
        let footPressure = pulse(cycle, 0.025, 0.12, 0.19, 0.32)
        let torsoCompression = add(scale(hips, 0.66), scale(knees, 0.34))
        let rebound = bump(cycle, 0.32, 0.9)
        let headRise = scale(rebound, 0.16)
        let effort = intensityScale(pose)

        return ReplaySkierMotionGraph(
            timing: timing,
            body: ReplaySkierMotionBody(
                armPress: channel(arms, timing),
                shoulderDrop: channel(arms, timing),
                hipHinge: channel(hips, timing),
                pelvisHinge: channel(hips, timing),
                kneeFlex: channel(knees, timing),
                poleSweep: channel(poleSweep, timing),
                elbowLoad: channel(elbowLoad, timing),
                armExtension: channel(armExtension, timing),
                poleLift: channel(poleLift, timing),
                poleFlight: channel(poleFlight, timing),
                reach: channel(invert(arms), timing),
                torsoCompression: channel(torsoCompression, timing),
                spineHinge: channel(torsoCompression, timing),
                headRise: channel(headRise, timing)
            ),
            contacts: ReplaySkierMotionContacts(
                poleGrip: channel(constant(1), timing),
                polePlant: channel(polePlant, timing),
                poleLoad: channel(poleLoad, timing),
                footPressure: channel(footPressure, timing)
            ),
            accents: ReplaySkierMotionAccents(
                surge: channel(scale(poleSweep, effort), timing),
                rebound: channel(rebound, timing)
            )
        )
    }

    public static func sampleBike(pose: ReplayStrokePose) -> ReplayBikeMotionGraph {
        let timing = timing(for: .bike, pose: pose)
        let sineWave = sine(timing.cycle)
        let doubleAngle = timing.cycle * tau * 2
        let hipRock = Curve(
            value: sin(doubleAngle) * 0.14,
            dCycle: cos(doubleAngle) * tau * 2 * 0.14,
            ddCycle: -sin(doubleAngle) * tau * tau * 4 * 0.14
        )
        let torsoSway = scale(sineWave, 0.22)
        let spineLean = scale(cosine(timing.cycle), 0.065)
        let shoulders = scale(torsoSway, -0.62)
        let headStabilization = scale(add(scale(torsoSway, -1), scale(hipRock, -0.25)), 0.32)

        return ReplayBikeMotionGraph(
            timing: timing,
            crank: circular(timing),
            body: ReplayBikeMotionBody(
                torsoSway: channel(torsoSway, timing),
                hipRock: channel(hipRock, timing),
                pelvisRock: channel(hipRock, timing),
                spineLean: channel(spineLean, timing),
                shoulderCounterRotation: channel(shoulders, timing),
                headStabilization: channel(headStabilization, timing)
            ),
            leftPedal: pedal(timing, phaseOffset: 0),
            rightPedal: pedal(timing, phaseOffset: .pi),
            contacts: ReplayBikeMotionContacts(
                handlebarGrip: channel(constant(1), timing),
                saddleContact: channel(constant(1), timing)
            )
        )
    }

    private static let tau = Double.pi * 2
    private static let boundaryEpsilon = 1e-12

    private struct Curve {
        var value: Double
        var dCycle: Double
        var ddCycle: Double
    }

    private static func timing(for sport: Sport, pose: ReplayStrokePose) -> ReplayMotionTiming {
        let fallbackCycle = clamp(finite(pose.cycleFrac, fallback: 0), 0, 0.999_999)
        let sourcePhase = finite(pose.phase, fallback: fallbackCycle * tau)
        let rawCycle = sourcePhase / tau
        let cycle = wrappedUnit(rawCycle)
        let seconds = clamp(finite(pose.strokeSeconds, fallback: defaultSeconds(sport)), 0.2, 12)
        let drive = clamp(
            finite(pose.driveFrac, fallback: defaultDriveFraction(sport)),
            sport == .bike ? 0.5 : 0.26,
            sport == .bike ? 0.5 : 0.48
        )
        let isDrive = cycle < drive
        let rawIndex = floor(rawCycle)
        let cycleIndex: Int
        if rawIndex >= Double(Int.max) {
            cycleIndex = Int.max
        } else if rawIndex <= Double(Int.min) {
            cycleIndex = Int.min
        } else {
            cycleIndex = Int(rawIndex)
        }
        return ReplayMotionTiming(
            cycleIndex: cycleIndex,
            cycle: cycle,
            phase: cycle * tau,
            secondsPerCycle: seconds,
            phaseVelocity: tau / seconds,
            phaseAcceleration: 0,
            driveFraction: drive,
            driveProgress: isDrive ? cycle / drive : 1,
            recoveryProgress: isDrive ? 0 : (cycle - drive) / (1 - drive)
        )
    }

    private static func pedal(_ timing: ReplayMotionTiming, phaseOffset: Double) -> ReplayPedalMotion {
        let rotation = circular(timing, phaseOffset: phaseOffset)
        let sineWave = sine(timing.cycle, phaseOffset: phaseOffset)
        let cosineWave = cosine(timing.cycle, phaseOffset: phaseOffset)
        let legExtensionCurve = add(constant(0.5), scale(cosineWave, 0.5))
        let downstroke = add(constant(0.5), scale(sineWave, 0.5))
        let drive = multiply(downstroke, downstroke)
        let ankle = add(scale(sineWave, 0.44), scale(cosineWave, -0.11))
        return ReplayPedalMotion(
            rotation: rotation,
            legExtension: channel(legExtensionCurve, timing),
            kneeLift: channel(invert(legExtensionCurve), timing),
            ankleFlex: channel(ankle, timing),
            drive: channel(drive, timing),
            pedalLock: channel(constant(1), timing)
        )
    }

    private static func circular(_ timing: ReplayMotionTiming, phaseOffset: Double = 0) -> ReplayCircularMotion {
        let unwrapped = timing.phase + phaseOffset
        return ReplayCircularMotion(
            angle: wrappedRadians(unwrapped),
            sin: sin(unwrapped),
            cos: cos(unwrapped),
            angularVelocity: timing.phaseVelocity,
            angularAcceleration: timing.phaseAcceleration
        )
    }

    private static func channel(_ curve: Curve, _ timing: ReplayMotionTiming) -> ReplayMotionChannel {
        let cyclesPerSecond = 1 / timing.secondsPerCycle
        return ReplayMotionChannel(
            value: curve.value,
            velocity: curve.dCycle * cyclesPerSecond,
            acceleration: curve.ddCycle * cyclesPerSecond * cyclesPerSecond
        )
    }

    private static func quinticRamp(_ cycle: Double, _ start: Double, _ end: Double) -> Curve {
        let span = max(1e-6, end - start)
        if cycle <= start + boundaryEpsilon { return constant(0) }
        if cycle >= end - boundaryEpsilon { return constant(1) }
        let u = (cycle - start) / span
        let u2 = u * u
        let u3 = u2 * u
        let u4 = u3 * u
        let u5 = u4 * u
        return Curve(
            value: 6 * u5 - 15 * u4 + 10 * u3,
            dCycle: 30 * u2 * (u - 1) * (u - 1) / span,
            ddCycle: (120 * u3 - 180 * u2 + 60 * u) / (span * span)
        )
    }

    private static func cruiseRamp(_ cycle: Double, _ start: Double, _ end: Double) -> Curve {
        let span = max(1e-6, end - start)
        if cycle <= start + boundaryEpsilon { return constant(0) }
        if cycle >= end - boundaryEpsilon { return constant(1) }
        let easeSpan = span * 0.15
        let cruiseVelocity = 1 / (span - easeSpan)
        let elapsed = cycle - start
        func edge(_ u: Double) -> (velocity: Double, acceleration: Double, distance: Double) {
            let u2 = u * u
            let u3 = u2 * u
            let u4 = u3 * u
            let u5 = u4 * u
            let u6 = u5 * u
            return (
                6 * u5 - 15 * u4 + 10 * u3,
                30 * u2 * (u - 1) * (u - 1),
                u6 - 3 * u5 + 2.5 * u4
            )
        }
        if elapsed < easeSpan {
            let e = edge(elapsed / easeSpan)
            return Curve(
                value: cruiseVelocity * easeSpan * e.distance,
                dCycle: cruiseVelocity * e.velocity,
                ddCycle: cruiseVelocity * e.acceleration / easeSpan
            )
        }
        if elapsed > span - easeSpan {
            let e = edge((span - elapsed) / easeSpan)
            return Curve(
                value: 1 - cruiseVelocity * easeSpan * e.distance,
                dCycle: cruiseVelocity * e.velocity,
                ddCycle: -cruiseVelocity * e.acceleration / easeSpan
            )
        }
        return Curve(
            value: cruiseVelocity * (elapsed - easeSpan * 0.5),
            dCycle: cruiseVelocity,
            ddCycle: 0
        )
    }

    private static func constant(_ value: Double) -> Curve {
        Curve(value: value, dCycle: 0, ddCycle: 0)
    }

    private static func add(_ curves: Curve...) -> Curve {
        curves.reduce(Curve(value: 0, dCycle: 0, ddCycle: 0)) { result, curve in
            Curve(
                value: result.value + curve.value,
                dCycle: result.dCycle + curve.dCycle,
                ddCycle: result.ddCycle + curve.ddCycle
            )
        }
    }

    private static func scale(_ curve: Curve, _ amount: Double) -> Curve {
        Curve(value: curve.value * amount, dCycle: curve.dCycle * amount, ddCycle: curve.ddCycle * amount)
    }

    private static func invert(_ curve: Curve) -> Curve {
        Curve(value: 1 - curve.value, dCycle: -curve.dCycle, ddCycle: -curve.ddCycle)
    }

    private static func multiply(_ first: Curve, _ second: Curve) -> Curve {
        Curve(
            value: first.value * second.value,
            dCycle: first.dCycle * second.value + first.value * second.dCycle,
            ddCycle: first.ddCycle * second.value
                + 2 * first.dCycle * second.dCycle
                + first.value * second.ddCycle
        )
    }

    private static func pulse(_ cycle: Double, _ riseStart: Double, _ riseEnd: Double, _ fallStart: Double, _ fallEnd: Double) -> Curve {
        add(quinticRamp(cycle, riseStart, riseEnd), scale(quinticRamp(cycle, fallStart, fallEnd), -1))
    }

    private static func bump(_ cycle: Double, _ start: Double, _ end: Double) -> Curve {
        let ramp = quinticRamp(cycle, start, end)
        return Curve(
            value: 4 * ramp.value * (1 - ramp.value),
            dCycle: 4 * ramp.dCycle * (1 - 2 * ramp.value),
            ddCycle: 4 * (ramp.ddCycle * (1 - 2 * ramp.value) - 2 * ramp.dCycle * ramp.dCycle)
        )
    }

    private static func sine(_ cycle: Double, phaseOffset: Double = 0) -> Curve {
        let angle = cycle * tau + phaseOffset
        let s = sin(angle)
        let c = cos(angle)
        return Curve(value: s, dCycle: c * tau, ddCycle: -s * tau * tau)
    }

    private static func cosine(_ cycle: Double, phaseOffset: Double = 0) -> Curve {
        sine(cycle, phaseOffset: phaseOffset + .pi / 2)
    }

    private static func centered(_ curve: Curve) -> Curve {
        add(scale(curve, 2), constant(-1))
    }

    private static func intensityScale(_ pose: ReplayStrokePose) -> Double {
        0.88 + clamp(finite(pose.intensity, fallback: 0.5), 0, 1) * 0.12
    }

    private static func defaultSeconds(_ sport: Sport) -> Double {
        switch sport {
        case .bike: 60 / 80
        case .skierg: 60 / 32
        case .rower: 60 / 28
        }
    }

    private static func defaultDriveFraction(_ sport: Sport) -> Double {
        switch sport {
        case .bike: 0.5
        case .skierg: 0.34
        case .rower: 0.38
        }
    }

    private static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        max(minimum, min(maximum, value))
    }

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    private static func wrappedUnit(_ value: Double) -> Double {
        var wrapped = value.truncatingRemainder(dividingBy: 1)
        if wrapped < 0 { wrapped += 1 }
        return wrapped.isFinite ? wrapped : 0
    }

    private static func wrappedRadians(_ value: Double) -> Double {
        var wrapped = value.truncatingRemainder(dividingBy: tau)
        if wrapped < 0 { wrapped += tau }
        return wrapped.isFinite ? wrapped : 0
    }
}
