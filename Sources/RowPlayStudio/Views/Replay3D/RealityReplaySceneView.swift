import Foundation
import Observation
import RealityKit
import RowPlayCore
import RowPlayPlatform
import SwiftUI

/// SwiftUI view wrapping a `RealityView` that displays the 3D workout replay.
///
/// The entity graph is created once in the `make` closure and updated
/// per-frame in the `update` closure. `ReplayState` is the single
/// playback clock — no independent timer is added.
struct RealityReplaySceneView: View {
    let detail: WorkoutDetail
    @Binding var state: ReplayState
    let reduceMotion: Bool
    let ghostDetail: WorkoutDetail?
    let cameraPreset: ReplayCameraPreset
    let cameraResetGeneration: Int
    let replayDiscontinuityGeneration: Int

    @Environment(\.colorScheme) private var colorScheme
    @State private var sceneState = Replay3DSceneState()
    @State private var cameraController = ReplayCameraController()
    @State private var lastTickDate: Date?

    private var sport: Sport { detail.workout.sport }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !state.playing)) { timeline in
            realityContent(timeline: timeline)
        }
        .frame(minHeight: 300)
        .onChange(of: state.playing) { _, playing in
            if playing {
                lastTickDate = nil
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("3D workout replay")
        .accessibilityValue(accessibilityDescription)
        .simultaneousGesture(orbitDragGesture)
        .simultaneousGesture(orbitMagnificationGesture)
        .simultaneousGesture(orbitResetGesture)
        .onChange(of: cameraPreset) { _, _ in
            cameraController.endOrbitDrag()
            cameraController.endOrbitMagnification()
        }
    }

    // MARK: - Reality Content

    @ViewBuilder
    private func realityContent(timeline: TimelineViewDefaultContext) -> some View {
        RealityView { make in
            // Precompute immutable aggregates once.
            sceneState.livePoseContext = computePoseContext(strokes: detail.strokes)
            sceneState.liveMedianHR = computeMedianHR(strokes: detail.strokes)
            if let ghost = ghostDetail {
                sceneState.ghostPoseContext = computePoseContext(strokes: ghost.strokes)
                sceneState.ghostMedianHR = computeMedianHR(strokes: ghost.strokes)
            }

            let container = Replay3DSceneBuilder.buildScene(
                sport: sport,
                colorScheme: colorScheme
            )
            make.add(container.root)
            sceneState.container = container
            cameraController.resetSceneState()
        } update: { _ in
            guard let container = sceneState.container else { return }
            let pose = currentPose()
            let ghostSample = currentGhostSample()

            Replay3DSceneBuilder.updateScene(
                container: container,
                livePose: pose,
                liveDistance: state.currentFrame.d,
                sport: sport,
                ghostPose: ghostSample.pose,
                ghostDistance: ghostSample.distance,
                ghostVisible: ghostDetail != nil,
                reduceMotion: reduceMotion,
                deltaTime: sceneState.lastFrameDelta,
                playbackTickGeneration: sceneState.playbackTickGeneration,
                isPlaying: state.playing,
                cameraController: cameraController,
                cameraPreset: cameraPreset,
                cameraResetGeneration: cameraResetGeneration,
                replayDiscontinuityGeneration: replayDiscontinuityGeneration
            )
        }
        .onChange(of: timeline.date) { _, newDate in
            guard state.playing else {
                lastTickDate = newDate
                sceneState.lastFrameDelta = 0
                return
            }
            let tick = ReplayPlaybackClock.tick(
                lastTickDate: lastTickDate,
                currentDate: newDate
            )
            lastTickDate = tick.lastTickDate
            sceneState.lastFrameDelta = tick.delta
            sceneState.playbackTickGeneration &+= 1
            state.tick(deltaTime: tick.delta)
        }
    }

    // MARK: - Pose Computation

    private func currentPose() -> ReplayStrokePose {
        let frame = state.currentFrame
        let fallbackPhase = stableFallbackPhase(distance: frame.d)

        if detail.strokes.isEmpty {
            return .fallback(sport: sport, phase: fallbackPhase, rate: frame.cadence)
        }

        guard let context = sceneState.livePoseContext else {
            return .fallback(sport: sport, phase: fallbackPhase, rate: frame.cadence)
        }

        // frame.t is relative to replay start; offset by first stroke's absolute time.
        let absoluteT = frame.t + (detail.strokes.first?.t ?? 0)
        let strokeIndex = ReplaySample.sampleIndexAt(strokes: detail.strokes, t: absoluteT)
        guard strokeIndex >= 0 else {
            return .fallback(sport: sport, phase: fallbackPhase, rate: frame.cadence)
        }

        let strokes = detail.strokes
        let startD = strokes[strokeIndex].d
        let endD = strokeIndex + 1 < strokes.count ? strokes[strokeIndex + 1].d : startD
        let startT = strokes[strokeIndex].t
        let endT = strokeIndex + 1 < strokes.count ? strokes[strokeIndex + 1].t : startT

        // Use absoluteT for computeAtTime — frame.t is replay-relative,
        // stroke times are absolute.
        let timeFrame = ReplayFrame(
            t: absoluteT, d: frame.d, pace: frame.pace,
            cadence: frame.cadence, heartRate: frame.heartRate,
            watts: frame.watts, progress: frame.progress
        )
        let pose = ReplayStrokePose.computeAtTime(
            frame: timeFrame,
            strokeStartTime: startT,
            strokeEndTime: endT,
            strokeStartDistance: startD,
            strokeEndDistance: endD,
            strokeIndex: strokeIndex,
            context: context,
            medianHR: sceneState.liveMedianHR,
            duration: state.duration
        )

        return reduceMotion ? .reducedMotion(pose) : pose
    }

    private func currentGhostSample() -> (pose: ReplayStrokePose?, distance: Double) {
        guard let ghost = ghostDetail, !ghost.strokes.isEmpty else { return (nil, 0) }
        guard let context = sceneState.ghostPoseContext else { return (nil, 0) }
        let ghostTime = ghostTimeAtCurrentElapsedTime(strokes: ghost.strokes)
        let ghostFrame = ReplaySample.sampleAt(strokes: ghost.strokes, t: ghostTime)
        let strokeIndex = ReplaySample.sampleIndexAt(strokes: ghost.strokes, t: ghostTime)
        guard strokeIndex >= 0 else {
            let fallback = ReplayStrokePose.fallback(
                sport: sport,
                phase: stableFallbackPhase(distance: ghostFrame.d),
                rate: ghostFrame.cadence
            )
            return (reduceMotion ? .reducedMotion(fallback) : fallback, ghostFrame.d)
        }

        let strokes = ghost.strokes
        let startD = strokes[strokeIndex].d
        let endD = strokeIndex + 1 < strokes.count ? strokes[strokeIndex + 1].d : startD
        let startT = strokes[strokeIndex].t
        let endT = strokeIndex + 1 < strokes.count ? strokes[strokeIndex + 1].t : startT

        let pose = ReplayStrokePose.computeAtTime(
            frame: ghostFrame,
            strokeStartTime: startT,
            strokeEndTime: endT,
            strokeStartDistance: startD,
            strokeEndDistance: endD,
            strokeIndex: strokeIndex,
            context: context,
            medianHR: sceneState.ghostMedianHR,
            duration: ghost.strokes.last?.t ?? 1
        )
        return (reduceMotion ? .reducedMotion(pose) : pose, ghostFrame.d)
    }

    private func ghostTimeAtCurrentElapsedTime(strokes: [Stroke]) -> TimeInterval {
        Replay3DPlayback.absoluteTime(elapsed: state.time, strokes: strokes)
    }

    private func stableFallbackPhase(distance: Double) -> Double {
        let safeDistance = distance.isFinite ? max(0, distance) : 0
        let metersPerCycle = ReplayMotion.metersPerCycle(for: sport)
        return safeDistance / metersPerCycle * Double.pi * 2
    }

    // MARK: - Context Builders (called once)

    /// Proper median matching the web `median()` helper: averages the two
    /// middle values for even-length arrays.
    private func computePoseContext(strokes: [Stroke]) -> ReplayStrokePoseContext {
        let watts = strokes.map(\.watts)
        let peakWatts = watts.max() ?? 0
        let wattsAsDoubles = watts.map { Double($0) }
        let medianWatts = Int(properMedian(wattsAsDoubles, fallback: 0))
        let dps = strokes.enumerated().compactMap { i, s -> Double? in
            guard i > 0 else { return nil }
            let delta = s.d - strokes[i - 1].d
            return delta > 0 ? delta : nil
        }
        let defaultDPS: Double = switch sport {
        case .rower: 11
        case .skierg: 8
        case .bike: 5
        }
        let medianDPS = properMedian(dps, fallback: defaultDPS)

        return ReplayStrokePoseContext(
            sport: sport,
            peakWatts: peakWatts,
            medianWatts: medianWatts,
            medianDPS: medianDPS,
            maxHR: strokes.compactMap(\.heartRate).max() ?? 0
        )
    }

    private func computeMedianHR(strokes: [Stroke]) -> Int {
        let hrs = strokes.compactMap(\.heartRate).map { Double($0) }
        return Int(properMedian(hrs, fallback: 0))
    }

    /// Proper median: averages two middle values for even-length arrays,
    /// matching the web `median()` helper in `strokeModel.ts`.
    private func properMedian(_ values: [Double], fallback: Double) -> Double {
        let nums = values.filter(\.isFinite).sorted()
        guard !nums.isEmpty else { return fallback }
        let mid = nums.count / 2
        if nums.count % 2 == 0 {
            return (nums[mid - 1] + nums[mid]) / 2
        }
        return nums[mid]
    }

    // MARK: - Camera Gestures

    private var orbitDragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard cameraPreset == .orbit else { return }
                cameraController.updateOrbitDrag(
                    translationX: Double(value.translation.width),
                    translationY: Double(value.translation.height)
                )
            }
            .onEnded { _ in
                cameraController.endOrbitDrag()
            }
    }

    private var orbitMagnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard cameraPreset == .orbit else { return }
                cameraController.updateOrbitMagnification(Double(value.magnification))
            }
            .onEnded { _ in
                cameraController.endOrbitMagnification()
            }
    }

    private var orbitResetGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                cameraController.resetOrbit()
            }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let sportName = sport.displayName
        let progress = Int(state.currentFrame.progress * 100)
        let pace = RowPlayFormatting.pace(state.currentFrame.pace)
        let cadence = state.currentFrame.cadence.isFinite ? String(Int(state.currentFrame.cadence.rounded())) : "-"
        let unit = sport.cadenceUnit
        let ghost = ghostDetail != nil ? "ghost present" : "no ghost"
        return "\(sportName) · \(cameraPreset.displayName) camera · \(progress)% · \(pace) · \(cadence) \(unit) · \(ghost)"
    }

}

