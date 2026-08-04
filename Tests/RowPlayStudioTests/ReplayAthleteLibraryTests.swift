import RealityKit
import RowPlayCore
import Synchronization
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayAthleteLibraryTests: XCTestCase {
    override func setUp() async throws {
        ReplayAthleteLibrary.shared.resetCacheForTesting()
        ReplayAthleteMaterialLibrary.shared.resetCacheForTesting()
    }

    func testProductionAthleteTemplateLoadsFromReferenceBundle() async throws {
        let template = await ReplayAthleteLibrary.shared.athleteTemplate()
        let loaded = try XCTUnwrap(
            template,
            "The bundled production athlete must activate — fallback is for failures only"
        )
        XCTAssertEqual(loaded.contract.semanticBones.count, 19)
        XCTAssertEqual(loaded.contract.helpers.count, 32)
        XCTAssertEqual(loaded.contract.totalBoneCount, 51)
        XCTAssertEqual(loaded.motionTable.boneNames, loaded.contract.semanticBoneNames)
        XCTAssertGreaterThanOrEqual(loaded.motionTable.samplesPerSport, 257)
        // Every contract bone resolves to a distinct loaded skeleton joint.
        XCTAssertEqual(Set(loaded.semanticJointIndices).count, 19)
        XCTAssertEqual(Set(loaded.helperJointIndices).count, 32)
        XCTAssertTrue(
            Set(loaded.semanticJointIndices).isDisjoint(with: Set(loaded.helperJointIndices))
        )
        let contacts = await loaded.makeInstance(
            sport: .rower,
            name: "contacts",
            isRival: false,
            quality: .medium
        )
        XCTAssertNotNil(contacts?.leftHandContact)
        XCTAssertNotNil(contacts?.rightHandContact)
        XCTAssertNotNil(contacts?.leftFootContact)
        XCTAssertNotNil(contacts?.rightFootContact)
    }

    func testInstancesDriveDeterministicFinitePosesForAllSports() async throws {
        let loadedTemplate = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loadedTemplate)
        for sport in ReplayAssetCatalog.supportedSports {
            let built = await template.makeInstance(
                sport: sport,
                name: "live",
                isRival: false,
                quality: .medium
            )
            let instance = try XCTUnwrap(
                built,
                "\(sport.rawValue) instance must build"
            )
            // Direct and shuffled seeks must be deterministic: the same
            // fraction always reproduces the same pose regardless of the
            // seek order that preceded it.
            instance.seek(toClipFraction: 0.25)
            let first = try XCTUnwrap(instance.currentConstraintPose())
            instance.seek(toClipFraction: 0.8)
            instance.seek(toClipFraction: 0.1)
            instance.seek(toClipFraction: 0.25)
            let second = try XCTUnwrap(instance.currentConstraintPose())
            XCTAssertEqual(first.jointTransforms.count, second.jointTransforms.count)
            for index in 0..<first.jointTransforms.count {
                let a = first.jointTransforms[index]
                let b = second.jointTransforms[index]
                XCTAssertEqual(a.translation.x, b.translation.x, accuracy: 1e-6)
                XCTAssertEqual(a.translation.y, b.translation.y, accuracy: 1e-6)
                XCTAssertEqual(a.translation.z, b.translation.z, accuracy: 1e-6)
            }
            // Dense cycle stays finite.
            for step in 0..<64 {
                instance.seek(toClipFraction: Double(step) / 64)
                XCTAssertTrue(
                    instance.hasFiniteJointTransforms(),
                    "\(sport.rawValue) non-finite at step \(step)"
                )
            }
        }
    }

    func testAuthoredMotionActuallyMovesTheSkeleton() async throws {
        let loadedTemplate = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loadedTemplate)
        let built = await template.makeInstance(
            sport: .rower,
            name: "live",
            isRival: false,
            quality: .medium
        )
        let instance = try XCTUnwrap(built)
        instance.seek(toClipFraction: 0)
        let catchPose = try XCTUnwrap(instance.currentConstraintPose())
        instance.seek(toClipFraction: 0.38)
        let finishPose = try XCTUnwrap(instance.currentConstraintPose())
        // The hips travel with the slide between catch and finish; a static
        // skeleton means the motion table is not driving the joints.
        var maximumDelta: Float = 0
        for index in 0..<catchPose.jointTransforms.count {
            let delta = simd_distance(
                catchPose.jointTransforms[index].translation,
                finishPose.jointTransforms[index].translation
            )
            maximumDelta = max(maximumDelta, delta)
        }
        XCTAssertGreaterThan(
            maximumDelta,
            0.05,
            "catch → finish should move at least one joint by centimetres"
        )
    }

    func testLiveAndRivalInstancesRemainIndependent() async throws {
        let loadedTemplate = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loadedTemplate)
        let builtLive = await template.makeInstance(
            sport: .rower,
            name: "live",
            isRival: false,
            quality: .medium
        )
        let builtRival = await template.makeInstance(
            sport: .rower,
            name: "rival",
            isRival: true,
            quality: .medium
        )
        let live = try XCTUnwrap(builtLive)
        let rival = try XCTUnwrap(builtRival)
        live.seek(toClipFraction: 0.1)
        rival.seek(toClipFraction: 0.6)
        let livePose = try XCTUnwrap(live.currentConstraintPose())
        let rivalPose = try XCTUnwrap(rival.currentConstraintPose())
        var differs = false
        for index in 0..<livePose.jointTransforms.count {
            if simd_distance(
                livePose.jointTransforms[index].translation,
                rivalPose.jointTransforms[index].translation
            ) > 1e-4 {
                differs = true
                break
            }
        }
        XCTAssertTrue(differs, "live and rival skeleton state must be independent")

        var liveModel = try XCTUnwrap(live.athleteEntity.components[ModelComponent.self])
        let rivalModel = try XCTUnwrap(rival.athleteEntity.components[ModelComponent.self])
        XCTAssertEqual(liveModel.materials.count, 8)
        XCTAssertEqual(rivalModel.materials.count, 8)
        var changed = try XCTUnwrap(liveModel.materials[0] as? PhysicallyBasedMaterial)
        changed.roughness = 0.123
        liveModel.materials[0] = changed
        live.athleteEntity.components.set(liveModel)
        let rivalFirst = try XCTUnwrap(
            rival.athleteEntity.components[ModelComponent.self]?.materials[0]
                as? PhysicallyBasedMaterial
        )
        XCTAssertNotEqual(rivalFirst.roughness.scale, changed.roughness.scale)
    }

    func testEveryQualityUsesEightSurfaceMaterialsAndExactDetailMapLadder() async throws {
        let loadedTemplate = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loadedTemplate)
        XCTAssertEqual(template.nativeManifest.surfaceRoles, ReplayAthleteSurfaceRole.allCases)

        for quality in ReplayRenderQuality.allCases {
            let built = await template.makeInstance(
                sport: .rower,
                name: "quality-\(quality.rawValue)",
                isRival: false,
                quality: quality
            )
            let instance = try XCTUnwrap(built)
            let model = try XCTUnwrap(instance.athleteEntity.components[ModelComponent.self])
            XCTAssertEqual(instance.surfaceRoles, ReplayAthleteSurfaceRole.allCases)
            XCTAssertEqual(model.materials.count, 8)
            let expectedSize = ReplayAthleteMaterialProfile.detailTextureSize(for: quality)
            for (index, role) in instance.surfaceRoles.enumerated() {
                let material = try XCTUnwrap(model.materials[index] as? PhysicallyBasedMaterial)
                let expected = ReplayAthleteMaterialProfile.profile(for: role, quality: quality)
                XCTAssertEqual(material.roughness.scale, expected.roughness, accuracy: 1e-6)
                XCTAssertEqual(material.metallic.scale, expected.metallic, accuracy: 1e-6)
                XCTAssertEqual(material.clearcoat.scale, expected.clearcoat, accuracy: 1e-6)
                XCTAssertEqual(material.specular.scale, expected.specular, accuracy: 1e-6)
                let detail = material.normal.texture?.resource
                if expectedSize == 0 || role == .eye {
                    XCTAssertNil(detail, "\(quality.rawValue) \(role.rawValue) must not allocate detail")
                } else {
                    XCTAssertEqual(detail?.width, expectedSize)
                    XCTAssertEqual(detail?.height, expectedSize)
                }
            }
        }
    }

    func testPortablePreflightRunsOutsideMainThreadBeforeRealityKitLoad() async throws {
        let observations = Mutex<[Bool]>([])
        let library = ReplayAthleteLibrary(
            source: TestAthleteResourceSource(urls: try bundledResourceURLs()),
            preflightObserver: { ranOnMainThread in
                observations.withLock { $0.append(ranOnMainThread) }
            }
        )

        let loaded = await library.athleteTemplate()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(observations.withLock { $0 }, [false])
    }

    func testNativeDerivativeHashMismatchRejectsBeforeRealityKitLoad() async throws {
        var urls = try bundledResourceURLs()
        urls[.nativeUsdz] = urls[.usdz]
        var entityLoads = 0
        let library = ReplayAthleteLibrary(
            source: TestAthleteResourceSource(urls: urls),
            entityLoader: { url in
                entityLoads += 1
                return try await Entity(contentsOf: url)
            }
        )

        let loaded = await library.athleteTemplate()
        XCTAssertNil(loaded)
        XCTAssertEqual(entityLoads, 0)
        guard case .hashMismatch(let resource, _, _) = library.lastFailure else {
            return XCTFail("expected typed native derivative hash rejection")
        }
        XCTAssertEqual(resource, "athlete.native-usdz")
    }

    func testMissingResourceReportsTypedFailureOnceAndStaysFailed() async throws {
        var urls = try bundledResourceURLs()
        urls[.motionBin] = nil
        let source = TestAthleteResourceSource(urls: urls)
        var reports: [ReplayAthleteValidationFailure] = []
        let library = ReplayAthleteLibrary(source: source) { reports.append($0) }

        let first = await library.athleteTemplate()
        let second = await library.athleteTemplate()

        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(source.requests[.motionBin], 1)
        XCTAssertEqual(reports, [.missingResource(ReplayAthleteResource.motionBin.rawValue)])
        XCTAssertEqual(library.lastFailure, reports.first)
    }

    func testCorruptMotionPayloadRejectsBeforeRealityKitLoadAndReportsOnce() async throws {
        var urls = try bundledResourceURLs()
        var binData = try Data(contentsOf: try XCTUnwrap(urls[.motionBin]))
        binData[binData.startIndex] ^= 0xff
        let corruptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rowplay-corrupt-motion-\(UUID().uuidString).bin")
        try binData.write(to: corruptURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: corruptURL) }
        urls[.motionBin] = corruptURL

        let source = TestAthleteResourceSource(urls: urls)
        var reports: [ReplayAthleteValidationFailure] = []
        let library = ReplayAthleteLibrary(source: source) { reports.append($0) }

        async let first = library.athleteTemplate()
        async let second = library.athleteTemplate()
        let results = await (first, second)

        XCTAssertNil(results.0)
        XCTAssertNil(results.1)
        XCTAssertEqual(source.requests[.motionBin], 1)
        XCTAssertEqual(reports.count, 1)
        let failure = try XCTUnwrap(library.lastFailure)
        guard case .hashMismatch(let resource, _, _) = failure else {
            return XCTFail("Expected the motion payload hash rejection")
        }
        XCTAssertEqual(resource, "motion.bin")
    }

    func testSuccessfulConcurrentRequestsCoalesceOneRuntimeLoad() async throws {
        let source = TestAthleteResourceSource(urls: try bundledResourceURLs())
        var entityLoads = 0
        let library = ReplayAthleteLibrary(source: source, entityLoader: { url in
            entityLoads += 1
            return try await Entity(contentsOf: url)
        })

        async let first = library.athleteTemplate()
        async let second = library.athleteTemplate()
        let templates = await (first, second)

        XCTAssertNotNil(templates.0)
        XCTAssertTrue(templates.0 === templates.1)
        XCTAssertEqual(entityLoads, 1)
        for resource in ReplayAthleteResource.allCases {
            XCTAssertEqual(source.requests[resource], 1)
        }
        XCTAssertNil(library.lastFailure)
    }

    func testContractHashMismatchReportsExactFailure() async throws {
        var urls = try bundledResourceURLs()
        let contractURL = try XCTUnwrap(urls[.contract])
        var data = try Data(contentsOf: contractURL)
        data.append(0x0a)
        let changedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rowplay-contract-hash-\(UUID().uuidString).json")
        try data.write(to: changedURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: changedURL) }
        urls[.contract] = changedURL

        let library = ReplayAthleteLibrary(source: TestAthleteResourceSource(urls: urls))
        let template = await library.athleteTemplate()
        XCTAssertNil(template)
        guard case .hashMismatch(let resource, _, _) = library.lastFailure else {
            return XCTFail("Expected typed contract hash failure")
        }
        XCTAssertEqual(resource, "athlete.contract")
    }

    func testMissingContactEntityReportsExactTemplateFailure() async throws {
        let urls = try bundledResourceURLs()
        let root = try await Entity(contentsOf: try XCTUnwrap(urls[.nativeUsdz]))
        let markerName = try XCTUnwrap(
            ReplayAthleteCatalog.contactEntityNames[.leftHand]
        )
        let marker = try XCTUnwrap(
            root.findEntity(named: markerName) ?? root.replayDescendant(named: markerName)
        )
        marker.removeFromParent()
        let library = ReplayAthleteLibrary(
            source: TestAthleteResourceSource(urls: urls),
            entityLoader: { _ in root }
        )

        let template = await library.athleteTemplate()
        XCTAssertNil(template)
        XCTAssertEqual(library.lastFailure, .missingContact("left-hand"))
    }

    func testDuplicateContactEntityReportsExactTemplateFailure() async throws {
        let urls = try bundledResourceURLs()
        let root = try await Entity(contentsOf: try XCTUnwrap(urls[.nativeUsdz]))
        let markerName = try XCTUnwrap(
            ReplayAthleteCatalog.contactEntityNames[.rightHand]
        )
        let marker = try XCTUnwrap(
            root.findEntity(named: markerName) ?? root.replayDescendant(named: markerName)
        )
        root.addChild(marker.clone(recursive: true))
        let library = ReplayAthleteLibrary(
            source: TestAthleteResourceSource(urls: urls),
            entityLoader: { _ in root }
        )

        let template = await library.athleteTemplate()
        XCTAssertNil(template)
        XCTAssertEqual(library.lastFailure, .duplicateContact("right-hand"))
    }

    func testTemplateValidatorReportsJointIdentityAndTransformFailures() async throws {
        let loadedTemplate = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loadedTemplate)
        let contactCounts = Dictionary(uniqueKeysWithValues:
            ReplayAthleteContactRole.allCases.map { ($0, 1) }
        )

        var duplicateNames = template.jointNames
        duplicateNames[1] = duplicateNames[0]
        assertTemplateFailure(
            ReplayAthleteTemplateValidator.validate(
                contract: template.contract,
                motionBoneNames: template.motionTable.boneNames,
                jointNames: duplicateNames,
                jointTransforms: template.restTransforms,
                availableContactRoleCounts: contactCounts
            ),
            matches: { if case .duplicateBone = $0 { true } else { false } }
        )

        var missingNames = template.jointNames
        let hips = try XCTUnwrap(missingNames.firstIndex {
            $0.split(separator: "/").last == "v4Hips"
        })
        missingNames[hips] = "missingHips"
        assertTemplateFailure(
            ReplayAthleteTemplateValidator.validate(
                contract: template.contract,
                motionBoneNames: template.motionTable.boneNames,
                jointNames: missingNames,
                jointTransforms: template.restTransforms,
                availableContactRoleCounts: contactCounts
            ),
            equals: .missingBone("v4Hips")
        )

        var nonFinite = template.restTransforms
        nonFinite[0].translation.x = .nan
        assertTemplateFailure(
            ReplayAthleteTemplateValidator.validate(
                contract: template.contract,
                motionBoneNames: template.motionTable.boneNames,
                jointNames: template.jointNames,
                jointTransforms: nonFinite,
                availableContactRoleCounts: contactCounts
            ),
            matches: { if case .nonFiniteJointTransform = $0 { true } else { false } }
        )

        assertTemplateFailure(
            ReplayAthleteTemplateValidator.validate(
                contract: template.contract,
                motionBoneNames: template.motionTable.boneNames,
                jointNames: template.jointNames,
                jointTransforms: Array(template.restTransforms.dropLast()),
                availableContactRoleCounts: contactCounts
            ),
            equals: .jointCountMismatch(
                actual: template.restTransforms.count - 1,
                expected: template.jointNames.count
            )
        )

        var missingRightFoot = contactCounts
        missingRightFoot.removeValue(forKey: .rightFoot)
        assertTemplateFailure(
            ReplayAthleteTemplateValidator.validate(
                contract: template.contract,
                motionBoneNames: template.motionTable.boneNames,
                jointNames: template.jointNames,
                jointTransforms: template.restTransforms,
                availableContactRoleCounts: missingRightFoot
            ),
            equals: .missingContact("right-foot")
        )
    }

    func testSeekClearsConstraintAndReapplicationIsDeterministic() async throws {
        let loadedTemplate = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loadedTemplate)
        let built = await template.makeInstance(
            sport: .rower,
            name: "constraint",
            isRival: false,
            quality: .medium
        )
        let instance = try XCTUnwrap(built)
        XCTAssertTrue(instance.seek(toClipFraction: 0.25))
        let sampled = try XCTUnwrap(instance.currentConstraintPose())
        XCTAssertTrue(instance.beginConstraintPass())
        var constrained = try XCTUnwrap(instance.currentConstraintPose())
        constrained.jointTransforms[0].translation.x += 0.1
        XCTAssertTrue(instance.writeConstraintPose(constrained))
        let firstConstrained = try XCTUnwrap(instance.currentConstraintPose())

        XCTAssertTrue(instance.seek(toClipFraction: 0.25))
        let restored = try XCTUnwrap(instance.currentConstraintPose())
        XCTAssertEqual(
            restored.jointTransforms[0].translation.x,
            sampled.jointTransforms[0].translation.x,
            accuracy: 1e-6
        )

        XCTAssertTrue(instance.beginConstraintPass())
        var reapplied = try XCTUnwrap(instance.currentConstraintPose())
        reapplied.jointTransforms[0].translation.x += 0.1
        XCTAssertTrue(instance.writeConstraintPose(reapplied))
        XCTAssertEqual(
            try XCTUnwrap(instance.currentConstraintPose()).jointTransforms[0].translation.x,
            firstConstrained.jointTransforms[0].translation.x,
            accuracy: 1e-6
        )
    }

    private func bundledResourceURLs() throws -> [ReplayAthleteResource: URL] {
        var urls: [ReplayAthleteResource: URL] = [:]
        for resource in ReplayAthleteResource.allCases {
            urls[resource] = try XCTUnwrap(ReplayBundledResourceSupport.bundledURL(
                name: resource.name,
                extension: resource.fileExtension,
                subdirectory: resource.subdirectory
            ))
        }
        return urls
    }

    private func assertTemplateFailure(
        _ result: Result<ReplayAthleteTemplateBinding, ReplayAthleteValidationFailure>,
        equals expected: ReplayAthleteValidationFailure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertTemplateFailure(result, matches: { $0 == expected }, file: file, line: line)
    }

    private func assertTemplateFailure(
        _ result: Result<ReplayAthleteTemplateBinding, ReplayAthleteValidationFailure>,
        matches predicate: (ReplayAthleteValidationFailure) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let failure) = result else {
            return XCTFail("Expected template validation failure", file: file, line: line)
        }
        XCTAssertTrue(predicate(failure), "Unexpected failure: \(failure)", file: file, line: line)
    }
}

@MainActor
private final class TestAthleteResourceSource: ReplayAthleteResourceSource {
    let urls: [ReplayAthleteResource: URL]
    private(set) var requests: [ReplayAthleteResource: Int] = [:]

    init(urls: [ReplayAthleteResource: URL]) {
        self.urls = urls
    }

    func url(for resource: ReplayAthleteResource) -> URL? {
        requests[resource, default: 0] += 1
        return urls[resource]
    }
}
