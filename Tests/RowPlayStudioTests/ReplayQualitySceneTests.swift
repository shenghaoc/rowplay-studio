import AppKit
import Observation
import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayQualitySceneTests: XCTestCase {
    func testSceneCourseEntityCountsMatchEveryQualityTier() {
        for quality in ReplayRenderQuality.allCases {
            let configuration = quality.configuration
            let container = Replay3DSceneBuilder.buildScene(
                sport: .rower,
                colorScheme: .dark,
                configuration: configuration
            )

            XCTAssertEqual(
                countEntities(namedPrefix: "lane-ring-segment-", in: container.course),
                configuration.courseRingSegmentCount,
                "Unexpected course-ring budget for \(quality.rawValue)"
            )
            XCTAssertEqual(
                countEntities(namedPrefix: "lane-marker-", in: container.course),
                configuration.laneMarkerCount,
                "Unexpected lane-marker budget for \(quality.rawValue)"
            )
            XCTAssertEqual(
                countEntities(namedPrefix: "distance-marker-", in: container.course),
                8
            )
            XCTAssertEqual(
                countEntities(namedPrefix: "start-finish-marker", in: container.course),
                1
            )
        }
    }

    func testEffectEntityCountsMatchEveryQualityTier() {
        for quality in ReplayRenderQuality.allCases {
            let configuration = quality.configuration
            let renderer = ReplayEffectRenderer(
                sport: .rower,
                configuration: configuration,
                parent: Entity()
            )

            XCTAssertEqual(
                renderer.liveWakeEntities.count,
                configuration.wakeEntryCapacityPerParticipant
            )
            XCTAssertEqual(
                renderer.ghostWakeEntities.count,
                configuration.wakeEntryCapacityPerParticipant
            )
            XCTAssertEqual(renderer.sprayEntities.count, configuration.sprayParticleCapacity)
            XCTAssertEqual(
                renderer.fixedEntityCount,
                configuration.wakeEntryCapacityPerParticipant * 2
                    + configuration.sprayParticleCapacity
            )
        }
    }

    func testLowQualityCreatesNoEffectEntities() {
        let renderer = ReplayEffectRenderer(
            sport: .rower,
            configuration: ReplayRenderQuality.low.configuration,
            parent: Entity()
        )

        XCTAssertTrue(renderer.liveWakeEntities.isEmpty)
        XCTAssertTrue(renderer.ghostWakeEntities.isEmpty)
        XCTAssertTrue(renderer.sprayEntities.isEmpty)
        XCTAssertEqual(renderer.fixedEntityCount, 0)
    }

    func testBikeErgKeepsEffectsInactiveAtEveryQualityTier() {
        for quality in ReplayRenderQuality.allCases {
            let renderer = ReplayEffectRenderer(
                sport: .bike,
                configuration: quality.configuration,
                parent: Entity()
            )

            update(
                renderer,
                liveDistance: 0,
                ghostDistance: 0,
                phase: 5.9,
                generation: 1
            )
            update(
                renderer,
                liveDistance: 8,
                ghostDistance: 7,
                phase: 6.4,
                generation: 2
            )

            XCTAssertEqual(renderer.liveWakeCount, 0)
            XCTAssertEqual(renderer.ghostWakeCount, 0)
            XCTAssertEqual(renderer.sprayCount, 0)
            XCTAssertTrue(allEffectEntities(renderer).allSatisfy { !$0.isEnabled })
        }
    }

    func testShrinkingActiveSprayDisablesOnlyNewlyInactiveTailOnce() {
        let renderer = ReplayEffectRenderer(
            sport: .rower,
            configuration: ReplayRenderQuality.medium.configuration,
            parent: Entity()
        )
        update(
            renderer,
            liveDistance: 0,
            ghostDistance: 0,
            phase: 5.9,
            generation: 1
        )
        update(
            renderer,
            liveDistance: 5,
            ghostDistance: 4,
            phase: 6.4,
            generation: 2
        )
        XCTAssertTrue(allEffectEntities(renderer).contains(where: \.isEnabled))
        let activeSprayCount = renderer.sprayCount
        let writesBeforeExpiry = renderer.inactiveEntityDisableWriteCount
        XCTAssertGreaterThan(activeSprayCount, 0)

        update(
            renderer,
            liveDistance: 6,
            ghostDistance: 5,
            phase: 6.5,
            generation: 3,
            deltaTime: 1
        )
        XCTAssertEqual(renderer.sprayCount, 0)
        XCTAssertEqual(
            renderer.inactiveEntityDisableWriteCount - writesBeforeExpiry,
            activeSprayCount
        )
        let writesAfterExpiry = renderer.inactiveEntityDisableWriteCount

        update(
            renderer,
            liveDistance: 7,
            ghostDistance: 6,
            phase: 6.6,
            generation: 4
        )
        XCTAssertEqual(renderer.inactiveEntityDisableWriteCount, writesAfterExpiry)
    }

    func testControllerDegradesExactlyOneTierForOneGovernorStep() {
        let controller = ReplayPerformanceController(selectedQuality: .ultra)
        controller.resetForNewScene(selectedQuality: .ultra)
        var generation: UInt64 = 0

        for _ in 0..<30 {
            generation &+= 1
            recordControllerSample(
                controller,
                intervalMilliseconds: 16,
                generation: generation
            )
        }
        while controller.effectiveQuality == .ultra, generation < 200 {
            generation &+= 1
            recordControllerSample(
                controller,
                intervalMilliseconds: 100,
                generation: generation
            )
        }

        XCTAssertEqual(controller.governorLevel, 1)
        XCTAssertEqual(controller.effectiveQuality, .high)

        for _ in 0..<90 {
            generation &+= 1
            recordControllerSample(
                controller,
                intervalMilliseconds: 100,
                generation: generation
            )
        }
        XCTAssertEqual(controller.governorLevel, 1)
        XCTAssertEqual(controller.effectiveQuality, .high)
    }

    func testControllerRejectsDuplicateRealityViewUpdatesForOneGeneration() {
        let controller = ReplayPerformanceController(selectedQuality: .medium)
        controller.resetForNewScene(selectedQuality: .medium)

        controller.recordFrameInterval(
            milliseconds: 16,
            playbackTickGeneration: 1
        )
        controller.recordFrameInterval(
            milliseconds: 20,
            playbackTickGeneration: 1
        )
        XCTAssertTrue(controller.shouldMeasureSceneUpdate(playbackTickGeneration: 1))
        controller.recordSceneUpdateDuration(
            milliseconds: 2,
            playbackTickGeneration: 1
        )
        controller.recordSceneUpdateDuration(
            milliseconds: 5,
            playbackTickGeneration: 1
        )

        XCTAssertEqual(controller.acceptedFrameIntervalCount, 1)
        XCTAssertEqual(controller.recordedSceneUpdateCount, 1)
        XCTAssertFalse(controller.shouldMeasureSceneUpdate(playbackTickGeneration: 1))
    }

    func testControllerEmitsOneBoundedMetricsWindow() throws {
        let controller = ReplayPerformanceController(selectedQuality: .low)
        controller.resetForNewScene(selectedQuality: .low)

        for generation in 1...ReplayPerformanceMetrics.defaultWindowSize {
            recordControllerSample(
                controller,
                intervalMilliseconds: 16,
                generation: UInt64(generation)
            )
        }

        XCTAssertEqual(controller.completedMetricsWindowCount, 1)
        let snapshot = try XCTUnwrap(controller.lastMetricsSnapshot)
        XCTAssertEqual(snapshot.sampleCount, ReplayPerformanceMetrics.defaultWindowSize)
        XCTAssertEqual(snapshot.averageFrameIntervalMilliseconds, 16, accuracy: 0.0001)
        XCTAssertEqual(snapshot.averageSceneUpdateDurationMilliseconds, 2, accuracy: 0.0001)
    }

    func testAdaptiveDegradationStartsFreshMetricsWindowForNewTier() {
        let controller = ReplayPerformanceController(selectedQuality: .ultra)
        controller.resetForNewScene(selectedQuality: .ultra)
        var generation: UInt64 = 0

        for _ in 0..<30 {
            generation &+= 1
            recordControllerSample(
                controller,
                intervalMilliseconds: 16,
                generation: generation
            )
        }
        XCTAssertEqual(controller.metricsSampleCount, 30)

        while controller.effectiveQuality == .ultra, generation < 200 {
            generation &+= 1
            recordControllerSample(
                controller,
                intervalMilliseconds: 100,
                generation: generation
            )
        }

        XCTAssertEqual(controller.effectiveQuality, .high)
        XCTAssertEqual(controller.metricsSampleCount, 0)
        XCTAssertFalse(
            controller.shouldMeasureSceneUpdate(playbackTickGeneration: generation)
        )
        XCTAssertNil(controller.lastMetricsSnapshot)
    }

    func testManualSelectionResetsGovernorMetricsAndStartsAtSelectedTier() {
        let controller = ReplayPerformanceController(selectedQuality: .ultra)
        controller.resetForNewScene(selectedQuality: .ultra)
        var generation: UInt64 = 0
        for _ in 0..<30 {
            generation &+= 1
            recordControllerSample(controller, intervalMilliseconds: 16, generation: generation)
        }
        while controller.effectiveQuality == .ultra, generation < 200 {
            generation &+= 1
            recordControllerSample(controller, intervalMilliseconds: 100, generation: generation)
        }
        XCTAssertEqual(controller.effectiveQuality, .high)

        controller.selectQuality(.medium)

        XCTAssertEqual(controller.selectedQuality, .medium)
        XCTAssertEqual(controller.effectiveQuality, .medium)
        XCTAssertEqual(controller.governorLevel, 0)
        XCTAssertEqual(controller.activeBudgetMilliseconds, 22)
        XCTAssertEqual(controller.metricsSampleCount, 0)
        XCTAssertEqual(controller.acceptedFrameIntervalCount, 0)
        XCTAssertEqual(controller.recordedSceneUpdateCount, 0)
        XCTAssertEqual(controller.completedMetricsWindowCount, 0)
        XCTAssertNil(controller.lastMetricsSnapshot)

        generation = 0
        for _ in 0..<30 {
            generation &+= 1
            recordControllerSample(controller, intervalMilliseconds: 16, generation: generation)
        }
        while controller.effectiveQuality == .medium, generation < 200 {
            generation &+= 1
            recordControllerSample(controller, intervalMilliseconds: 100, generation: generation)
        }
        XCTAssertEqual(controller.governorLevel, 1)
        XCTAssertEqual(controller.effectiveQuality, .low)
    }

    func testMismatchedSceneGenerationDoesNotConsumePendingSample() {
        let controller = ReplayPerformanceController(selectedQuality: .medium)
        controller.recordFrameInterval(milliseconds: 16, playbackTickGeneration: 4)

        controller.recordSceneUpdateDuration(
            milliseconds: 2,
            playbackTickGeneration: 5
        )
        XCTAssertEqual(controller.recordedSceneUpdateCount, 0)
        XCTAssertTrue(controller.shouldMeasureSceneUpdate(playbackTickGeneration: 4))

        controller.recordSceneUpdateDuration(
            milliseconds: 2,
            playbackTickGeneration: 4
        )
        XCTAssertEqual(controller.recordedSceneUpdateCount, 1)
    }

    func testSamplingPolicyExcludesFirstPausedAndTwoDimensionalTicks() {
        let controller = ReplayPerformanceController(selectedQuality: .medium)
        let excluded: [(TimeInterval?, Bool, ReplayRendererMode)] = [
            (nil, true, .threeD),
            (0.016, false, .threeD),
            (0.016, true, .twoD),
        ]
        var generation: UInt64 = 0
        for (rawDelta, isPlaying, mode) in excluded {
            generation &+= 1
            if let milliseconds = ReplayPerformanceSampling.frameIntervalMilliseconds(
                rawDelta: rawDelta,
                isPlaying: isPlaying,
                rendererMode: mode
            ) {
                controller.recordFrameInterval(
                    milliseconds: milliseconds,
                    playbackTickGeneration: generation
                )
            }
        }
        XCTAssertEqual(controller.acceptedFrameIntervalCount, 0)

        generation &+= 1
        let milliseconds = ReplayPerformanceSampling.frameIntervalMilliseconds(
            rawDelta: 0.016,
            isPlaying: true,
            rendererMode: .threeD
        )
        controller.recordFrameInterval(
            milliseconds: milliseconds ?? 0,
            playbackTickGeneration: generation
        )
        controller.recordSceneUpdateDuration(
            milliseconds: 2,
            playbackTickGeneration: generation
        )
        XCTAssertEqual(controller.acceptedFrameIntervalCount, 1)
        XCTAssertEqual(controller.recordedSceneUpdateCount, 1)
    }

    func testQualityTransitionRebuildPreservesPlaybackCameraAndOrbitState() {
        let strokes = [
            Stroke(t: 0, d: 0, pace: 120, cadence: 28, watts: 160),
            Stroke(t: 10, d: 100, pace: 118, cadence: 29, watts: 175),
        ]
        let state = ReplayState(strokes: strokes)
        state.seek(to: 4)
        state.setSpeed(.two)
        state.play()
        let identity = ObjectIdentifier(state)
        let time = state.time
        let speed = state.speed
        let playing = state.playing
        let cameraController = ReplayCameraController()
        cameraController.updateOrbitDrag(translationX: 40, translationY: -12)
        cameraController.endOrbitDrag()
        let orbit = cameraController.orbit
        let cameraPreset = ReplayCameraPreset.orbit
        let performanceController = ReplayPerformanceController(selectedQuality: .ultra)
        let outerIdentityBefore = Replay3DSceneIdentity(
            workoutID: 1,
            ghostWorkoutID: 2,
            sportRawValue: Sport.rower.rawValue
        )
        let graphIdentityBefore = Replay3DQualityGraphIdentity(effectiveQuality: .ultra)

        let originalContainer = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark,
            configuration: ReplayRenderQuality.ultra.configuration
        )
        update(
            originalContainer.effectRenderer,
            liveDistance: 0,
            ghostDistance: 0,
            phase: 5.9,
            generation: 1
        )
        update(
            originalContainer.effectRenderer,
            liveDistance: 5,
            ghostDistance: 4,
            phase: 6.4,
            generation: 2
        )
        XCTAssertGreaterThan(originalContainer.effectRenderer.sprayCount, 0)

        performanceController.selectQuality(.low)
        let outerIdentityAfter = Replay3DSceneIdentity(
            workoutID: 1,
            ghostWorkoutID: 2,
            sportRawValue: Sport.rower.rawValue
        )
        let graphIdentityAfter = Replay3DQualityGraphIdentity(
            effectiveQuality: performanceController.effectiveQuality
        )
        let rebuiltContainer = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark,
            configuration: performanceController.effectiveQuality.configuration
        )
        cameraController.resetSceneState()

        XCTAssertEqual(ObjectIdentifier(state), identity)
        XCTAssertEqual(state.time, time)
        XCTAssertEqual(state.speed, speed)
        XCTAssertEqual(state.playing, playing)
        XCTAssertEqual(cameraPreset, .orbit)
        XCTAssertEqual(cameraController.orbit, orbit)
        XCTAssertEqual(outerIdentityAfter, outerIdentityBefore)
        XCTAssertNotEqual(graphIdentityAfter, graphIdentityBefore)
        XCTAssertEqual(performanceController.effectiveQuality, .low)
        XCTAssertEqual(rebuiltContainer.effectRenderer.fixedEntityCount, 0)
        XCTAssertEqual(rebuiltContainer.effectRenderer.liveWakeCount, 0)
        XCTAssertEqual(rebuiltContainer.effectRenderer.ghostWakeCount, 0)
        XCTAssertEqual(rebuiltContainer.effectRenderer.sprayCount, 0)
    }

    func testQualityControlAccessibilityVisibilityLabelsAndHelpAreStable() {
        XCTAssertTrue(ReplayView.showsQualityControl(rendererMode: .threeD))
        XCTAssertFalse(ReplayView.showsQualityControl(rendererMode: .twoD))
        XCTAssertEqual(ReplayView.qualityAccessibilityLabel, "3D replay quality")
        XCTAssertEqual(
            ReplayView.qualityPickerHelp,
            "Choose the maximum 3D replay quality"
        )
        XCTAssertEqual(
            ReplayView.qualityAccessibilityValue(selected: .ultra, effective: .medium),
            "Selected Ultra, effective Medium"
        )
        XCTAssertEqual(
            ReplayView.adaptiveQualityAccessibilityLabel(effective: .medium),
            "3D replay quality reduced to Medium"
        )
        XCTAssertEqual(
            ReplayView.adaptiveQualityHelp,
            "Quality was reduced to maintain replay performance"
        )
    }

    func testQualityStatusStartsAtPersistedCeilingAndOnlyReportsLowerTiers() {
        for selected in ReplayRenderQuality.allCases {
            let displayed = ReplayView.effectiveQualityForDisplay(
                selected: selected,
                reportedEffective: nil
            )
            XCTAssertEqual(displayed, selected)
            XCTAssertFalse(ReplayView.isAdaptiveReduction(
                selected: selected,
                effective: displayed
            ))
        }

        XCTAssertTrue(ReplayView.isAdaptiveReduction(selected: .ultra, effective: .high))
        XCTAssertTrue(ReplayView.isAdaptiveReduction(selected: .medium, effective: .low))
        XCTAssertFalse(ReplayView.isAdaptiveReduction(selected: .low, effective: .medium))
        XCTAssertFalse(ReplayView.isAdaptiveReduction(selected: .high, effective: .ultra))
    }

    func testProductionQualityBoundaryRebuildsOnlyInnerGraph() async {
        let strokes = [
            Stroke(t: 0, d: 0, pace: 120, cadence: 28, watts: 160),
            Stroke(t: 10, d: 100, pace: 118, cadence: 29, watts: 175),
        ]
        let replayState = ReplayState(strokes: strokes)
        replayState.seek(to: 4)
        replayState.setSpeed(.two)
        replayState.play()
        let model = ReplayQualityBoundaryHarnessModel(replayState: replayState)
        model.cameraController.updateOrbitDrag(translationX: 40, translationY: -12)
        model.cameraController.endOrbitDrag()
        let host = NSHostingView(rootView: ReplayQualityBoundaryHarness(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        host.layoutSubtreeIfNeeded()
        await drainSwiftUIUpdates(for: host)

        let replayIdentity = ObjectIdentifier(replayState)
        let time = replayState.time
        let speed = replayState.speed
        let playing = replayState.playing
        let orbit = model.cameraController.orbit
        XCTAssertEqual(model.graphAppearances.count, 1)

        model.effectiveQuality = .low
        await drainSwiftUIUpdates(for: host)

        XCTAssertEqual(model.graphAppearances.count, 2)
        XCTAssertNotEqual(model.graphAppearances[0], model.graphAppearances[1])
        XCTAssertEqual(ObjectIdentifier(model.replayState), replayIdentity)
        XCTAssertEqual(model.replayState.time, time)
        XCTAssertEqual(model.replayState.speed, speed)
        XCTAssertEqual(model.replayState.playing, playing)
        XCTAssertEqual(model.cameraPreset, .orbit)
        XCTAssertEqual(model.cameraController.orbit, orbit)
        model.replayState.pause()
    }

    private func recordControllerSample(
        _ controller: ReplayPerformanceController,
        intervalMilliseconds: Double,
        generation: UInt64
    ) {
        controller.recordFrameInterval(
            milliseconds: intervalMilliseconds,
            playbackTickGeneration: generation
        )
        controller.recordSceneUpdateDuration(
            milliseconds: 2,
            playbackTickGeneration: generation
        )
    }

    private func update(
        _ renderer: ReplayEffectRenderer,
        liveDistance: Double,
        ghostDistance: Double,
        phase: Double,
        generation: UInt64,
        deltaTime: TimeInterval = 1.0 / 60.0,
        reduceMotion: Bool = false
    ) {
        renderer.update(
            layout: .standard,
            liveDistance: liveDistance,
            livePhase: phase,
            liveCatchOrdinal: Int(generation),
            ghostDistance: ghostDistance,
            ghostVisible: true,
            deltaTime: deltaTime,
            playbackTickGeneration: generation,
            isPlaying: true,
            reduceMotion: reduceMotion,
            resetGeneration: 0
        )
    }

    private func countEntities(namedPrefix prefix: String, in entity: Entity) -> Int {
        let ownCount = entity.name.hasPrefix(prefix) ? 1 : 0
        return ownCount + entity.children.reduce(0) {
            $0 + countEntities(namedPrefix: prefix, in: $1)
        }
    }

    private func allEffectEntities(_ renderer: ReplayEffectRenderer) -> [ModelEntity] {
        renderer.liveWakeEntities + renderer.ghostWakeEntities + renderer.sprayEntities
    }

    private func drainSwiftUIUpdates(
        for host: NSHostingView<ReplayQualityBoundaryHarness>
    ) async {
        for _ in 0..<24 {
            await Task.yield()
            host.layoutSubtreeIfNeeded()
        }
    }

}

@MainActor
@Observable
private final class ReplayQualityBoundaryHarnessModel {
    let replayState: ReplayState
    let cameraController = ReplayCameraController()
    let cameraPreset = ReplayCameraPreset.orbit
    var effectiveQuality = ReplayRenderQuality.ultra
    var graphAppearances: [UUID] = []

    init(replayState: ReplayState) {
        self.replayState = replayState
    }

    func recordGraphAppearance(_ identity: UUID) {
        guard graphAppearances.last != identity else { return }
        graphAppearances.append(identity)
    }
}

@MainActor
private struct ReplayQualityBoundaryHarness: View {
    let model: ReplayQualityBoundaryHarnessModel

    var body: some View {
        Replay3DQualityRebuildBoundary(effectiveQuality: model.effectiveQuality) {
            ReplayQualityGraphProbe(model: model)
        }
    }
}

@MainActor
private struct ReplayQualityGraphProbe: View {
    let model: ReplayQualityBoundaryHarnessModel
    @State private var identity = UUID()

    var body: some View {
        Color.clear
            .onAppear {
                model.recordGraphAppearance(identity)
            }
    }
}
