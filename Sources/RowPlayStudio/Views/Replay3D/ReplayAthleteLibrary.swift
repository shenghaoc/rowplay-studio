import Foundation
import RealityKit
import RowPlayCore

enum ReplayAthleteResource: String, CaseIterable, Sendable {
    case contract
    case sourceManifest
    case usdz
    case motionManifest
    case motionBin

    var name: String {
        switch self {
        case .contract: ReplayAthleteCatalog.contractResourceName
        case .sourceManifest: ReplayAthleteCatalog.sourceManifestResourceName
        case .usdz: ReplayAthleteCatalog.usdzResourceName
        case .motionManifest: ReplayAthleteCatalog.motionManifestResourceName
        case .motionBin: ReplayAthleteCatalog.motionBinResourceName
        }
    }

    var fileExtension: String {
        switch self {
        case .contract: ReplayAthleteCatalog.contractExtension
        case .sourceManifest: ReplayAthleteCatalog.sourceManifestExtension
        case .usdz: ReplayAthleteCatalog.usdzExtension
        case .motionManifest: ReplayAthleteCatalog.motionManifestExtension
        case .motionBin: ReplayAthleteCatalog.motionBinExtension
        }
    }

    var subdirectory: String {
        switch self {
        case .contract, .sourceManifest, .usdz:
            ReplayAthleteCatalog.athleteSubdirectory
        case .motionManifest, .motionBin:
            ReplayAthleteCatalog.motionSubdirectory
        }
    }
}

@MainActor
protocol ReplayAthleteResourceSource: AnyObject {
    func url(for resource: ReplayAthleteResource) -> URL?
}

@MainActor
private final class ReplayModuleAthleteResourceSource: ReplayAthleteResourceSource {
    func url(for resource: ReplayAthleteResource) -> URL? {
        ReplayBundledResourceSupport.bundledURL(
            name: resource.name,
            extension: resource.fileExtension,
            subdirectory: resource.subdirectory
        )
    }
}

/// Loads and validates the bundled production athlete from the
/// `ReplayReference` bundle: contract, source manifest, native USDZ, and the
/// sampled motion table.
///
/// Failure is atomic — a package that fails any gate yields no template, and
/// the failure is cached so scene rebuilds remain deterministic and never
/// retry a broken package on every SwiftUI update.
@MainActor
final class ReplayAthleteLibrary {
    static let shared = ReplayAthleteLibrary(source: ReplayModuleAthleteResourceSource())
    private static let logger = PrivacySafeLogger(category: "replay-athlete")

    private let source: any ReplayAthleteResourceSource
    private let failureReporter: (ReplayAthleteValidationFailure) -> Void
    private let entityLoader: (URL) async throws -> Entity
    private var template: ReplayAthleteTemplate?
    private var loadFailed = false
    private var inFlight: Task<ReplayAthleteTemplate?, Never>?
    private(set) var lastFailure: ReplayAthleteValidationFailure?

    init(
        source: any ReplayAthleteResourceSource,
        failureReporter: ((ReplayAthleteValidationFailure) -> Void)? = nil,
        entityLoader: ((URL) async throws -> Entity)? = nil
    ) {
        self.source = source
        self.entityLoader = entityLoader ?? { try await Entity(contentsOf: $0) }
        self.failureReporter = failureReporter ?? { failure in
            ReplayAthleteLibrary.logger.warn(
                "Replay athlete package rejected",
                failure.diagnosticCode,
                failure.diagnosticContext
            )
        }
    }

