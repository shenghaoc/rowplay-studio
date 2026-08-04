import RealityKit
import RowPlayCore
import XCTest
@testable import RowPlayStudio

@MainActor
final class ReplayAthleteLibraryTests: XCTestCase {
    override func setUp() async throws {
        ReplayAthleteLibrary.shared.resetCacheForTesting()
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
        XCTAssertNotNil(loaded.makeInstance(sport: .rower, name: "contacts", isRival: false)?.leftHandContact)
        XCTAssertNotNil(loaded.makeInstance(sport: .rower, name: "contacts", isRival: false)?.rightHandContact)
        XCTAssertNotNil(loaded.makeInstance(sport: .rower, name: "contacts", isRival: false)?.leftFootContact)
        XCTAssertNotNil(loaded.makeInstance(sport: .rower, name: "contacts", isRival: false)?.rightFootContact)
    }

    func testInstancesDriveDeterministicFinitePosesForAllSports() async throws {
        let loadedTemplate = await ReplayAthleteLibrary.shared.athleteTemplate()
        let template = try XCTUnwrap(loadedTemplate)
        for sport in ReplayAssetCatalog.supportedSports {
            let instance = try XCTUnwrap(
                template.makeInstance(sport: sport, name: "live", isRival: false),
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
        let instance = try XCTUnwrap(
            template.makeInstance(sport: .rower, name: "live", isRival: false)
        )
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
        let live = try XCTUnwrap(
            template.makeInstance(sport: .rower, name: "live", isRival: false)
        )
        let rival = try XCTUnwrap(
            template.makeInstance(sport: .rower, name: "rival", isRival: true)
        )
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
        let root = try await Entity(contentsOf: try XCTUnwrap(urls[.usdz]))
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
        let root = try await Entity(contentsOf: try XCTUnwrap(urls[.usdz]))
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
        let instance = try XCTUnwrap(
            template.makeInstance(sport: .rower, name: "constraint", isRival: false)
        )
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
