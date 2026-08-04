import Foundation
import RealityKit
import RowPlayCore

enum ReplayAthleteResource: String, CaseIterable, Sendable {
    case contract
    case sourceManifest
    case usdz
    case nativeManifest
    case nativeUsdz
    case motionManifest
    case motionBin

    var name: String {
        switch self {
        case .contract: ReplayAthleteCatalog.contractResourceName
        case .sourceManifest: ReplayAthleteCatalog.sourceManifestResourceName
        case .usdz: ReplayAthleteCatalog.usdzResourceName
        case .nativeManifest: ReplayAthleteCatalog.nativeManifestResourceName
        case .nativeUsdz: ReplayAthleteCatalog.nativeUsdzResourceName
        case .motionManifest: ReplayAthleteCatalog.motionManifestResourceName
        case .motionBin: ReplayAthleteCatalog.motionBinResourceName
        }
    }

    var fileExtension: String {
        switch self {
        case .contract: ReplayAthleteCatalog.contractExtension
        case .sourceManifest: ReplayAthleteCatalog.sourceManifestExtension
        case .usdz: ReplayAthleteCatalog.usdzExtension
        case .nativeManifest: ReplayAthleteCatalog.nativeManifestExtension
        case .nativeUsdz: ReplayAthleteCatalog.nativeUsdzExtension
        case .motionManifest: ReplayAthleteCatalog.motionManifestExtension
        case .motionBin: ReplayAthleteCatalog.motionBinExtension
        }
    }

