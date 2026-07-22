import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayBundledSportRigTests: XCTestCase {
    override func setUp() async throws {
        ReplayAthleteLibrary.shared.resetCacheForTesting()
        ReplayAssetLibrary.shared.resetCacheForTesting()
    }

    func testV4ClipGateRejectsEveryBundledSportSet() async {
        for sport in ReplayAssetCatalog.supportedSports {
            let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            XCTAssertNil(
                assetSet,
                "The V4 contract/animation mismatch must reject the whole \(sport.rawValue) package"
            )
        }
    }

    func testCanonicalContactGateRejectsDetachedOrNonfiniteSkeletons() {
        let acceptable = ReplayAthleteContactError(
            leftHand: 0.01,
            rightHand: 0.02,
            leftFoot: 0.03,
            rightFoot: 0.04,
            pelvis: 0.05
        )
        XCTAssertTrue(ReplayAthleteContactSolver.isUsable(acceptable))

        let detached = ReplayAthleteContactError(
            leftHand: ReplayAthleteContactSolver.softContactBudgetMeters + 0.001,
            rightHand: 0,
            leftFoot: 0,
            rightFoot: 0,
            pelvis: 0
        )
        XCTAssertFalse(ReplayAthleteContactSolver.isUsable(detached))

        let nonfinite = ReplayAthleteContactError(
            leftHand: .infinity,
            rightHand: 0,
            leftFoot: 0,
            rightFoot: 0,
            pelvis: 0
        )
        XCTAssertFalse(ReplayAthleteContactSolver.isUsable(nonfinite))
    }

    func testSceneBuilderUsesOneCompleteProceduralSceneWhenBundleIsUnavailable() {
        for sport in ReplayAssetCatalog.supportedSports {
            let scene = Replay3DSceneBuilder.buildScene(
                sport: sport,
                colorScheme: .dark,
                configuration: ReplayRenderQuality.ultra.configuration,
                effectiveQuality: .ultra,
                bundledAssetSet: nil
            )

            XCTAssertEqual(scene.visualSource, .procedural)
            XCTAssertNil(scene.bundledEnvironment)
            XCTAssertNotNil(scene.liveRig.root.replayDescendant(named: "pelvis"))
            XCTAssertNotNil(scene.ghostRig.root.replayDescendant(named: "pelvis"))
            XCTAssertNil(scene.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName))
        }
    }

    func testProceduralRigsKeepEquipmentContactsAndFiniteTransforms() {
        let rower = buildProceduralRig(sport: .rower)
        rower.applyPose(.rower(ReplayRowerRigPose(
            joints: ReplayAthleteJointPose(
                torsoLean: 0.21,
                shoulderFlexL: -0.18,
                shoulderFlexR: -0.18,
                kneeFlexL: 0.35,
                kneeFlexR: 0.35
            ),
            seatZ: -0.12,
            handleY: 0.72,
            handleZ: 0.53,
            oarSweep: 0.2,
            oarFeather: -0.06
        )))
        assertContact(named: "hand-L", with: "handle-grip-anchor-L", in: rower)
        assertContact(named: "hand-R", with: "handle-grip-anchor-R", in: rower)
        assertContact(named: "foot-L", with: "foot-anchor-L", in: rower)
        assertContact(named: "foot-R", with: "foot-anchor-R", in: rower)
        XCTAssertTrue(allTransformsAreFinite(in: rower.root))

        let ski = buildProceduralRig(sport: .skierg)
        ski.applyPose(.skierg(ReplaySkiErgRigPose(
            joints: ReplayAthleteJointPose(
                torsoLean: 0.12,
                shoulderFlexL: 0.22,
                shoulderFlexR: 0.22,
                kneeFlexL: 0.16,
                kneeFlexR: 0.16
            ),
            hipCompression: 0.25,
            handleY: 0.57,
            handleZ: 0.18,
            poleRotation: -0.22
        )))
        assertContact(named: "hand-L", with: "handle-L", in: ski)
        assertContact(named: "hand-R", with: "handle-R", in: ski)
        assertContact(named: "foot-L", with: "foot-anchor-L", in: ski)
        assertContact(named: "foot-R", with: "foot-anchor-R", in: ski)
        XCTAssertTrue(allTransformsAreFinite(in: ski.root))

        let bike = buildProceduralRig(sport: .bike)
        bike.applyPose(.bike(ReplayBikeErgRigPose(
            joints: ReplayAthleteJointPose(
                torsoTilt: 0.04,
                shoulderFlexL: -0.25,
                shoulderFlexR: -0.25,
                kneeFlexL: 0.42,
                kneeFlexR: -0.22
            ),
            crankAngle: .pi / 3,
            wheelAngle: .pi / 4,
            pedalPosL: ReplayPedalPosition(y: 0.18, z: 0),
            pedalPosR: ReplayPedalPosition(y: -0.18, z: 0),
            riderSway: 0.03
        )))
        assertContact(named: "hand-L", with: "handle-grip-anchor-L", in: bike)
        assertContact(named: "hand-R", with: "handle-grip-anchor-R", in: bike)
        assertContact(named: "foot-L", with: "pedal-L", in: bike)
        assertContact(named: "foot-R", with: "pedal-R", in: bike)
        XCTAssertTrue(allTransformsAreFinite(in: bike.root))
    }

    func testProceduralBikeKeepsChainStaysAndGhostsDoNotMutateLiveMaterials() {
        let live = buildProceduralRig(sport: .bike)
        let ghost = buildProceduralRig(sport: .bike)
        XCTAssertNotNil(live.root.replayDescendant(named: "chainStay-L"))
        XCTAssertNotNil(live.root.replayDescendant(named: "chainStay-R"))

        let liveBefore = materialAlphas(in: live.root)
        XCTAssertFalse(liveBefore.isEmpty)
        ghost.applyGhostTranslucency()
        XCTAssertEqual(materialAlphas(in: live.root), liveBefore)
        XCTAssertTrue(materialAlphas(in: ghost.root).allSatisfy { $0 <= 0.46 })
    }

    private func buildProceduralRig(sport: Sport) -> ReplaySportRig {
        ReplaySportRigFactory.build(
            sport: sport,
            into: ModelEntity(),
            accent: .green,
            opacity: 1,
            visualProvider: nil,
            canonicalAthlete: nil
        )
    }

    private func assertContact(
        named bodyPartName: String,
        with anchorName: String,
        in rig: ReplaySportRig,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let bodyPart = rig.root.replayDescendant(named: bodyPartName),
              let anchor = rig.root.replayDescendant(named: anchorName) else {
            return XCTFail("Missing \(bodyPartName) or \(anchorName)", file: file, line: line)
        }
        let bodyPosition = bodyPart.position(relativeTo: rig.root)
        let anchorPosition = anchor.position(relativeTo: rig.root)
        XCTAssertEqual(bodyPosition.x, anchorPosition.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(bodyPosition.y, anchorPosition.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(bodyPosition.z, anchorPosition.z, accuracy: 0.0001, file: file, line: line)
    }

    private func allTransformsAreFinite(in entity: Entity) -> Bool {
        let position = entity.position
        let orientation = entity.orientation
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              orientation.vector.x.isFinite, orientation.vector.y.isFinite,
              orientation.vector.z.isFinite, orientation.vector.w.isFinite else {
            return false
        }
        return entity.children.allSatisfy(allTransformsAreFinite)
    }

    private func materialAlphas(in entity: Entity) -> [Float] {
        var values: [Float] = []
        if let model = entity.components[ModelComponent.self] {
            for material in model.materials {
                if let simple = material as? SimpleMaterial {
                    values.append(Float(simple.color.tint.cgColor.alpha))
                } else if let pbr = material as? PhysicallyBasedMaterial {
                    values.append(Float(pbr.baseColor.tint.cgColor.alpha))
                } else if let unlit = material as? UnlitMaterial {
                    values.append(Float(unlit.color.tint.cgColor.alpha))
                }
            }
        }
        for child in entity.children {
            values.append(contentsOf: materialAlphas(in: child))
        }
        return values
    }
}
