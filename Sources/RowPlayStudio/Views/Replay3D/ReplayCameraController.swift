import Foundation
import Observation
import RealityKit
import RowPlayCore

/// Owns scene-local camera interaction and RealityKit transform application.
/// Playback time remains owned by `ReplayState` and its existing timeline.
@MainActor
@Observable
final class ReplayCameraController {
    var orbit = ReplayCameraOrbit()

    @ObservationIgnored private var currentPose: ReplayCameraPose?
    @ObservationIgnored private var smoothedSpeed: Double = 0
    @ObservationIgnored private var previousDistance: Double?
    @ObservationIgnored private var previousPreset: ReplayCameraPreset?
    @ObservationIgnored private var appliedResetGeneration: Int?
    @ObservationIgnored private var appliedDiscontinuityGeneration: Int?
    @ObservationIgnored private var appliedPlaybackTickGeneration: UInt64?
    @ObservationIgnored private var dragBaseline: ReplayCameraOrbit?
    @ObservationIgnored private var magnificationBaseline: ReplayCameraOrbit?
    @ObservationIgnored private var forceSnap = true

    private static let dragRadiansPerPoint = 0.006
    private static let speedDampingRate = 3.0
    private static let maximumContinuousDistanceDelta = 30.0

    func update(
        camera: PerspectiveCamera,
        layout: ReplayCourseLayout,
        distance: Double,
        deltaTime: TimeInterval,
        playbackTickGeneration: UInt64,
        preset: ReplayCameraPreset,
        reduceMotion: Bool,
        isPlaying: Bool,
        resetGeneration: Int,
        discontinuityGeneration: Int
    ) {
        let safeDistance = distance.isFinite ? distance : 0
        let rawDeltaTime = deltaTime.isFinite && deltaTime > 0 ? deltaTime : 0
        let hasNewPlaybackTick = appliedPlaybackTickGeneration.map {
            $0 != playbackTickGeneration
        } ?? isPlaying
        let safeDeltaTime = hasNewPlaybackTick ? rawDeltaTime : 0
        let distanceDelta = previousDistance.map { safeDistance - $0 } ?? 0

        let resetChanged = appliedResetGeneration.map { $0 != resetGeneration } ?? false
        let discontinuityChanged = appliedDiscontinuityGeneration.map {
            $0 != discontinuityGeneration
        } ?? false
        let presetChanged = previousPreset.map { $0 != preset } ?? true
        let firstUpdate = previousDistance == nil
        let movementDiscontinuity = distanceDelta < 0
            || distanceDelta > Self.maximumContinuousDistanceDelta
        let pausedMovement = !isPlaying
            && !hasNewPlaybackTick
            && previousDistance != nil
            && distanceDelta != 0
        let continuousMovement = hasNewPlaybackTick
            && safeDeltaTime > 0
            && distanceDelta >= 0
            && distanceDelta <= Self.maximumContinuousDistanceDelta
            && !discontinuityChanged

        if resetChanged {
            orbit.reset()
            endInteractions()
        }

        if resetChanged || discontinuityChanged || movementDiscontinuity || pausedMovement {
            smoothedSpeed = 0
        } else if continuousMovement {
            let instantaneousSpeed = distanceDelta / safeDeltaTime
            let speedFactor = ReplayMotion.dampFactor(
                rate: Self.speedDampingRate,
                dt: safeDeltaTime
            )
            smoothedSpeed += (instantaneousSpeed - smoothedSpeed) * speedFactor
        }

        let participantPosition = layout.position(at: safeDistance)
        let courseTangent = layout.tangent(at: safeDistance)
        let targetPose = ReplayCameraSolver.targetPose(
            preset: preset,
            participant: participantPosition,
            tangent: courseTangent,
            speed: smoothedSpeed,
            orbit: orbit,
            reduceMotion: reduceMotion
        )
        let shouldSnap = forceSnap
            || firstUpdate
            || resetChanged
            || discontinuityChanged
            || presetChanged
            || reduceMotion
            || movementDiscontinuity
            || pausedMovement
        let solvedPose = shouldSnap
            ? targetPose
            : ReplayCameraSolver.smoothedPose(
                current: currentPose ?? targetPose,
                target: targetPose,
                dt: safeDeltaTime,
                reduceMotion: reduceMotion
            )

        apply(solvedPose.isFinite ? solvedPose : targetPose, to: camera)
        currentPose = solvedPose.isFinite ? solvedPose : targetPose
        previousDistance = safeDistance
        previousPreset = preset
        appliedResetGeneration = resetGeneration
        appliedDiscontinuityGeneration = discontinuityGeneration
        appliedPlaybackTickGeneration = playbackTickGeneration
        forceSnap = false
    }

    func updateOrbitDrag(translationX: Double, translationY: Double) {
        guard translationX.isFinite, translationY.isFinite else { return }
        if dragBaseline == nil {
            dragBaseline = orbit
        }
        guard var updated = dragBaseline else { return }
        updated.rotate(
            yawDelta: -translationX * Self.dragRadiansPerPoint,
            pitchDelta: -translationY * Self.dragRadiansPerPoint
        )
        orbit = updated
        forceSnap = true
    }

    func endOrbitDrag() {
        dragBaseline = nil
    }

    func updateOrbitMagnification(_ magnification: Double) {
        guard magnification.isFinite, magnification > 0 else { return }
        if magnificationBaseline == nil {
            magnificationBaseline = orbit
        }
        guard var updated = magnificationBaseline else { return }
        updated.zoom(magnification: magnification)
        orbit = updated
        forceSnap = true
    }

    func endOrbitMagnification() {
        magnificationBaseline = nil
    }

    func resetOrbit() {
        orbit.reset()
        endInteractions()
        forceSnap = true
    }

    func resetSceneState() {
        currentPose = nil
        smoothedSpeed = 0
        previousDistance = nil
        previousPreset = nil
        appliedResetGeneration = nil
        appliedDiscontinuityGeneration = nil
        appliedPlaybackTickGeneration = nil
        endInteractions()
        forceSnap = true
    }

    private func endInteractions() {
        dragBaseline = nil
        magnificationBaseline = nil
    }

    private func apply(_ pose: ReplayCameraPose, to camera: PerspectiveCamera) {
        let position = SIMD3<Float>(
            finiteFloat(pose.positionX),
            finiteFloat(pose.positionY),
            finiteFloat(pose.positionZ)
        )
        let target = SIMD3<Float>(
            finiteFloat(pose.targetX),
            finiteFloat(pose.targetY),
            finiteFloat(pose.targetZ)
        )
        let fieldOfView = finiteFloat(pose.fieldOfViewDegrees, fallback: 46)

        camera.camera.fieldOfViewInDegrees = min(51, max(46, fieldOfView))
        camera.look(at: target, from: position, relativeTo: nil)
    }

    private func finiteFloat(_ value: Double, fallback: Float = 0) -> Float {
        guard value.isFinite, value >= -Double(Float.greatestFiniteMagnitude),
              value <= Double(Float.greatestFiniteMagnitude) else {
            return fallback
        }
        return Float(value)
    }
}