enum Replay3DPlayback {
    static func absoluteTime(elapsed: TimeInterval, strokes: [Stroke]) -> TimeInterval {
        guard let firstTime = strokes.first?.t, let lastTime = strokes.last?.t else { return 0 }
        let duration = max(0, lastTime - firstTime)
        let safeElapsed = elapsed.isFinite ? elapsed : 0
        return firstTime + min(max(0, safeElapsed), duration)
    }
}

// MARK: - Scene State

/// Mutable state for the 3D scene, kept separate from the view struct.
/// Precomputed aggregates avoid O(N log N) work on every frame.
@MainActor
@Observable
final class Replay3DSceneState {
    var container: Replay3DSceneContainer?
    @ObservationIgnored var lastFrameDelta: TimeInterval = 0
    /// Changes exactly once per playback-clock callback. RealityView may
    /// refresh for gestures or controls between ticks; render adapters use
    /// this token to avoid integrating the same frame delta twice.
    var playbackTickGeneration: UInt64 = 0
    /// Precomputed live pose context (immutable during replay).
    var livePoseContext: ReplayStrokePoseContext?
    /// Precomputed live median HR (immutable during replay).
    var liveMedianHR: Int = 0
    /// Precomputed ghost pose context (immutable during replay).
    var ghostPoseContext: ReplayStrokePoseContext?
    /// Precomputed ghost median HR (immutable during replay).
    var ghostMedianHR: Int = 0
}
