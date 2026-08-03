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

    func testBundledThemeRivalReducedMotionMatrixIsDeterministic() async throws {
        var cases = 0
        var bundledCases = 0
        for sport in Sport.allCases {
            let loadedAssetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            let assetSet = try XCTUnwrap(loadedAssetSet)
            for quality in ReplayRenderQuality.allCases {
                for colorScheme in [ColorScheme.light, .dark] {
                    for rendersGhost in [false, true] {
                        let scene = Replay3DSceneBuilder.buildScene(
                            sport: sport,
                            colorScheme: colorScheme,
                            configuration: quality.configuration,
                            effectiveQuality: quality,
                            bundledAssetSet: assetSet
                        )
                        let expectedVisualSource: ReplayAssetVisualSource =
                            ReplayAssetCatalog.bundledVisualsAreEligible(at: quality)
                                ? .bundled
                                : .procedural
                        XCTAssertEqual(scene.visualSource, expectedVisualSource)
                        if expectedVisualSource == .bundled {
                            bundledCases += 1
                        }
                        XCTAssertNotNil(scene.bundledEnvironment)
                        XCTAssertFalse(scene.liveGroup === scene.ghostGroup)

                        let controller = ReplayCameraController()
                        let liveDistance = 246.5
                        let ghostDistance = 211.0
                        let viewportAspect = colorScheme == .light ? 0.65 : 2.4
                        let live = ReplayStrokePose.fallback(
                            sport: sport,
                            phase: 2.3,
                            rate: 30
                        )
                        let rival = rendersGhost
                            ? ReplayStrokePose.fallback(sport: sport, phase: 1.4, rate: 29)
                            : nil

                        func seek(generation: Int) {
                            XCTAssertTrue(Replay3DSceneBuilder.updateScene(
                                container: scene,
                                livePose: live,
                                liveDistance: liveDistance,
                                sport: sport,
                                ghostPose: rival,
                                ghostDistance: ghostDistance,
                                ghostVisible: rendersGhost,
                                reduceMotion: true,
                                viewportAspect: viewportAspect,
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
                        let firstFieldOfView = scene.camera.camera.fieldOfViewInDegrees
                        seek(generation: 2)
                        XCTAssertEqual(scene.liveGroup.transform.matrix, firstLive)
                        XCTAssertEqual(scene.ghostGroup.transform.matrix, firstRival)
                        XCTAssertEqual(scene.camera.transform.matrix, firstCamera)
                        XCTAssertEqual(
                            scene.camera.camera.fieldOfViewInDegrees,
                            firstFieldOfView
                        )
                        XCTAssertEqual(scene.ghostGroup.isEnabled, rendersGhost)
                        XCTAssertEqual(scene.liveGroup.position.y, 0)

                        let participant = scene.layout.position(at: liveDistance)
                        let tangent = scene.layout.tangent(at: liveDistance)
                        let expectedSolo = ReplayCameraSolver.targetPose(
                            preset: .chase,
                            sport: sport,
                            participant: participant,
                            tangent: tangent,
                            speed: 0,
                            aspect: viewportAspect,
                            reduceMotion: true
                        )
                        let expected = ReplayCameraSolver.targetPose(
                            preset: .chase,
                            sport: sport,
                            participant: participant,
                            tangent: tangent,
                            speed: 0,
                            rival: rendersGhost
                                ? scene.layout.ghostPosition(at: ghostDistance)
                                : nil,
                            aspect: viewportAspect,
                            reduceMotion: true
                        )
                        let resolved = try XCTUnwrap(controller.resolvedPose)
                        XCTAssertEqual(resolved, expected)
                        XCTAssertEqual(
                            resolved.fieldOfViewDegrees,
                            ReplayCameraChaseRig.rig(for: sport).baseFieldOfView
                        )
                        if rendersGhost {
                            XCTAssertGreaterThan(
                                cameraDistance(resolved),
                                cameraDistance(expectedSolo)
                            )
                        } else {
                            XCTAssertEqual(resolved, expectedSolo)
                        }
                        cases += 1
                    }
                }
            }
        }
        XCTAssertEqual(cases, 48)
        XCTAssertEqual(bundledCases, 24)
    }

    private func cameraDistance(_ pose: ReplayCameraPose) -> Double {
        hypot(pose.positionX - pose.targetX, pose.positionZ - pose.targetZ)
    }
}
