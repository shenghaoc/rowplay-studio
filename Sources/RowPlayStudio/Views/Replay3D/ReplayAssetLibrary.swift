import Foundation
import RealityKit
import RowPlayCore

/// Resolves equipment resources without coupling validation to Bundle.module.
@MainActor
protocol ReplayAssetResourceSource: AnyObject {
    func packageURL(for resource: ReplayEquipmentPackageResource) -> URL?
    func contractURL(for resource: ReplayEquipmentPackageResource) -> URL?
    func manifestURL() -> URL?
}

@MainActor
private final class ReplayModuleAssetResourceSource: ReplayAssetResourceSource {
    func packageURL(for resource: ReplayEquipmentPackageResource) -> URL? {
        ReplayBundledResourceSupport.bundledURL(
            name: resource.packageName,
            extension: resource.packageExtension,
            subdirectory: resource.subdirectory
        )
    }

    func contractURL(for resource: ReplayEquipmentPackageResource) -> URL? {
        ReplayBundledResourceSupport.bundledURL(
            name: resource.contractName,
            extension: resource.contractExtension,
            subdirectory: resource.subdirectory
        )
    }

    func manifestURL() -> URL? {
        ReplayBundledResourceSupport.bundledURL(
            name: ReplayAssetCatalog.equipmentManifestName,
            extension: ReplayAssetCatalog.equipmentManifestExtension,
            subdirectory: ReplayAssetCatalog.equipmentSubdirectory
        )
    }
}

/// A complete validated equipment package for one sport.
///
/// This layer deliberately does not load or require the athlete. The later
/// athlete layer combines independently validated equipment and athlete
/// components at scene construction, preserving all-or-nothing selection.
@MainActor
final class ReplayBundledEquipmentSet {
    let sport: Sport
    let rigVisualProvider: ReplayBundledRigVisualProvider

    init(
        sport: Sport,
        rigVisualProvider: ReplayBundledRigVisualProvider
    ) {
        self.sport = sport
        self.rigVisualProvider = rigVisualProvider
    }
}

/// Small RealityKit-side geometry predicate used only while loading assets.
@MainActor
enum ReplayAssetGeometry {
    static func hasModel(in entity: Entity) -> Bool {
        if entity.components[ModelComponent.self] != nil {
            return true
        }
        return entity.children.contains { hasModel(in: $0) }
    }
}

enum ReplayAssetLoadFailure: Error, Equatable, Sendable {
    case manifestInvalid
    case packageMissing
    case contractMissing
    case packageUnreadable
    case contractUnreadable
    case packageHashMismatch
    case contractHashMismatch
    case contractInvalid(ReplayEquipmentContractFailure)
    case packageLoadFailed
    case providerInvalid(ReplayBundledRigVisualProviderFailure)

    var diagnosticCode: String {
        switch self {
        case .manifestInvalid: "manifest-invalid"
        case .packageMissing: "package-missing"
        case .contractMissing: "contract-missing"
        case .packageUnreadable: "package-unreadable"
        case .contractUnreadable: "contract-unreadable"
        case .packageHashMismatch: "package-hash-mismatch"
        case .contractHashMismatch: "contract-hash-mismatch"
        case .contractInvalid(let failure): "contract-\(failure.diagnosticCode)"
        case .packageLoadFailed: "package-load-failed"
        case .providerInvalid(let failure): "provider-\(failure.diagnosticCode)"
        }
    }
}

/// Immutable manifest entry used by the portable equipment preflight.
///
/// Keeping this value `Sendable` lets the library resolve bundle URLs on the
/// main actor, then move all file reads, hashing, JSON parsing, and contract
/// validation to a detached task before RealityKit touches the package.
struct ReplayEquipmentManifestEntry: Equatable, Sendable {
    let sha256: String
    let contractSha256: String
}

