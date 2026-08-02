import Foundation

/// Options for one hand's digit closure around an equipment surface.
public struct ReplayHandGripClosureOptions: Sendable {
    public let side: Double
    public let surface: ReplayHandGripSurface
    /// Base opposition (local Z at the thumb root) bringing the thumb across.
    public let thumbOppose: Double
    /// Effective flesh radius of a finger pad pressed onto the surface.
    public let fingerFlesh: Double?
    /// Effective flesh radius of the thumb pad.
    public let thumbFlesh: Double?
    /// Solve all three bounded finger stages together for a final enclosure
    /// instead of freezing each stage on its first surface contact — the
    /// palm-supported BikeErg hood contract.  Pole/scull closures omit it.
    public let wrapFingerStages: Bool

    public init(
        side: Double,
        surface: ReplayHandGripSurface,
        thumbOppose: Double,
        fingerFlesh: Double? = nil,
        thumbFlesh: Double? = nil,
        wrapFingerStages: Bool = false
    ) {
        self.side = side
        self.surface = surface
        self.thumbOppose = thumbOppose
        self.fingerFlesh = fingerFlesh
        self.thumbFlesh = thumbFlesh
        self.wrapFingerStages = wrapFingerStages
    }
}

/// Deterministic digit-closure solver ported from RowPlay `handGrip.ts`.
///
/// Finger chains are first posed into the `handClosureCup` carrying posture
/// the grip channel was fitted in; each stage then flexes until a constrained
/// bone point reaches the surface (radius + pad flesh) and stops at contact.
/// Curl angles are outputs of the equipment geometry, not per-sport tuning
/// constants.  This is an install-time solve: callers cache the returned
/// helper poses rather than call it per frame.
public enum ReplayHandClosure {
    /// Full-fist anatomical maxima (MCP ~90°, PIP ~110°, DIP ~80°).
    public static let fingerStageLimits: [Double] = [1.57, 1.92, 1.4]
    /// Thumb MCP/IP maxima (~60/80°) with a mobile root.
    public static let thumbStageLimits: [Double] = [1.0, 1.25, 1.35]
    /// Digit-pad flesh calibrated from the rig's own approved envelope: the
    /// fitted SkiErg fist closes its bone helpers onto a 0.0169 m circle
    /// around the 0.016 m rendered rubber.
    public static let defaultDigitFlesh =
        ReplayGripGeometry.handFistRadius - ReplayGripGeometry.handFistReferenceGripRadius
    /// Axial allowance for a thumb pressing a flat handle end: the pad under
    /// the estimated tip, roughly a distal-phalanx pad length behind it.
    public static let thumbEndPadAllowance = 0.0095
    /// Samples used to sweep one stage's flexion range.
    static let closureEmergeSamples = 24
    /// Coarse deterministic search resolution for an opt-in final enclosure.
    static let wrapGridSteps = 16
    /// Final helper points may compress into a held surface by at most 0.5 mm.
    static let wrapMaxPenetration = 0.0005
    /// Contact is a 4 mm band around the surface, not an exact landing.
    static let contactBand = 0.004
    static let bisectionIterations = 28