    var subdirectory: String {
        switch self {
        case .contract, .sourceManifest, .usdz, .nativeManifest, .nativeUsdz:
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

struct ReplayAthletePreflight: Sendable {
    let runtimeUsdzURL: URL
    let contract: ReplayAthleteContract
    let sourceManifest: ReplayAthleteSourceManifest
    let nativeManifest: ReplayAthleteNativeManifest
    let motionTable: ReplayAthleteMotionTable
}

/// Portable package I/O, hashing, JSON validation and motion-table parsing.
/// This type has no RealityKit state and is deliberately nonisolated so the
/// first 3D open never performs 22 MB of file/hash work on MainActor.
enum ReplayAthletePreflightLoader {
    nonisolated static func isMainThread() -> Bool {
        Thread.isMainThread
    }

    nonisolated static func load(
        urls: [ReplayAthleteResource: URL]
    ) -> Result<ReplayAthletePreflight, ReplayAthleteValidationFailure> {
        var payloads: [ReplayAthleteResource: Data] = [:]
        for resource in ReplayAthleteResource.allCases
        where resource != .usdz && resource != .nativeUsdz {
            guard let url = urls[resource], let data = try? Data(contentsOf: url) else {
                return .failure(.unreadableResource(resource.rawValue))
            }
            payloads[resource] = data
        }
        guard let sourceUsdzURL = urls[.usdz],
              let runtimeUsdzURL = urls[.nativeUsdz],
              let contractData = payloads[.contract],
              let sourceData = payloads[.sourceManifest],
              let nativeManifestData = payloads[.nativeManifest],
              let motionManifestData = payloads[.motionManifest],
              let motionBinData = payloads[.motionBin] else {
            return .failure(.invalidRuntimeAsset)
        }

        let manifest: ReplayAthleteSourceManifest
        switch ReplayAthleteCatalog.parseSourceManifest(data: sourceData) {
        case .success(let parsed): manifest = parsed
        case .failure(let failure): return .failure(failure)
        }
        if let failure = ReplayAthleteCatalog.validateSourceManifest(manifest).failures.first {
            return .failure(failure)
        }

        let contractHash = ReplayBundledResourceSupport.sha256Hex(of: contractData)
        guard contractHash == manifest.contractSha256 else {
            return .failure(.hashMismatch(
                resource: "athlete.contract",
                expected: manifest.contractSha256,
                actual: contractHash
            ))
        }
        let sourceUsdzHash: String
        do {
            sourceUsdzHash = try ReplayBundledResourceSupport.sha256Hex(contentsOf: sourceUsdzURL)
        } catch {
            return .failure(.unreadableResource(ReplayAthleteResource.usdz.rawValue))
        }
        guard sourceUsdzHash == manifest.usdzSha256 else {
            return .failure(.hashMismatch(
                resource: "athlete.usdz",
                expected: manifest.usdzSha256,
                actual: sourceUsdzHash
            ))
        }

        let contract: ReplayAthleteContract
        switch ReplayAthleteCatalog.parseContract(data: contractData) {
        case .success(let parsed): contract = parsed
        case .failure(let failure): return .failure(failure)
        }
        if let failure = ReplayAthleteCatalog.validateContract(
            contract,
            manifest: manifest
        ).failures.first {
            return .failure(failure)
        }

        let nativeManifest: ReplayAthleteNativeManifest
        switch ReplayAthleteCatalog.parseNativeManifest(data: nativeManifestData) {
        case .success(let parsed): nativeManifest = parsed
        case .failure(let failure): return .failure(failure)
        }
        if let failure = ReplayAthleteCatalog.validateNativeManifest(
            nativeManifest,
            source: manifest,
            contract: contract
        ).failures.first {
            return .failure(failure)
        }
        let runtimeHash: String
        do {
            runtimeHash = try ReplayBundledResourceSupport.sha256Hex(contentsOf: runtimeUsdzURL)
        } catch {
            return .failure(.unreadableResource(ReplayAthleteResource.nativeUsdz.rawValue))
        }
        guard runtimeHash == nativeManifest.runtimeUsdzSha256 else {
            return .failure(.hashMismatch(
                resource: "athlete.native-usdz",
                expected: nativeManifest.runtimeUsdzSha256,
                actual: runtimeHash
            ))
        }
        let runtimeByteCount: Int
        do {
            let values = try runtimeUsdzURL.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize else {
                return .failure(.unreadableResource(ReplayAthleteResource.nativeUsdz.rawValue))
            }
            runtimeByteCount = size
        } catch {
            return .failure(.unreadableResource(ReplayAthleteResource.nativeUsdz.rawValue))
        }
        guard runtimeByteCount == nativeManifest.runtimeUsdzByteCount else {
            return .failure(.byteCountMismatch(
                resource: "athlete.native-usdz",
                expected: nativeManifest.runtimeUsdzByteCount,
                actual: runtimeByteCount
            ))
        }

        let motionManifest: ReplayAthleteMotionTable.Manifest
        switch ReplayAthleteCatalog.parseMotionManifest(data: motionManifestData) {
        case .success(let parsed): motionManifest = parsed
        case .failure(let failure): return .failure(failure)
        }
        if let failure = ReplayAthleteCatalog.validateMotionManifest(
            motionManifest,
            source: manifest,
            binData: motionBinData
        ).failures.first {
            return .failure(failure)
        }
        let motionTable: ReplayAthleteMotionTable
        do {
            motionTable = try ReplayAthleteMotionTable(
                manifest: motionManifest,
                binData: motionBinData
            )
        } catch let error as ReplayAthleteMotionTable.LoadError {
            return .failure(.motionTableLoad(error))
        } catch {
            return .failure(.invalidMotionManifest("unrecognized table load error"))
        }
        let supportedSports = Set(Sport.allCases)
        guard motionTable.boneNames == contract.semanticBoneNames,
              motionTable.sourceCommit == manifest.pinnedCommit,
              Set(motionTable.sports) == supportedSports,
              Set(motionTable.clips.keys) == supportedSports else {
            return .failure(.invalidMotionManifest("motion table"))
        }
        for sport in [Sport.rower, .skierg, .bike] {
            guard let tableClip = motionTable.clips[sport],
                  let contractClip = contract.clip(for: sport),
                  tableClip.clipName == contractClip.name,
                  abs(tableClip.driveEnd - contractClip.driveEnd) < 1e-9 else {
                return .failure(.invalidMotionManifest("\(sport.rawValue) clip"))
            }
        }

        return .success(ReplayAthletePreflight(
            runtimeUsdzURL: runtimeUsdzURL,
            contract: contract,
            sourceManifest: manifest,
            nativeManifest: nativeManifest,
            motionTable: motionTable
        ))
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
    private let preflightObserver: (@Sendable (_ ranOnMainThread: Bool) -> Void)?
    private var template: ReplayAthleteTemplate?
    private var loadFailed = false
    private var inFlight: Task<ReplayAthleteTemplate?, Never>?
    private(set) var lastFailure: ReplayAthleteValidationFailure?

    init(
        source: any ReplayAthleteResourceSource,
        failureReporter: ((ReplayAthleteValidationFailure) -> Void)? = nil,
        entityLoader: ((URL) async throws -> Entity)? = nil,
        preflightObserver: (@Sendable (_ ranOnMainThread: Bool) -> Void)? = nil
    ) {
        self.source = source
        self.entityLoader = entityLoader ?? { try await Entity(contentsOf: $0) }
        self.preflightObserver = preflightObserver
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
        let observer = preflightObserver
        let preflightResult = await Task.detached(priority: .userInitiated) {
            observer?(ReplayAthletePreflightLoader.isMainThread())
            return ReplayAthletePreflightLoader.load(urls: urls)
        }.value
        let preflight: ReplayAthletePreflight
        switch preflightResult {
        case .success(let result): preflight = result
        case .failure(let failure): return reject(failure)
        }

        let root: Entity
        do {
            root = try await entityLoader(preflight.runtimeUsdzURL)
        } catch {
            return reject(.unreadableResource("athlete.native-usdz.runtime"))
        }
        let template: ReplayAthleteTemplate
        do {
            template = try ReplayAthleteTemplate(
                root: root,
                contract: preflight.contract,
                sourceManifest: preflight.sourceManifest,
                nativeManifest: preflight.nativeManifest,
                motionTable: preflight.motionTable
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
        case .surfaceCountMismatch: "surface-count-mismatch"
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
             .jointCountMismatch(let actual, let expected),
             .surfaceCountMismatch(let actual, let expected):
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
