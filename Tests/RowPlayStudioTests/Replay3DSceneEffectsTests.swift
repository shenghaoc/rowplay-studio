import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class Replay3DSceneEffectsTests: XCTestCase {
    private var tickGeneration: UInt64 = 0

    func testEffectRendererPrebuildsFixedEntityBudgetForEverySport() {
        for sport: Sport in [.rower, .skierg, .bike] {
            let parent = Entity()
            let renderer = ReplayEffectRenderer(sport: sport, parent: parent)

            XCTAssertEqual(renderer.liveWakeEntities.count, 24)
            XCTAssertEqual(renderer.ghostWakeEntities.count, 24)
            XCTAssertEqual(renderer.sprayEntities.count, 48)
            XCTAssertEqual(renderer.fixedEntityCount, 96)
            XCTAssertEqual(renderer.root.children.count, 96)
        }
    }

    func testRepeatedSceneUpdatesDoNotIncreaseEntityCount() {
        let container = Replay3DSceneBuilder.buildScene(
            sport: .rower,
            colorScheme: .dark
        )
        let controller = ReplayCameraController()
        let initialCount = recursiveEntityCount(container.root)

        for frame in 0..<120 {
            let distance = Double(frame) * 0.75
            let phase = Double(frame) * 0.45
            let pose = ReplayStrokePose.fallback(sport: .rower, phase: phase, rate: 28)
            Replay3DSceneBuilder.updateScene(
                container: container,
                livePose: pose,
                liveDistance: distance,
                sport: .rower,
                ghostPose: pose,
                ghostDistance: distance * 0.9,
                ghostVisible: true,
                reduceMotion: false,
                deltaTime: 1.0 / 60.0,
                playbackTickGeneration: UInt64(frame + 1),
                isPlaying: true,
                cameraController: controller,
                cameraPreset: .chase,
                cameraResetGeneration: 0,
                replayDiscontinuityGeneration: 0
            )
        }

        XCTAssertEqual(recursiveEntityCount(container.root), initialCount)
        XCTAssertLessThanOrEqual(container.effectRenderer.sprayCount, 48)
    }

    func testLiveAndGhostWakeHistoriesAdvanceIndependently() {
        let renderer = ReplayEffectRenderer(sport: .skierg, parent: Entity())

        update(renderer, liveDistance: 0, ghostDistance: 0, ghostVisible: true)
        update(renderer, liveDistance: 5, ghostDistance: 0, ghostVisible: true)

        XCTAssertEqual(renderer.liveWakeCount, 1)
        XCTAssertEqual(renderer.ghostWakeCount, 0)

        update(renderer, liveDistance: 5, ghostDistance: 4, ghostVisible: true)

        XCTAssertEqual(renderer.liveWakeCount, 1)
        XCTAssertEqual(renderer.ghostWakeCount, 1)
    }

    func testBikeErgKeepsEveryEffectDisabled() {
        let renderer = ReplayEffectRenderer(sport: .bike, parent: Entity())

        update(renderer, liveDistance: 0, ghostDistance: 0, ghostVisible: true, phase: 5.9)
        update(renderer, liveDistance: 8, ghostDistance: 7, ghostVisible: true, phase: 6.4)

        XCTAssertEqual(renderer.liveWakeCount, 0)
        XCTAssertEqual(renderer.ghostWakeCount, 0)
        XCTAssertEqual(renderer.sprayCount, 0)
        XCTAssertTrue(allEffectEntities(renderer).allSatisfy { !$0.isEnabled })
    }

    func testReducedMotionClearsWakeAndSpray() {
        let renderer = ReplayEffectRenderer(sport: .rower, parent: Entity())

        update(renderer, liveDistance: 0, ghostDistance: 0, ghostVisible: true, phase: 5.9)
        update(renderer, liveDistance: 5, ghostDistance: 4, ghostVisible: true, phase: 6.4)

        XCTAssertGreaterThan(renderer.liveWakeCount, 0)
        XCTAssertGreaterThan(renderer.ghostWakeCount, 0)
        XCTAssertGreaterThan(renderer.sprayCount, 0)

        update(
            renderer,
            liveDistance: 6,
            ghostDistance: 5,
            ghostVisible: true,
            phase: 6.6,
            reduceMotion: true
        )

        XCTAssertEqual(renderer.liveWakeCount, 0)
        XCTAssertEqual(renderer.ghostWakeCount, 0)
        XCTAssertEqual(renderer.sprayCount, 0)
        XCTAssertTrue(allEffectEntities(renderer).allSatisfy { !$0.isEnabled })
    }

    func testReplayDiscontinuityClearsWithoutSpawningCatch() {
        let renderer = ReplayEffectRenderer(sport: .rower, parent: Entity())

        update(renderer, liveDistance: 0, ghostDistance: 0, ghostVisible: false, phase: 5.9)
        update(renderer, liveDistance: 5, ghostDistance: 0, ghostVisible: false, phase: 6.4)
        XCTAssertGreaterThan(renderer.sprayCount, 0)

        update(
            renderer,
            liveDistance: 12,
            ghostDistance: 0,
            ghostVisible: false,
            phase: 12.7,
            resetGeneration: 1
        )

        XCTAssertEqual(renderer.liveWakeCount, 0)
        XCTAssertEqual(renderer.sprayCount, 0)
    }

    func testGhostOnlyDiscontinuityDoesNotClearLiveEffects() {
        let renderer = ReplayEffectRenderer(sport: .rower, parent: Entity())

        update(renderer, liveDistance: 0, ghostDistance: 0, ghostVisible: true, phase: 5.9)
        update(renderer, liveDistance: 5, ghostDistance: 4, ghostVisible: true, phase: 6.4)
        XCTAssertEqual(renderer.liveWakeCount, 1)
        XCTAssertEqual(renderer.ghostWakeCount, 1)
        XCTAssertGreaterThan(renderer.sprayCount, 0)

        update(renderer, liveDistance: 6, ghostDistance: 40, ghostVisible: true, phase: 6.5)

        XCTAssertEqual(renderer.liveWakeCount, 2)
        XCTAssertEqual(renderer.ghostWakeCount, 0)
        XCTAssertGreaterThan(renderer.sprayCount, 0)
    }

    func testPausedAndDuplicateTickUpdatesDoNotAdvanceParticles() throws {
        let renderer = ReplayEffectRenderer(sport: .rower, parent: Entity())

        update(renderer, liveDistance: 0, ghostDistance: 0, ghostVisible: false, phase: 5.9)
        update(renderer, liveDistance: 5, ghostDistance: 0, ghostVisible: false, phase: 6.4)
        let before = try XCTUnwrap(renderer.sprayParticle(at: 0))

        update(
            renderer,
            liveDistance: 5,
            ghostDistance: 0,
            ghostVisible: false,
            phase: 6.4,
            deltaTime: 0.5,
            isPlaying: true,
            advanceTick: false
        )
        XCTAssertEqual(renderer.sprayParticle(at: 0), before)

        update(
            renderer,
            liveDistance: 5,
            ghostDistance: 0,
            ghostVisible: false,
            phase: 6.4,
            deltaTime: 0.5,
            isPlaying: false,
            advanceTick: false
        )
        XCTAssertEqual(renderer.sprayParticle(at: 0), before)
    }

    func testCatchVariationUsesStableStrokeOrdinal() throws {
        let renderer = ReplayEffectRenderer(sport: .rower, parent: Entity())
        let tau = Double.pi * 2
        let distance = 5.0

        update(
            renderer,
            liveDistance: 0,
            ghostDistance: 0,
            ghostVisible: false,
            phase: 5 * tau - 0.1,
            catchOrdinal: 4
        )
        update(
            renderer,
            liveDistance: distance,
            ghostDistance: 0,
            ghostVisible: false,
            phase: 5 * tau + 0.1,
            catchOrdinal: 5
        )

        var expected = ReplayParticlePool()
        let layout = ReplayCourseLayout.standard
        let position = layout.position(at: distance)
        let tangent = layout.tangent(at: distance)
        _ = ReplaySprayGenerator.spawnCatch(
            into: &expected,
            profile: ReplayEffectProfile.forSport(.rower),
            origin: ReplayEffectPoint(x: position.x, y: 0.05, z: position.z),
            tangent: ReplayEffectPoint(x: tangent.x, y: tangent.y, z: tangent.z),
            radial: ReplayEffectPoint(x: position.x, y: 0, z: position.z),
            catchOrdinal: 5
        )

        XCTAssertEqual(renderer.sprayParticle(at: 0), try XCTUnwrap(expected.particle(at: 0)))
    }

    func testNonFinitePhaseDoesNotSpawnOrCrash() {
        let renderer = ReplayEffectRenderer(sport: .rower, parent: Entity())

        update(renderer, liveDistance: 0, ghostDistance: 0, ghostVisible: false, phase: 5.9)
        update(
            renderer,
            liveDistance: 5,
            ghostDistance: 0,
            ghostVisible: false,
            phase: .infinity,
            catchOrdinal: 1
        )

        XCTAssertEqual(renderer.sprayCount, 0)
    }

    func testWakeIsOffsetBehindAndAlignedWithCourseTangent() {
        let renderer = ReplayEffectRenderer(sport: .rower, parent: Entity())

        update(renderer, liveDistance: 0, ghostDistance: 0, ghostVisible: false)
        update(renderer, liveDistance: 1, ghostDistance: 0, ghostVisible: false)

        let entity = renderer.liveWakeEntities[0]
        let position = ReplayCourseLayout.standard.position(at: 1)
        let tangent = ReplayCourseLayout.standard.tangent(at: 1)
        XCTAssertEqual(entity.position.x, Float(position.x - tangent.x * 1.6), accuracy: 0.0001)
        XCTAssertEqual(entity.position.z, Float(position.z - tangent.z * 1.6), accuracy: 0.0001)
        let forward = entity.orientation.act(SIMD3<Float>(0, 0, 1))
        XCTAssertEqual(forward.x, Float(tangent.x), accuracy: 0.0001)
        XCTAssertEqual(forward.z, Float(tangent.z), accuracy: 0.0001)
        XCTAssertGreaterThan(entity.scale.z, entity.scale.x)
    }

    func testFinalPlaybackTickAdvancesEffectsEvenWhenStateAutoPauses() {
        let renderer = ReplayEffectRenderer(sport: .rower, parent: Entity())

        update(renderer, liveDistance: 0, ghostDistance: 0, ghostVisible: false, phase: 5.9)
        update(
            renderer,
            liveDistance: 5,
            ghostDistance: 0,
            ghostVisible: false,
            phase: 6.4,
            catchOrdinal: 1,
            isPlaying: false
        )

        XCTAssertEqual(renderer.liveWakeCount, 1)
        XCTAssertGreaterThan(renderer.sprayCount, 0)
    }

    func testPausingDoesNotPopChaseFieldOfView() {
        let controller = ReplayCameraController()
        let camera = PerspectiveCamera()
        let layout = ReplayCourseLayout.standard

        controller.update(
            camera: camera,
            layout: layout,
            distance: 0,
            deltaTime: 1.0 / 60.0,
            playbackTickGeneration: 1,
            preset: .chase,
            reduceMotion: false,
            isPlaying: true,
            resetGeneration: 0,
            discontinuityGeneration: 0
        )
        controller.update(
            camera: camera,
            layout: layout,
            distance: 6,
            deltaTime: 1.0 / 60.0,
            playbackTickGeneration: 2,
            preset: .chase,
            reduceMotion: false,
            isPlaying: true,
            resetGeneration: 0,
            discontinuityGeneration: 0
        )
        let fieldOfViewBeforePause = camera.camera.fieldOfViewInDegrees

        controller.update(
            camera: camera,
            layout: layout,
            distance: 6,
            deltaTime: 1.0 / 60.0,
            playbackTickGeneration: 2,
            preset: .chase,
            reduceMotion: false,
            isPlaying: false,
            resetGeneration: 0,
            discontinuityGeneration: 0
        )

        XCTAssertEqual(camera.camera.fieldOfViewInDegrees, fieldOfViewBeforePause, accuracy: 0.0001)
    }

    private func update(
        _ renderer: ReplayEffectRenderer,
        liveDistance: Double,
        ghostDistance: Double,
        ghostVisible: Bool,
        phase: Double = 0,
        catchOrdinal: Int = 0,
        deltaTime: TimeInterval = 1.0 / 60.0,
        isPlaying: Bool = true,
        advanceTick: Bool = true,
        reduceMotion: Bool = false,
        resetGeneration: Int = 0
    ) {
        if advanceTick {
            tickGeneration &+= 1
        }
        renderer.update(
            layout: .standard,
            liveDistance: liveDistance,
            livePhase: phase,
            liveCatchOrdinal: catchOrdinal,
            ghostDistance: ghostDistance,
            ghostVisible: ghostVisible,
            deltaTime: deltaTime,
            playbackTickGeneration: tickGeneration,
            isPlaying: isPlaying,
            reduceMotion: reduceMotion,
            resetGeneration: resetGeneration
        )
    }

    private func allEffectEntities(_ renderer: ReplayEffectRenderer) -> [ModelEntity] {
        renderer.liveWakeEntities + renderer.ghostWakeEntities + renderer.sprayEntities
    }

    private func recursiveEntityCount(_ entity: Entity) -> Int {
        1 + entity.children.reduce(0) { $0 + recursiveEntityCount($1) }
    }
}