    func athleteTemplate() async -> ReplayAthleteTemplate? {
        if let template {
            return template
        }
        guard !loadFailed else { return nil }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { @MainActor [weak self] () -> ReplayAthleteTemplate? in
            guard let self else { return nil }
            return await self.loadTemplate()
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    func resetCacheForTesting() {
        template = nil
        loadFailed = false
        lastFailure = nil
        inFlight?.cancel()
        inFlight = nil
    }

    private func loadTemplate() async -> ReplayAthleteTemplate? {
        if let template {
            return template
        }
        guard !loadFailed else { return nil }

        var urls: [ReplayAthleteResource: URL] = [:]
        for resource in ReplayAthleteResource.allCases {
            guard let url = source.url(for: resource) else {
                return reject(.missingResource(resource.rawValue))
            }
            urls[resource] = url
        }
        var payloads: [ReplayAthleteResource: Data] = [:]
        for resource in ReplayAthleteResource.allCases where resource != .usdz {
            guard let url = urls[resource], let data = try? Data(contentsOf: url) else {
                return reject(.unreadableResource(resource.rawValue))
            }
            payloads[resource] = data
        }
        guard let usdzURL = urls[.usdz],
              let contractData = payloads[.contract],
              let sourceData = payloads[.sourceManifest],
              let motionManifestData = payloads[.motionManifest],
              let motionBinData = payloads[.motionBin] else {
            return reject(.invalidRuntimeAsset)
        }

        let parsedSource = ReplayAthleteCatalog.parseSourceManifest(data: sourceData)
        guard case .success(let manifest) = parsedSource else {
            if case .failure(let failure) = parsedSource { return reject(failure) }
            return reject(.invalidContract("source manifest"))
        }
        let sourceValidation = ReplayAthleteCatalog.validateSourceManifest(manifest)
        if let failure = sourceValidation.failures.first { return reject(failure) }

        let contractHash = ReplayBundledResourceSupport.sha256Hex(of: contractData)
        let usdzHash: String
        do {
            usdzHash = try ReplayBundledResourceSupport.sha256Hex(contentsOf: usdzURL)
        } catch {
            return reject(.unreadableResource(ReplayAthleteResource.usdz.rawValue))
        }
        guard contractHash == manifest.contractSha256 else {
            return reject(.hashMismatch(
                resource: "athlete.contract",
                expected: manifest.contractSha256,
                actual: contractHash
            ))
        }
        guard usdzHash == manifest.usdzSha256 else {
            return reject(.hashMismatch(
                resource: "athlete.usdz",
                expected: manifest.usdzSha256,
                actual: usdzHash
            ))
        }
        let parsedContract = ReplayAthleteCatalog.parseContract(data: contractData)
        guard case .success(let contract) = parsedContract else {
            if case .failure(let failure) = parsedContract { return reject(failure) }
            return reject(.invalidContract("contract"))
        }
        let contractValidation = ReplayAthleteCatalog.validateContract(contract, manifest: manifest)
        if let failure = contractValidation.failures.first { return reject(failure) }

        let parsedMotion = ReplayAthleteCatalog.parseMotionManifest(data: motionManifestData)
        guard case .success(let motionManifest) = parsedMotion else {
            if case .failure(let failure) = parsedMotion { return reject(failure) }
            return reject(.invalidMotionManifest("manifest"))
        }
        let motionValidation = ReplayAthleteCatalog.validateMotionManifest(
            motionManifest,
            source: manifest,
            binData: motionBinData
        )
        if let failure = motionValidation.failures.first { return reject(failure) }

        // The motion table must come from the same pinned tree and match the
        // contract's semantic hierarchy exactly.
        let motionTable: ReplayAthleteMotionTable
        do {
            motionTable = try ReplayAthleteMotionTable(
                manifest: motionManifest,
                binData: motionBinData
            )
        } catch let error as ReplayAthleteMotionTable.LoadError {
            return reject(.motionTableLoad(error))
        } catch {
            return reject(.invalidMotionManifest("unrecognized table load error"))
        }
        let supportedSports = Set(Sport.allCases)
        guard motionTable.boneNames == contract.semanticBoneNames,
        motionTable.sourceCommit == manifest.pinnedCommit,
        Set(motionTable.sports) == supportedSports,
        Set(motionTable.clips.keys) == supportedSports else {
            return reject(.invalidMotionManifest("motion table"))
        }
        for sport in [Sport.rower, .skierg, .bike] {
            guard let tableClip = motionTable.clips[sport],
                  let contractClip = contract.clip(for: sport),
                  tableClip.clipName == contractClip.name,
                  abs(tableClip.driveEnd - contractClip.driveEnd) < 1e-9 else {
                return reject(.invalidMotionManifest("\(sport.rawValue) clip"))
            }
        }

        let root: Entity
        do {
            root = try await entityLoader(usdzURL)
        } catch {
            return reject(.unreadableResource("athlete.usdz.runtime"))
        }
        let template: ReplayAthleteTemplate
        do {
            template = try ReplayAthleteTemplate(
                root: root,
                contract: contract,
                sourceManifest: manifest,
                motionTable: motionTable
            )
        } catch let failure as ReplayAthleteValidationFailure {
            return reject(failure)
        } catch {
            return reject(.invalidRuntimeAsset)
        }

        self.template = template
        return template
    }

    private func reject(
        _ failure: ReplayAthleteValidationFailure
    ) -> ReplayAthleteTemplate? {
        guard !loadFailed else { return nil }
        loadFailed = true
        lastFailure = failure
        failureReporter(failure)
        return nil
    }

}

private extension ReplayAthleteValidationFailure {
    var diagnosticCode: String {
        switch self {
        case .missingResource: "missing-resource"
        case .unreadableResource: "unreadable-resource"
        case .hashMismatch: "hash-mismatch"
        case .invalidContract: "invalid-contract"
        case .invalidMotionManifest: "invalid-motion-manifest"
        case .motionTableLoad: "motion-table-load"
        case .byteCountMismatch: "byte-count-mismatch"
        case .missingBone: "missing-bone"
        case .duplicateBone: "duplicate-bone"
        case .boneCountMismatch: "bone-count-mismatch"
        case .jointCountMismatch: "joint-count-mismatch"
        case .missingClip: "missing-clip"
        case .invalidClipTiming: "invalid-clip-timing"
        case .missingContact: "missing-contact"
        case .duplicateContact: "duplicate-contact"
        case .nonFiniteRestTransform: "nonfinite-rest-transform"
        case .nonFiniteJointTransform: "nonfinite-joint-transform"
        case .missingSkinnedAthlete: "missing-skinned-athlete"
        case .multipleSkinnedAthletes: "multiple-skinned-athletes"
        case .missingModelComponent: "missing-model-component"
        case .missingSkeletalPose: "missing-skeletal-pose"
        case .missingAnimation: "missing-animation"
        case .invalidRuntimeAsset: "invalid-runtime-asset"
        case .pinMismatch: "pin-mismatch"
        }
    }

    var diagnosticContext: String {
        switch self {
        case .missingResource(let resource),
             .unreadableResource(let resource),
             .invalidContract(let resource),
             .invalidMotionManifest(let resource),
             .missingBone(let resource),
             .duplicateBone(let resource),
             .missingContact(let resource),
             .duplicateContact(let resource),
             .nonFiniteRestTransform(let resource),
             .nonFiniteJointTransform(let resource),
             .pinMismatch(let resource):
            resource
        case .hashMismatch(let resource, _, _),
             .byteCountMismatch(let resource, _, _):
            resource
        case .missingClip(let sport), .invalidClipTiming(let sport):
            sport.rawValue
        case .motionTableLoad(let error):
            String(describing: error)
        case .boneCountMismatch(let actual, let expected),
             .jointCountMismatch(let actual, let expected):
            "actual=\(actual) expected=\(expected)"
        case .missingSkinnedAthlete,
             .multipleSkinnedAthletes,
             .missingModelComponent,
             .missingSkeletalPose,
             .missingAnimation,
             .invalidRuntimeAsset:
            "runtime"
        }
    }
}
