import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class Phase11SceneAcceptanceTests: XCTestCase {
    func testThreeSportQualityCameraRivalMatrixBuildsAndUpdates() {
        var cases = 0
        for sport in Sport.allCases {
            for quality in ReplayRenderQuality.allCases {
                let scene = Replay3DSceneBuilder.buildScene(
                    sport: sport,
                    colorScheme: .dark,
                    configuration: quality.configuration,
                    effectiveQuality: quality,
                    bundledAssetSet: nil
                )
                XCTAssertNotNil(scene.bundledEnvironment)
                XCTAssertFalse(scene.groundEntity.isEnabled)
                XCTAssertFalse(scene.liveGroup === scene.ghostGroup)

                let controller = ReplayCameraController()
                for (presetIndex, preset) in ReplayCameraPreset.allCases.enumerated() {
                    let phase = Double(presetIndex) * 0.7
                    let live = ReplayStrokePose.fallback(sport: sport, phase: phase, rate: 28)
                    let rival = ReplayStrokePose.fallback(sport: sport, phase: phase + 0.35, rate: 27)
                    XCTAssertTrue(Replay3DSceneBuilder.updateScene(
                        container: scene,
                        livePose: live,
                        liveDistance: 120 + Double(presetIndex) * 10,
                        sport: sport,
                        ghostPose: rival,
                        ghostDistance: 116 + Double(presetIndex) * 10,
                        ghostVisible: true,
                        reduceMotion: false,
                        deltaTime: 1.0 / 60.0,
                        playbackTickGeneration: UInt64(presetIndex + 1),
                        isPlaying: true,
                        cameraController: controller,
                        cameraPreset: preset,
                        cameraResetGeneration: 0,
                        replayDiscontinuityGeneration: 0
                    ))
                    XCTAssertTrue(scene.ghostGroup.isEnabled)
                    XCTAssertTrue(scene.camera.transform.matrix.columns.3.x.isFinite)
                    cases += 1
                }
            }
        }
        XCTAssertEqual(cases, 48)
    }

    func testExactSeekAndReducedMotionRemainDeterministicWithRival() {
        for sport in Sport.allCases {
            let scene = Replay3DSceneBuilder.buildScene(
                sport: sport,
                colorScheme: .light,
                configuration: ReplayRenderQuality.high.configuration,
                effectiveQuality: .high,
                bundledAssetSet: nil
            )
            let controller = ReplayCameraController()
            let live = ReplayStrokePose.fallback(sport: sport, phase: 2.3, rate: 30)
            let rival = ReplayStrokePose.fallback(sport: sport, phase: 1.4, rate: 29)

            func seek(generation: Int) {
                XCTAssertTrue(Replay3DSceneBuilder.updateScene(
                    container: scene,
                    livePose: live,
                    liveDistance: 246.5,
                    sport: sport,
                    ghostPose: rival,
                    ghostDistance: 241.0,
                    ghostVisible: true,
                    reduceMotion: true,
                    deltaTime: 0,
                    playbackTickGeneration: UInt64(generation),
                    isPlaying: false,
                    cameraController: controller,
                    cameraPreset: .chase,
                    cameraResetGeneration: 0,
                    replayDiscontinuityGeneration: generation
                ))
            }

            seek(generation: 1)
            let firstLive = scene.liveGroup.transform.matrix
            let firstRival = scene.ghostGroup.transform.matrix
            let firstCamera = scene.camera.transform.matrix
            seek(generation: 2)
            XCTAssertEqual(scene.liveGroup.transform.matrix, firstLive)
            XCTAssertEqual(scene.ghostGroup.transform.matrix, firstRival)
            XCTAssertEqual(scene.camera.transform.matrix, firstCamera)
            XCTAssertEqual(scene.liveGroup.position.y, 0)
        }
    }
}
