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
    /// Generic rival (past session, constant pace, or imported). Nil = no rival.
    let rival: ReplayRival?
    let selectedQuality: ReplayRenderQuality
    @Binding var effectiveQuality: ReplayRenderQuality
    let cameraPreset: ReplayCameraPreset
    let cameraResetGeneration: Int
    let replayDiscontinuityGeneration: Int

    @Environment(\.colorScheme) private var colorScheme
    @State private var sceneState = Replay3DSceneState()
    @State private var cameraController = ReplayCameraController()
    @State private var performanceController: ReplayPerformanceController
    @State private var lastTickDate: Date?

    private var sport: Sport { detail.workout.sport }

    init(
        detail: WorkoutDetail,
        state: Binding<ReplayState>,
        reduceMotion: Bool,
        rival: ReplayRival?,
        selectedQuality: ReplayRenderQuality,
        effectiveQuality: Binding<ReplayRenderQuality>,
        cameraPreset: ReplayCameraPreset,
        cameraResetGeneration: Int,
        replayDiscontinuityGeneration: Int
    ) {
        self.detail = detail
        _state = state
        self.reduceMotion = reduceMotion
        self.rival = rival
        self.selectedQuality = selectedQuality
        _effectiveQuality = effectiveQuality
        self.cameraPreset = cameraPreset
        self.cameraResetGeneration = cameraResetGeneration
        self.replayDiscontinuityGeneration = replayDiscontinuityGeneration
        _performanceController = State(
            initialValue: ReplayPerformanceController(selectedQuality: selectedQuality)
        )
    }

    var body: some View {
        let configuration = performanceController.effectiveQuality.configuration
        let interval = 1.0 / Double(configuration.targetFrameRate)
        TimelineView(.animation(minimumInterval: interval, paused: !state.playing)) { timeline in
            Replay3DQualityRebuildBoundary(
                effectiveQuality: performanceController.effectiveQuality,
                sceneIdentity: Replay3DSceneIdentity(
                    workoutID: detail.id,
                    rivalID: rival?.id,
                    sportRawValue: sport.rawValue
                )
            ) {
                realityContent(timeline: timeline, configuration: configuration)
            }
        }
        .frame(minHeight: 300)
        .onAppear {
            performanceController.resetForNewScene(selectedQuality: selectedQuality)
            effectiveQuality = performanceController.effectiveQuality
            resetPerformanceTiming()
        }
        .task {
            // Pre-load the bundled athlete character mesh once.
            if Replay3DSceneBuilder.athleteCatalog == nil {
                Replay3DSceneBuilder.athleteCatalog = await ReplayAthleteMeshCatalog()
            }
        }
        .onChange(of: state.playing) { _, playing in
            if playing {
                lastTickDate = nil
            }
        }
        .onChange(of: selectedQuality) { _, quality in
            performanceController.selectQuality(quality)
            effectiveQuality = performanceController.effectiveQuality
            resetPerformanceTiming()
        }
        .onChange(of: performanceController.effectiveQuality) { _, quality in
            effectiveQuality = quality
            resetPerformanceTiming()
        }
        .onChange(of: rival?.id) { _, _ in
            refreshGhostPoseAggregates()
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
    private func realityContent(
        timeline: TimelineViewDefaultContext,
        configuration: ReplayRenderConfiguration
    ) -> some View {
        RealityView { make in
            // Precompute immutable aggregates once per live workout, and per
            // rival identity so session A → session B cannot reuse A's pose/HR.
            if sceneState.livePoseContext == nil {
                sceneState.livePoseContext = computePoseContext(strokes: detail.strokes)
                sceneState.liveMedianHR = computeMedianHR(strokes: detail.strokes)
            }
            refreshGhostPoseAggregates()

            let container = Replay3DSceneBuilder.buildScene(
                sport: sport,
                colorScheme: colorScheme,
                configuration: configuration
            )
            make.add(container.root)
            sceneState.container = container
            cameraController.resetSceneState()
        } update: { _ in
            guard let container = sceneState.container else { return }
            let generation = sceneState.playbackTickGeneration
            let shouldMeasure = performanceController.shouldMeasureSceneUpdate(
                playbackTickGeneration: generation
            )
            let clock = ContinuousClock()
            let updateStart = shouldMeasure ? clock.now : nil
            let pose = currentPose()
            let ghostSample = currentGhostSample()

            Replay3DSceneBuilder.updateScene(
                container: container,
                livePose: pose,
                liveDistance: state.currentFrame.d,
                sport: sport,
                ghostPose: ghostSample.pose,
                ghostDistance: ghostSample.distance,
                ghostVisible: rival != nil,
                reduceMotion: reduceMotion,
                deltaTime: sceneState.lastFrameDelta,
                playbackTickGeneration: sceneState.playbackTickGeneration,
                isPlaying: state.playing,
                cameraController: cameraController,
                cameraPreset: cameraPreset,
                cameraResetGeneration: cameraResetGeneration,
                replayDiscontinuityGeneration: replayDiscontinuityGeneration
            )
            if let updateStart {
                let duration = updateStart.duration(to: clock.now)
                performanceController.recordSceneUpdateDuration(
                    milliseconds: Self.milliseconds(duration),
                    playbackTickGeneration: generation
                )
            }
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
            if let frameIntervalMilliseconds = ReplayPerformanceSampling
                .frameIntervalMilliseconds(
                    rawDelta: tick.rawDelta,
                    isPlaying: state.playing,
                    rendererMode: .threeD
                ) {
                performanceController.recordFrameInterval(
                    milliseconds: frameIntervalMilliseconds,
                    playbackTickGeneration: sceneState.playbackTickGeneration
                )
            }
            state.tick(deltaTime: tick.delta)
        }
    }

    private func resetPerformanceTiming() {
        lastTickDate = nil
        sceneState.lastFrameDelta = 0
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
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
        guard let rival, !rival.strokes.isEmpty else { return (nil, 0) }
        let ghostTime = ghostTimeAtCurrentElapsedTime(strokes: rival.strokes)
        let ghostFrame = ReplaySample.sampleAt(strokes: rival.strokes, t: ghostTime)

        // Constant-pace and imported rivals: deterministic fallback articulation.
        guard case let .genuine(context) = Replay3DGhostArticulation.select(
            rival: rival,
            poseContext: sceneState.ghostPoseContext
        ) else {
            let fallback = ReplayStrokePose.fallback(
                sport: sport,
                phase: stableFallbackPhase(distance: ghostFrame.d),
                rate: ghostFrame.cadence > 0 ? ghostFrame.cadence : defaultFallbackRate
            )
            return (reduceMotion ? .reducedMotion(fallback) : fallback, ghostFrame.d)
        }

        let strokeIndex = ReplaySample.sampleIndexAt(strokes: rival.strokes, t: ghostTime)
        guard strokeIndex >= 0 else {
            let fallback = ReplayStrokePose.fallback(
                sport: sport,
                phase: stableFallbackPhase(distance: ghostFrame.d),
                rate: ghostFrame.cadence
            )
            return (reduceMotion ? .reducedMotion(fallback) : fallback, ghostFrame.d)
        }

        let strokes = rival.strokes
        let startD = strokes[strokeIndex].d
        let endD = strokeIndex + 1 < strokes.count ? strokes[strokeIndex + 1].d : startD
        let startT = strokes[strokeIndex].t
        let endT = strokeIndex + 1 < strokes.count ? strokes[strokeIndex + 1].t : startT
        let originT = strokes.first?.t ?? 0
        let relativeDuration = max(0, (strokes.last?.t ?? originT) - originT)

        let pose = ReplayStrokePose.computeAtTime(
            frame: ghostFrame,
            strokeStartTime: startT,
            strokeEndTime: endT,
            strokeStartDistance: startD,
            strokeEndDistance: endD,
            strokeIndex: strokeIndex,
            context: context,
            medianHR: sceneState.ghostMedianHR,
            duration: relativeDuration > 0 ? relativeDuration : 1
        )
        return (reduceMotion ? .reducedMotion(pose) : pose, ghostFrame.d)
    }

    private var defaultFallbackRate: Double {
        switch sport {
        case .rower: return 28
        case .skierg: return 30
        case .bike: return 80
        }
    }

    private func ghostTimeAtCurrentElapsedTime(strokes: [Stroke]) -> TimeInterval {
        ReplayRaceGap.absoluteTime(elapsed: state.time, strokes: strokes)
    }

    private func stableFallbackPhase(distance: Double) -> Double {
        let safeDistance = distance.isFinite ? max(0, distance) : 0
        let metersPerCycle = ReplayMotion.metersPerCycle(for: sport)
        return safeDistance / metersPerCycle * Double.pi * 2
    }

    // MARK: - Context Builders (called once)

    /// Rebuild ghost pose/HR aggregates whenever the active rival identity
    /// changes. `sceneState` outlives the RealityView remake boundary, so a
    /// nil-check alone would leave session A's context articulating session B.
    private func refreshGhostPoseAggregates() {
        guard let rival, rival.hasGenuineStrokeData else {
            sceneState.clearGhostPoseAggregates()
            return
        }
        sceneState.updateGhostPoseAggregates(for: rival.id) {
            (
                context: computePoseContext(strokes: rival.strokes),
                medianHR: computeMedianHR(strokes: rival.strokes)
            )
        }
    }

    /// Proper median matching the web `median()` helper: averages the two
    /// middle values for even-length arrays.
    private func computePoseContext(strokes: [Stroke]) -> ReplayStrokePoseContext {
        let watts = strokes.map(\.watts)
        let peakWatts = watts.max() ?? 0
        let wattsAsDoubles = watts.map { Double($0) }
        let medianWatts = Int(exactly: properMedian(wattsAsDoubles, fallback: 0).rounded()) ?? 0
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
        return Int(exactly: properMedian(hrs, fallback: 0).rounded()) ?? 0
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
        let progress = ReplayTelemetryFormatting.roundedInteger(
            state.currentFrame.progress * 100,
            fallback: "0"
        )
        let pace = RowPlayFormatting.pace(state.currentFrame.pace)
        let cadence = ReplayTelemetryFormatting.roundedInteger(state.currentFrame.cadence)
        let unit = sport.cadenceUnit
        let ghost = rival != nil ? "ghost present" : "no ghost"
        return "\(sportName), \(cameraPreset.displayName) camera, \(progress)%, \(pace), \(cadence) \(unit), \(ghost)"
    }

}

/// Identity for the RealityKit graph only. Replay, camera, orbit, and adaptive
/// performance owners intentionally live outside the view keyed by this value.
struct Replay3DQualityGraphIdentity: Hashable {
    let effectiveQuality: ReplayRenderQuality
    let sceneIdentity: Replay3DSceneIdentity
}

/// Production identity boundary that limits quality and rival changes to the
/// RealityKit graph. The caller retains replay, camera, orbit, and adaptive
/// performance state outside it.
struct Replay3DQualityRebuildBoundary<Content: View>: View {
    let effectiveQuality: ReplayRenderQuality
    let sceneIdentity: Replay3DSceneIdentity
    private let content: Content

    init(
        effectiveQuality: ReplayRenderQuality,
        sceneIdentity: Replay3DSceneIdentity,
        @ViewBuilder content: () -> Content
    ) {
        self.effectiveQuality = effectiveQuality
        self.sceneIdentity = sceneIdentity
        self.content = content()
    }

    var body: some View {
        content.id(Replay3DQualityGraphIdentity(
            effectiveQuality: effectiveQuality,
            sceneIdentity: sceneIdentity
        ))
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
    /// Rival identity that produced `ghostPoseContext` / `ghostMedianHR`.
    /// Prevents session A aggregates from articulating session B after a rebuild.
    var ghostPoseRivalID: String?

    /// Installs aggregates for a new genuine rival. The closure is deliberately
    /// lazy because computing medians is O(N log N), and the same rival can
    /// revisit the RealityView make path after a quality-only rebuild.
    @discardableResult
    func updateGhostPoseAggregates(
        for rivalID: String,
        makeAggregates: () -> (context: ReplayStrokePoseContext, medianHR: Int)
    ) -> Replay3DGhostAggregateUpdate {
        guard ghostPoseRivalID != rivalID else { return .unchanged }
        let aggregates = makeAggregates()
        ghostPoseContext = aggregates.context
        ghostMedianHR = aggregates.medianHR
        ghostPoseRivalID = rivalID
        return .recomputed
    }

    /// Clears genuine-stroke aggregates when the rival is removed or switches
    /// to constant-pace/imported fallback articulation.
    @discardableResult
    func clearGhostPoseAggregates() -> Replay3DGhostAggregateUpdate {
        guard ghostPoseRivalID != nil || ghostPoseContext != nil || ghostMedianHR != 0 else {
            return .unchanged
        }
        ghostPoseContext = nil
        ghostMedianHR = 0
        ghostPoseRivalID = nil
        return .cleared
    }
}

/// Selects the production 3D articulation path for a rival. Session rivals
/// with precomputed genuine-stroke context use data-driven poses; synthetic or
/// imported traces deliberately use the deterministic fallback animation.
enum Replay3DGhostArticulation: Equatable {
    case genuine(ReplayStrokePoseContext)
    case fallback

    static func select(
        rival: ReplayRival,
        poseContext: ReplayStrokePoseContext?
    ) -> Replay3DGhostArticulation {
        guard rival.hasGenuineStrokeData, let poseContext else { return .fallback }
        return .genuine(poseContext)
    }
}

enum Replay3DGhostAggregateUpdate: Equatable {
    case unchanged
    case recomputed
    case cleared
}