    /// Close every digit of one hand around an equipment surface.  The
    /// capsule axis runs through `handChannelCentre(radius:side:)` along the
    /// hand's curl axis, thumb-ward positive.  Penetration is minimised, not
    /// forbidden: where no pose in anatomical range clears the surface the
    /// stage holds its least-penetrating flexion.
    public static func solve(
        chains: [ReplayHandDigitChain],
        options: ReplayHandGripClosureOptions
    ) -> ReplayHandGripClosure {
        let surface = options.surface
        let fingerFlesh = options.fingerFlesh ?? defaultDigitFlesh
        // Pose the finger chains into the fitted carrying cup before any
        // geometry is read: axis signing, closure, and contact reporting all
        // happen in the same space the renderer will draw.
        let posed = chains.map { cupChain($0, side: options.side) }
        var axis = ReplayGripGeometry.handCurlAxis(side: options.side)
        // Thumb-ward sign: the axis must point from the pinky side toward the
        // index/thumb side so `thumbEndAxial` has one meaning on both hands.
        if let index = posed.first(where: { $0.digit == .index }),
           let pinky = posed.first(where: { $0.digit == .pinky }) {
            let delta = index.joints[0].position - pinky.joints[0].position
            if ReplayGripGeometry.dot(delta, axis) < 0 {
                axis = SIMD3(-axis.x, -axis.y, -axis.z)
            }
        }
        let centre = ReplayGripGeometry.handChannelCentre(
            radius: surface.radius,
            side: options.side
        )

        var poses: [ReplayHandDigitStagePose] = []
        var contacts: [ReplayHandDigitContactReport] = []
        var workspace = ClosureWorkspace(axis: axis, centre: centre)

        for chain in posed {
            let isThumb = chain.digit == .thumb
            let limits = isThumb ? thumbStageLimits : fingerStageLimits
            let oppose = isThumb
                ? ReplayGripGeometry.mirrorSign(options.side) * options.thumbOppose
                : 0
            var flexions: [Double] = [0, 0, 0]
            let thumbEnd = isThumb && surface.thumbEndAxial != nil
            let flesh: Double
            if isThumb {
                flesh = options.thumbFlesh
                    ?? (thumbEnd ? thumbEndPadAllowance : defaultDigitFlesh)
            } else {
                flesh = fingerFlesh
            }

            // A thumb lies nearly along the shaft it opposes: in radial mode
            // only the pad tip is the opposing contact the solver may
            // constrain.  Fingers wrap across the shaft and constrain every
            // downstream point.
            func firstCollisionPoint(_ stage: Int) -> Int {
                (isThumb && !thumbEnd) ? chain.joints.count : stage + 1
            }

            func clearance(_ stage: Int) -> Double {
                workspace.digitPoints(chain, flexions: flexions, oppose: oppose)
                var nearest = Double.infinity
                var pointIndex = firstCollisionPoint(stage)
                while pointIndex <= chain.joints.count {
                    let point = workspace.points[pointIndex]
                    if thumbEnd, let thumbEndAxial = surface.thumbEndAxial {
                        // The thumb lies along the handle beyond its flat end
                        // and presses the end face from outside: clearance is
                        // the axial distance still to travel down onto the
                        // stop.
                        let axial = workspace.axialCoordinate(point)
                        nearest = min(nearest, axial - thumbEndAxial - flesh)
                    } else {
                        nearest = min(
                            nearest,
                            workspace.distanceToAxis(point) - surface.radius - flesh
                        )
                    }
                    pointIndex += 1
                }
                return nearest
            }

            func recordDigit(reportSegments: Bool = false) {
                workspace.digitPoints(chain, flexions: flexions, oppose: oppose)
                var surfaceDistance = Double.infinity
                var pointIndex = firstCollisionPoint(0)
                while pointIndex <= chain.joints.count {
                    let point = workspace.points[pointIndex]
                    let distance: Double
                    if thumbEnd, let thumbEndAxial = surface.thumbEndAxial {
                        distance = workspace.axialCoordinate(point) - thumbEndAxial - flesh
                    } else {
                        distance = workspace.distanceToAxis(point) - surface.radius - flesh
                    }
                    surfaceDistance = min(surfaceDistance, distance)
                    pointIndex += 1
                }
                var segmentSurfaceDistance: Double?
                if reportSegments {
                    var nearest = Double.infinity
                    for segment in 1..<chain.joints.count {
                        nearest = min(
                            nearest,
                            workspace.segmentDistanceToAxis(
                                workspace.points[segment],
                                workspace.points[segment + 1]
                            ) - surface.radius - flesh
                        )
                    }
                    segmentSurfaceDistance = nearest
                }
                contacts.append(
                    ReplayHandDigitContactReport(
                        digit: chain.digit,
                        surfaceDistance: surfaceDistance,
                        segmentSurfaceDistance: segmentSurfaceDistance,
                        contact: abs(surfaceDistance) < contactBand,
                        tip: workspace.points[chain.joints.count]
                    )
                )
                for stage in 0..<chain.joints.count {
                    poses.append(
                        ReplayHandDigitStagePose(
                            helper: chain.joints[stage].helper,
                            flex: flexions[stage],
                            oppose: stage == 0 ? oppose : 0
                        )
                    )
                }
            }

            var wrappedSolved = false
            if options.wrapFingerStages, !isThumb {
                // A palm-supported hood needs a final-pose enclosure, not the
                // first point reached while a finger is closing.  Search the
                // three bounded joint ranges together so the final chain can
                // land on the far side without any joint/tip point
                // penetrating the equipment.
                var bestScore = -Double.infinity
                var bestFlexions: (Double, Double, Double)?
                for proximal in 0...wrapGridSteps {
                    flexions[0] = limits[0] * Double(proximal) / Double(wrapGridSteps)
                    for intermediate in 0...wrapGridSteps {
                        flexions[1] = limits[1] * Double(intermediate) / Double(wrapGridSteps)
                        for distal in 0...wrapGridSteps {
                            flexions[2] = limits[2] * Double(distal) / Double(wrapGridSteps)
                            workspace.digitPoints(chain, flexions: flexions, oppose: oppose)
                            var nearest = Double.infinity
                            for pointIndex in 1...chain.joints.count {
                                nearest = min(
                                    nearest,
                                    workspace.distanceToAxis(workspace.points[pointIndex])
                                        - surface.radius - flesh
                                )
                            }
                            for segment in 1..<chain.joints.count {
                                nearest = min(
                                    nearest,
                                    workspace.segmentDistanceToAxis(
                                        workspace.points[segment],
                                        workspace.points[segment + 1]
                                    ) - surface.radius - flesh
                                )
                            }
                            let tipDistance = workspace.distanceToAxis(
                                workspace.points[chain.joints.count]
                            ) - surface.radius - flesh
                            if nearest < -wrapMaxPenetration
                                || abs(nearest) >= contactBand
                                || abs(tipDistance) >= contactBand {
                                continue
                            }
                            let wrap = Double(proximal + intermediate + distal)
                                / Double(wrapGridSteps)
                            let score = wrap - 12 * (abs(nearest) + abs(tipDistance))
                            if score > bestScore {
                                bestScore = score
                                bestFlexions = (flexions[0], flexions[1], flexions[2])
                            }
                        }
                    }
                }
                if let best = bestFlexions {
                    flexions[0] = best.0
                    flexions[1] = best.1
                    flexions[2] = best.2
                    wrappedSolved = true
                }
            }
            if wrappedSolved {
                recordDigit(reportSegments: true)
                continue
            }
            flexions = [0, 0, 0]
            for stage in 0..<chain.joints.count {
                let limit = stage < limits.count ? limits[stage] : 1
                flexions[stage] = 0
                if clearance(stage) > 0 {
                    // Outside the surface: close until the first constrained
                    // bone point lands on it.
                    flexions[stage] = limit
                    if clearance(stage) > 0 {
                        // Fully flexed still clears — the surface is beyond
                        // reach, or the sweep dips onto the surface mid-range
                        // and recedes (the thumb's arc bows away from a shaft
                        // seated against its own web).  Scan for a mid-range
                        // touch first.
                        var best = limit
                        var bestClearance = clearance(stage)
                        var touched = -1.0
                        var before = 0.0
                        for sample in 0..<closureEmergeSamples {
                            let candidate = limit * Double(sample) / Double(closureEmergeSamples)
                            flexions[stage] = candidate
                            let value = clearance(stage)
                            if value <= 0 {
                                touched = candidate
                                break
                            }
                            before = candidate
                            if value < bestClearance {
                                bestClearance = value
                                best = candidate
                            }
                        }
                        if touched < 0 {
                            // No touch anywhere in range.  A finger's
                            // non-terminal stage still curls fully: the wrap
                            // it carries brings the *next* segment around the
                            // shaft.  The tip stage — and every stage of a
                            // radial thumb — instead holds the closest
                            // approach.
                            let holdClosest = (isThumb && !thumbEnd)
                                || stage == chain.joints.count - 1
                            flexions[stage] = holdClosest ? best : limit
                            continue
                        }
                        var low = before
                        var high = touched
                        for _ in 0..<bisectionIterations {
                            let middle = (low + high) / 2
                            flexions[stage] = middle
                            if clearance(stage) > 0 { low = middle } else { high = middle }
                        }
                        flexions[stage] = low
                        continue
                    }
                    var low = 0.0
                    var high = limit
                    for _ in 0..<bisectionIterations {
                        let middle = (low + high) / 2
                        flexions[stage] = middle
                        if clearance(stage) > 0 { low = middle } else { high = middle }
                    }
                    flexions[stage] = low
                    continue
                }

                // The stage starts *inside* the surface: on a thick handle
                // the ulnar knuckles genuinely begin inboard of the rubber.
                // Close further — the segment sweeps around the shaft and
                // emerges onto the far side, which is what a real finger does
                // when the handle is thicker than the span from its own
                // knuckle.  Clearance is not monotonic across that sweep, so
                // sample first and then bisect the bracket containing the
                // crossing.
                var previous = 0.0
                var emerged = -1.0
                for sample in 1...closureEmergeSamples {
                    let candidate = limit * Double(sample) / Double(closureEmergeSamples)
                    flexions[stage] = candidate
                    if clearance(stage) > 0 {
                        emerged = candidate
                        break
                    }
                    previous = candidate
                }
                if emerged < 0 {
                    // No pose in anatomical range clears the surface.  Keep
                    // the flexion that penetrates least so the reported
                    // contact distance is the honest best this anatomy can
                    // reach.
                    var best = 0.0
                    var bestClearance = -Double.infinity
                    for sample in 0...closureEmergeSamples {
                        let candidate = limit * Double(sample) / Double(closureEmergeSamples)
                        flexions[stage] = candidate
                        let value = clearance(stage)
                        if value > bestClearance {
                            bestClearance = value
                            best = candidate
                        }
                    }
                    flexions[stage] = best
                    continue
                }
                // Stop at the first flexion that clears: the segment rests on
                // the surface instead of continuing to curl into free space.
                var low = previous
                var high = emerged
                for _ in 0..<bisectionIterations {
                    let middle = (low + high) / 2
                    flexions[stage] = middle
                    if clearance(stage) > 0 { high = middle } else { low = middle }
                }
                flexions[stage] = high
            }
            recordDigit()
        }
        return ReplayHandGripClosure(poses: poses, contacts: contacts)
    }