/// Portable, RealityKit-free validation for bundled equipment resources.
///
/// These synchronous functions intentionally have no actor annotation. The
/// main-actor library invokes them only from detached tasks so cold package
/// verification cannot stall SwiftUI while it reads and hashes bundle files.
enum ReplayEquipmentPortablePreflight {
    static func loadManifest(
        contentsOf url: URL
    ) -> Result<[Sport: ReplayEquipmentManifestEntry], ReplayAssetLoadFailure> {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = root["packages"] as? [[String: Any]] else {
            return .failure(.manifestInvalid)
        }

        var bySport: [Sport: ReplayEquipmentManifestEntry] = [:]
        for entry in packages {
            guard let slug = entry["sport"] as? String,
                  let sha256 = entry["sha256"] as? String,
                  let contractSha256 = entry["contractSha256"] as? String,
                  let sport = sport(slug: slug),
                  bySport[sport] == nil else {
                return .failure(.manifestInvalid)
            }
            bySport[sport] = ReplayEquipmentManifestEntry(
                sha256: sha256,
                contractSha256: contractSha256
            )
        }
        guard Set(bySport.keys) == Set(ReplayAssetCatalog.supportedSports) else {
            return .failure(.manifestInvalid)
        }
        return .success(bySport)
    }

    static func validatePackage(
        packageURL: URL,
        contractURL: URL,
        expected: ReplayEquipmentManifestEntry,
        sport: Sport
    ) -> Result<ReplayEquipmentPackageContract, ReplayAssetLoadFailure> {
        let packageHash: String
        do {
            packageHash = try ReplayBundledResourceSupport.sha256Hex(contentsOf: packageURL)
        } catch {
            return .failure(.packageUnreadable)
        }
        guard let contractData = try? Data(contentsOf: contractURL) else {
            return .failure(.contractUnreadable)
        }
        guard packageHash == expected.sha256 else {
            return .failure(.packageHashMismatch)
        }
        guard ReplayBundledResourceSupport.sha256Hex(of: contractData)
            == expected.contractSha256 else {
            return .failure(.contractHashMismatch)
        }

        let contract: ReplayEquipmentPackageContract
        switch ReplayAssetCatalog.parsePackageContract(data: contractData, sport: sport) {
        case .success(let parsed):
            contract = parsed
        case .failure(let failure):
            return .failure(.contractInvalid(failure))
        }
        if case .failure(let failure) = ReplayAssetCatalog.validatePackageContract(contract) {
            return .failure(.contractInvalid(failure))
        }
        return .success(contract)
    }

    private static func sport(slug: String) -> Sport? {
        switch slug {
        case "row": .rower
        case "ski": .skierg
        case "bike": .bike
        default: nil
        }
    }
}

/// Loads, hash-checks, contract-checks, and caches per-sport equipment.
/// Failures are cached so a broken package selects one coherent procedural
/// fallback instead of being retried during render updates.
@MainActor
final class ReplayAssetLibrary {
    static let shared = ReplayAssetLibrary(source: ReplayModuleAssetResourceSource())
    private static let logger = PrivacySafeLogger(category: "replay-assets")

    private let source: any ReplayAssetResourceSource
    private let failureReporter: (Sport, ReplayAssetLoadFailure) -> Void
    private var loadedSets: [Sport: ReplayBundledEquipmentSet] = [:]
    private var failedSports = Set<Sport>()
    private var inFlightLoads: [Sport: Task<ReplayBundledEquipmentSet?, Never>] = [:]
    private var manifestPackages: [Sport: ReplayEquipmentManifestEntry]?
    private var manifestLoadTask: Task<
        Result<[Sport: ReplayEquipmentManifestEntry], ReplayAssetLoadFailure>,
        Never
    >?
    private var manifestLoadFailed = false
    private(set) var lastFailures: [Sport: ReplayAssetLoadFailure] = [:]

    init(
        source: any ReplayAssetResourceSource,
        failureReporter: ((Sport, ReplayAssetLoadFailure) -> Void)? = nil
    ) {
        self.source = source
        self.failureReporter = failureReporter ?? { sport, failure in
            ReplayAssetLibrary.logger.warn(
                "Replay equipment package rejected",
                sport.rawValue,
                failure.diagnosticCode
            )
        }
    }

