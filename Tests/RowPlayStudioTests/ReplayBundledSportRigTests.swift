import RealityKit
import RowPlayCore
import SwiftUI
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayBundledSportRigTests: XCTestCase {
    func testBundledRigsKeepEquipmentVisualsAndCanonicalAthleteContactsForEverySport() async {
        for sport in ReplayAssetCatalog.supportedSports {
            guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport) else {
                return XCTFail("Expected bundled asset set for \(sport.rawValue)")
            }

            let rig = buildRig(sport: sport, assetSet: assetSet)
            // Equipment visuals remain native-owned.
            for visualName in ReplayAssetCatalog.requiredRigNodeNames(for: sport) {
                XCTAssertNotNil(
                    rig.root.replayDescendant(named: visualName),
                    "Bundled \(sport.rawValue) rig is missing visual \(visualName)"
                )
            }
            // Canonical V4 supplies palm/sole contact markers (renamed for tests).
            for contact in ["hand-L", "hand-R", "foot-L", "foot-R"] {
                XCTAssertNotNil(
                    rig.root.replayDescendant(named: contact),
                    "Bundled \(sport.rawValue) rig is missing V4 contact \(contact)"
                )
            }
            // Native human body pivots must not appear alongside the V4 athlete.
            for pivot in ["pelvis", "torso", "visual-pelvis", "visual-torso"] {
                XCTAssertNil(
                    rig.root.replayDescendant(named: pivot),
                    "Bundled \(sport.rawValue) must not mix a second human with V4"
                )
            }
            XCTAssertNotNil(rig.root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName))
        }
    }

    func testBundledRowerPreservesHandleAndFootContactsWithFiniteTransforms() async {
        guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower) else {
            return XCTFail("Expected bundled rower asset set")
        }
        let rig = buildRig(sport: .rower, assetSet: assetSet)
        rig.applyPose(
            .rower(ReplayRowerRigPose(
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
            )),
            motion: ReplayAthleteMotionSample(phase: 1.2, cycleFrac: 0.25, driveFrac: 0.4)
        )

        assertContact(named: "hand-L", with: "handle-grip-anchor-L", in: rig)
        assertContact(named: "hand-R", with: "handle-grip-anchor-R", in: rig)
        assertContact(named: "foot-L", with: "foot-anchor-L", in: rig)
        assertContact(named: "foot-R", with: "foot-anchor-R", in: rig)
        XCTAssertTrue(allTransformsAreFinite(in: rig.root))
    }

    func testBundledSkiErgPreservesHandleAndFootContactsWithFiniteTransforms() async {
        guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .skierg) else {
            return XCTFail("Expected bundled SkiErg asset set")
        }
        let rig = buildRig(sport: .skierg, assetSet: assetSet)
        rig.applyPose(
            .skierg(ReplaySkiErgRigPose(
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
            )),
            motion: ReplayAthleteMotionSample(phase: 0.8, cycleFrac: 0.2, driveFrac: 0.34)
        )

        assertContact(named: "hand-L", with: "handle-L", in: rig)
        assertContact(named: "hand-R", with: "handle-R", in: rig)
        assertContact(named: "foot-L", with: "foot-anchor-L", in: rig)
        assertContact(named: "foot-R", with: "foot-anchor-R", in: rig)
        XCTAssertTrue(allTransformsAreFinite(in: rig.root))
    }

    func testBundledBikeErgPreservesPedalAndHandlebarContactsWithFiniteTransforms() async {
        guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .bike) else {
            return XCTFail("Expected bundled BikeErg asset set")
        }
        let rig = buildRig(sport: .bike, assetSet: assetSet)
        rig.applyPose(
            .bike(ReplayBikeErgRigPose(
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
            )),
            motion: ReplayAthleteMotionSample(phase: 2.1, cycleFrac: 0.4, driveFrac: 0.5)
        )

        assertContact(named: "hand-L", with: "handle-grip-anchor-L", in: rig)
        assertContact(named: "hand-R", with: "handle-grip-anchor-R", in: rig)
        assertContact(named: "foot-L", with: "pedal-L", in: rig)
        assertContact(named: "foot-R", with: "pedal-R", in: rig)
        XCTAssertTrue(allTransformsAreFinite(in: rig.root))
    }

    func testBundledEquipmentVisualsFollowTheExistingMotionPivots() async throws {
        guard let rowerSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower),
              let skiSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .skierg),
              let bikeSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .bike) else {
            return XCTFail("Expected every bundled sport set")
        }

        let rower = buildRig(sport: .rower, assetSet: rowerSet)
        rower.applyPose(.rower(ReplayRowerRigPose(
            joints: .neutral,
            seatZ: -0.32,
            handleY: 0.72,
            handleZ: 0.50,
            oarSweep: -0.5,
            oarFeather: -0.06
        )))
        let rowerCatchSeat = try position(named: "visual-seat", in: rower)
        let rowerCatchHandle = try position(named: "visual-handle", in: rower)
        let rowerCatchOar = try orientation(named: "visual-oar-port", in: rower)
        rower.applyPose(.rower(ReplayRowerRigPose(
            joints: .neutral,
            seatZ: -0.10,
            handleY: 0.76,
            handleZ: 0.66,
            oarSweep: 0.5,
            oarFeather: 0.2
        )))
        XCTAssertNotEqual(rowerCatchSeat, try position(named: "visual-seat", in: rower))
        XCTAssertNotEqual(rowerCatchHandle, try position(named: "visual-handle", in: rower))
        XCTAssertNotEqual(rowerCatchOar, try orientation(named: "visual-oar-port", in: rower))

        let ski = buildRig(sport: .skierg, assetSet: skiSet)
        ski.applyPose(.skierg(ReplaySkiErgRigPose(
            joints: .neutral,
            hipCompression: 0,
            handleY: 0.58,
            handleZ: 0.41,
            poleRotation: -1.0
        )))
        let skiTallHandle = try position(named: "visual-handle-L", in: ski)
        let skiTallPole = try orientation(named: "visual-pole-L", in: ski)
        let skiTallCableScale = try XCTUnwrap(ski.root.replayDescendant(named: "cable")).scale.y
        ski.applyPose(.skierg(ReplaySkiErgRigPose(
            joints: .neutral,
            hipCompression: 0.8,
            handleY: 0.26,
            handleZ: -0.09,
            poleRotation: 0.8
        )))
        XCTAssertNotEqual(skiTallHandle, try position(named: "visual-handle-L", in: ski))
        XCTAssertNotEqual(skiTallPole, try orientation(named: "visual-pole-L", in: ski))
        XCTAssertNotEqual(skiTallCableScale, try XCTUnwrap(ski.root.replayDescendant(named: "cable")).scale.y)

        let bike = buildRig(sport: .bike, assetSet: bikeSet)
        bike.applyPose(.bike(ReplayBikeErgRigPose(
            crankAngle: 0,
            wheelAngle: 0,
            pedalPosL: ReplayPedalPosition(y: 0.18, z: 0),
            pedalPosR: ReplayPedalPosition(y: -0.18, z: 0)
        )))
        let bikeStartCranks = try orientation(named: "visual-cranks", in: bike)
        let bikeStartWheel = try orientation(named: "visual-wheel-front", in: bike)
        let bikeStartPedal = try position(named: "visual-pedal-L", in: bike)
        bike.applyPose(.bike(ReplayBikeErgRigPose(
            crankAngle: .pi / 2,
            wheelAngle: .pi * 1.2,
            pedalPosL: ReplayPedalPosition(y: 0, z: 0.18),
            pedalPosR: ReplayPedalPosition(y: 0, z: -0.18)
        )))
        XCTAssertNotEqual(bikeStartCranks, try orientation(named: "visual-cranks", in: bike))
        XCTAssertNotEqual(bikeStartWheel, try orientation(named: "visual-wheel-front", in: bike))
        XCTAssertNotEqual(bikeStartPedal, try position(named: "visual-pedal-L", in: bike))
    }

    func testBundledGhostAppliesTranslucencyWithoutMutatingLiveMaterialsForEverySport() async {
        for sport in ReplayAssetCatalog.supportedSports {
            guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport) else {
                return XCTFail("Expected bundled \(sport.rawValue) asset set")
            }

            let live = buildRig(sport: sport, assetSet: assetSet)
            let ghost = buildRig(sport: sport, assetSet: assetSet)
            let liveBefore = recognizedMaterialAlphas(in: live.root)
            XCTAssertFalse(liveBefore.isEmpty, "Expected PBR materials in bundled \(sport.rawValue) rig")

            ghost.applyGhostTranslucency()

            XCTAssertEqual(recognizedMaterialAlphas(in: live.root), liveBefore)
            let ghostAlphas = recognizedMaterialAlphas(in: ghost.root)
            XCTAssertFalse(ghostAlphas.isEmpty, "Expected ghost materials in bundled \(sport.rawValue) rig")
            XCTAssertTrue(ghostAlphas.allSatisfy { $0 <= 0.46 })
            // USDA materials load as PBR; transparent blending must be enabled
            // or rivals render solid despite tint alpha.
            XCTAssertGreaterThan(
                transparentPBRMaterialCount(in: ghost.root),
                0,
                "Bundled \(sport.rawValue) ghost must enable PBR transparent blending"
            )
        }
    }

    func testBundledBikeErgDoesNotMixProceduralChainStays() async {
        guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .bike) else {
            return XCTFail("Expected bundled bike asset set")
        }
        let bundled = buildRig(sport: .bike, assetSet: assetSet)
        XCTAssertNil(bundled.root.replayDescendant(named: "chainStay-L"))
        XCTAssertNil(bundled.root.replayDescendant(named: "chainStay-R"))
        XCTAssertNotNil(bundled.root.replayDescendant(named: "visual-topTube"))

        let procedural = ReplaySportRigFactory.build(
            sport: .bike,
            into: ModelEntity(),
            accent: .green,
            opacity: 1,
            visualProvider: nil,
            canonicalAthlete: nil
        )
        XCTAssertNotNil(procedural.root.replayDescendant(named: "chainStay-L"))
        XCTAssertNotNil(procedural.root.replayDescendant(named: "chainStay-R"))
    }

    func testBundledAccentSlotsAreRecolouredPerIndependentLiveAndGhostClone() async {
        guard let assetSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower) else {
            return XCTFail("Expected bundled rower asset set")
        }

        let originalAccentSlots = ReplayAssetCatalog.requiredRigNodeNames(for: .rower)
            .compactMap { assetSet.rigVisualProvider.cloneVisual(named: $0) }
            .reduce(0) { $0 + accentMaterialSlotCount(in: $1) }
        XCTAssertGreaterThan(originalAccentSlots, 0, "Expected generated accent material slots")

        let live = buildRig(sport: .rower, assetSet: assetSet, accent: .green)
        let ghost = buildRig(sport: .rower, assetSet: assetSet, accent: .purple)
        let liveAccentSlots = accentMaterialCount(matching: NSColor(Color.green), in: live.root)
        let ghostAccentSlots = accentMaterialCount(matching: NSColor(Color.purple), in: ghost.root)

        XCTAssertEqual(liveAccentSlots, originalAccentSlots)
        XCTAssertEqual(ghostAccentSlots, originalAccentSlots)

        ghost.applyGhostTranslucency()
        XCTAssertEqual(accentMaterialCount(matching: NSColor(Color.green), in: live.root), originalAccentSlots)
    }

    private func buildRig(
        sport: Sport,
        assetSet: ReplayBundledAssetSet,
        accent: Color = .green
    ) -> ReplaySportRig {
        let athlete = assetSet.makeAthleteInstance(name: "test-v4-\(sport.rawValue)", opacity: 1)
        return ReplaySportRigFactory.build(
            sport: sport,
            into: ModelEntity(),
            accent: accent,
            opacity: 1,
            visualProvider: assetSet.rigVisualProvider,
            canonicalAthlete: athlete
        )
    }

    private func assertContact(named bodyPartName: String, with anchorName: String, in rig: ReplaySportRig,
                               file: StaticString = #filePath, line: UInt = #line) {
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

    private func position(named name: String, in rig: ReplaySportRig) throws -> SIMD3<Float> {
        let entity = try XCTUnwrap(rig.root.replayDescendant(named: name))
        return entity.position(relativeTo: rig.root)
    }

    private func orientation(named name: String, in rig: ReplaySportRig) throws -> simd_quatf {
        let entity = try XCTUnwrap(rig.root.replayDescendant(named: name))
        return entity.orientation(relativeTo: rig.root)
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

    private func recognizedMaterialAlphas(in entity: Entity) -> [Float] {
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
            values.append(contentsOf: recognizedMaterialAlphas(in: child))
        }
        return values
    }

    private func transparentPBRMaterialCount(in entity: Entity) -> Int {
        var count = 0
        if let model = entity.components[ModelComponent.self] {
            for material in model.materials {
                guard let pbr = material as? PhysicallyBasedMaterial else { continue }
                if case .transparent = pbr.blending {
                    count += 1
                }
            }
        }
        for child in entity.children {
            count += transparentPBRMaterialCount(in: child)
        }
        return count
    }

    private func accentMaterialSlotCount(in entity: Entity) -> Int {
        let ownCount = entity.name.hasPrefix("material_accent_")
            && entity.components[ModelComponent.self] != nil ? 1 : 0
        return ownCount + entity.children.reduce(0) { $0 + accentMaterialSlotCount(in: $1) }
    }

    private func accentMaterialCount(matching expected: NSColor, in entity: Entity) -> Int {
        var count = 0
        if entity.name.hasPrefix("material_accent_"),
           let model = entity.components[ModelComponent.self] {
            for material in model.materials {
                if let simple = material as? SimpleMaterial,
                   colorsMatch(simple.color.tint, expected) {
                    count += 1
                } else if let pbr = material as? PhysicallyBasedMaterial,
                          colorsMatch(pbr.baseColor.tint, expected) {
                    count += 1
                } else if let unlit = material as? UnlitMaterial,
                          colorsMatch(unlit.color.tint, expected) {
                    count += 1
                }
            }
        }
        for child in entity.children {
            count += accentMaterialCount(matching: expected, in: child)
        }
        return count
    }

    private func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let left = lhs.usingColorSpace(.deviceRGB),
              let right = rhs.usingColorSpace(.deviceRGB) else {
            return false
        }
        let tolerance: CGFloat = 0.015
        return abs(left.redComponent - right.redComponent) <= tolerance
            && abs(left.greenComponent - right.greenComponent) <= tolerance
            && abs(left.blueComponent - right.blueComponent) <= tolerance
    }
}