    /// Apply the carrying cup to a finger chain: conjugate every joint by the
    /// cup rotation about the `v4*Fingers` node, exactly the composition the
    /// renderer applies to the live helper (`rest × R_y(-side·cup)`).  Chains
    /// without a cup node (thumbs, minimal test rigs) pass through untouched.
    static func cupChain(_ chain: ReplayHandDigitChain, side: Double) -> ReplayHandDigitChain {
        guard let cup = chain.cupNode else { return chain }
        let roll = ReplayQuaternion(
            axis: SIMD3(0, 1, 0),
            angle: -ReplayGripGeometry.mirrorSign(side) * ReplayGripGeometry.handClosureCup
        )
        let conjugate = cup.quaternion * roll * cup.quaternion.inverted()
        return ReplayHandDigitChain(
            digit: chain.digit,
            joints: chain.joints.map { joint in
                ReplayHandDigitJoint(
                    helper: joint.helper,
                    position: conjugate.act(joint.position - cup.position) + cup.position,
                    quaternion: conjugate * joint.quaternion
                )
            },
            tipLength: chain.tipLength,
            cupNode: chain.cupNode
        )
    }

    /// Reusable forward-kinematics workspace for one closure solve.
    struct ClosureWorkspace {
        let axis: SIMD3<Double>
        let centre: SIMD3<Double>
        var points: [SIMD3<Double>] = Array(repeating: SIMD3(0, 0, 0), count: 4)