    func bundledEquipmentSet(for sport: Sport) async -> ReplayBundledEquipmentSet? {
        if let cached = loadedSets[sport] { return cached }
        guard !failedSports.contains(sport) else { return nil }
        if let inFlight = inFlightLoads[sport] {
            return await inFlight.value
        }
        let task: Task<ReplayBundledEquipmentSet?, Never> = Task {
            @MainActor [weak self] () -> ReplayBundledEquipmentSet? in
            guard let self else { return nil }
            return await self.loadEquipmentSet(for: sport)
        }
        inFlightLoads[sport] = task
        let result = await task.value
        inFlightLoads[sport] = nil
        return result
    }

    private func loadEquipmentSet(for sport: Sport) async -> ReplayBundledEquipmentSet? {
        if let cached = loadedSets[sport] { return cached }
        guard !failedSports.contains(sport) else { return nil }
        guard let expected = await loadManifest()?[sport] else {
            return reject(sport, because: .manifestInvalid)
        }

        let resource = ReplayEquipmentPackageResource(sport: sport)
        guard let packageURL = source.packageURL(for: resource) else {
            return reject(sport, because: .packageMissing)
        }
        guard let contractURL = source.contractURL(for: resource) else {
            return reject(sport, because: .contractMissing)
        }
        let preflightTask = Task.detached(priority: .userInitiated) {
            ReplayEquipmentPortablePreflight.validatePackage(
                packageURL: packageURL,
                contractURL: contractURL,
                expected: expected,
                sport: sport
            )
        }
        let contract: ReplayEquipmentPackageContract
        switch await preflightTask.value {
        case .success(let parsed):
            contract = parsed
        case .failure(let failure):
            return reject(sport, because: failure)
        }
        guard let root = try? await Entity(contentsOf: packageURL) else {
            return reject(sport, because: .packageLoadFailed)
        }
        let provider: ReplayBundledRigVisualProvider
        do {
            provider = try ReplayBundledRigVisualProvider(root: root, contract: contract)
        } catch let failure as ReplayBundledRigVisualProviderFailure {
            return reject(sport, because: .providerInvalid(failure))
        } catch {
            return reject(sport, because: .packageLoadFailed)
        }
        let set = ReplayBundledEquipmentSet(sport: sport, rigVisualProvider: provider)

        loadedSets[sport] = set
        return set
    }

    private func reject(
        _ sport: Sport,
        because failure: ReplayAssetLoadFailure
    ) -> ReplayBundledEquipmentSet? {
        if failedSports.insert(sport).inserted {
            lastFailures[sport] = failure
            failureReporter(sport, failure)
        }
        return nil
    }

    private func loadManifest() async -> [Sport: ReplayEquipmentManifestEntry]? {
        if let manifestPackages { return manifestPackages }
        guard !manifestLoadFailed else { return nil }
        if let manifestLoadTask {
            return manifestPackages(from: await manifestLoadTask.value)
        }
        guard let url = source.manifestURL() else {
            manifestLoadFailed = true
            return nil
        }
        let task = Task.detached(priority: .userInitiated) {
            ReplayEquipmentPortablePreflight.loadManifest(contentsOf: url)
        }
        manifestLoadTask = task
        let result = await task.value
        manifestLoadTask = nil
        return manifestPackages(from: result)
    }

    private func manifestPackages(
        from result: Result<
            [Sport: ReplayEquipmentManifestEntry],
            ReplayAssetLoadFailure
        >
    ) -> [Sport: ReplayEquipmentManifestEntry]? {
        switch result {
        case .success(let packages):
            manifestPackages = packages
            return packages
        case .failure:
            manifestLoadFailed = true
            return nil
        }
    }

    func resetCacheForTesting() {
        loadedSets.removeAll()
        failedSports.removeAll()
        for task in inFlightLoads.values {
            task.cancel()
        }
        inFlightLoads.removeAll()
        manifestLoadTask?.cancel()
        manifestLoadTask = nil
        manifestPackages = nil
        manifestLoadFailed = false
        lastFailures.removeAll()
    }
}