        init(axis: SIMD3<Double>, centre: SIMD3<Double>) {
            self.axis = axis
            self.centre = centre
        }

        /// Forward-kinematics of one digit chain for candidate stage
        /// flexions: joint origins plus the tip, in hand-local space.
        mutating func digitPoints(
            _ chain: ReplayHandDigitChain,
            flexions: [Double],
            oppose: Double
        ) {
            var parentPosition = chain.joints[0].position
            let opposeRotation = ReplayQuaternion(axis: SIMD3(0, 0, 1), angle: oppose)
            var parentQuaternion = chain.joints[0].quaternion * opposeRotation
                * ReplayQuaternion(axis: SIMD3(1, 0, 0), angle: -(flexions.first ?? 0))
            points[0] = parentPosition
            for stage in 1..<chain.joints.count {
                let joint = chain.joints[stage]
                let previous = chain.joints[stage - 1]
                // The child's rest offset/orientation relative to its parent.
                let localPosition = previous.quaternion.inverted().act(
                    joint.position - previous.position
                )
                let localQuaternion = previous.quaternion.inverted() * joint.quaternion
                let worldPosition = parentQuaternion.act(localPosition) + parentPosition
                var worldQuaternion = parentQuaternion * localQuaternion
                worldQuaternion = worldQuaternion * ReplayQuaternion(
                    axis: SIMD3(1, 0, 0),
                    angle: -(stage < flexions.count ? flexions[stage] : 0)
                )
                points[stage] = worldPosition
                parentPosition = worldPosition
                parentQuaternion = worldQuaternion
            }
            points[chain.joints.count] = parentPosition
                + parentQuaternion.act(SIMD3(0, chain.tipLength, 0))
        }

        func distanceToAxis(_ point: SIMD3<Double>) -> Double {
            let delta = point - centre
            let along = ReplayGripGeometry.dot(delta, axis)
            let radialSquared = ReplayGripGeometry.dot(delta, delta) - along * along
            return max(0, radialSquared).squareRoot()
        }

        /// Minimum radial distance from a complete phalanx segment to the
        /// grip axis.
        func segmentDistanceToAxis(_ start: SIMD3<Double>, _ end: SIMD3<Double>) -> Double {
            var radialStart = start - centre
            radialStart -= axis * ReplayGripGeometry.dot(radialStart, axis)
            var radialDelta = end - centre
            radialDelta -= axis * ReplayGripGeometry.dot(radialDelta, axis)
            radialDelta -= radialStart
            let lengthSquared = ReplayGripGeometry.dot(radialDelta, radialDelta)
            let along: Double
            if lengthSquared <= .ulpOfOne {
                along = 0
            } else {
                along = min(
                    max(-ReplayGripGeometry.dot(radialStart, radialDelta) / lengthSquared, 0),
                    1
                )
            }
            let closest = radialStart + radialDelta * along
            return ReplayGripGeometry.dot(closest, closest).squareRoot()
        }

        func axialCoordinate(_ point: SIMD3<Double>) -> Double {
            ReplayGripGeometry.dot(point - centre, axis)
        }
    }
}
