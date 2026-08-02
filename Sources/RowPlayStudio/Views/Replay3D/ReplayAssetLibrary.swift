import CryptoKit
import Foundation
import RealityKit
import RowPlayCore

/// Resolves an equipment package resource without coupling the library to a
/// filesystem location.  Production uses `Bundle.module`; tests can inject a
/// missing or malformed source to prove the atomic fallback contract.
@MainActor
protocol ReplayAssetResourceSource: AnyObject {
    func packageURL(for resource: ReplayEquipmentPackageResource) -> URL?
    func contractURL(for resource: ReplayEquipmentPackageResource) -> URL?
    func manifestURL() -> URL?
}

@MainActor
private final class ReplayModuleAssetResourceSource: ReplayAssetResourceSource {
    func packageURL(for resource: ReplayEquipmentPackageResource) -> URL? {
        ReplayAssetLibrary.bundledURL(
            name: resource.packageName,
            extension: resource.packageExtension,
            subdirectory: resource.subdirectory
        )
    }

    func contractURL(for resource: ReplayEquipmentPackageResource) -> URL? {
        ReplayAssetLibrary.bundledURL(
            name: resource.contractName,
            extension: resource.contractExtension,
            subdirectory: resource.subdirectory
        )
    }

    func manifestURL() -> URL? {
        ReplayAssetLibrary.bundledURL(
            name: ReplayAssetCatalog.equipmentManifestName,
            extension: ReplayAssetCatalog.equipmentManifestExtension,
            subdirectory: ReplayAssetCatalog.equipmentSubdirectory
        )
    }
}

/// A complete validated sport-specific asset set: the converted authored
/// equipment package plus the production athlete template.  Both must
/// validate together — a missing athlete rejects the whole bundled set so
/// scenes never mix sources.  Premium environments are built natively by
/// `ReplayEnvironmentBuilder` and are not part of this set.
@MainActor
final class ReplayBundledAssetSet {
    let sport: Sport
    let rigVisualProvider: ReplayBundledRigVisualProvider
    let athleteTemplate: ReplayAthleteTemplate

    init?(
        sport: Sport,
        equipmentRoot: Entity,
        equipmentContract: ReplayEquipmentPackageContract,
        athleteTemplate: ReplayAthleteTemplate
    ) {
        guard equipmentContract.sport == sport,
              let provider = ReplayBundledRigVisualProvider(
                root: equipmentRoot,
                contract: equipmentContract
              ) else {
            return nil
        }
        self.sport = sport
        self.rigVisualProvider = provider
        self.athleteTemplate = athleteTemplate
    }

    func makeAthleteInstance(
        sport: Sport,
        name: String,
        isRival: Bool
    ) -> ReplayAthleteInstance? {
        athleteTemplate.makeInstance(sport: sport, name: name, isRival: isRival)
    }
}

/// Small RealityKit-side geometry predicate shared by the template and rig
/// validators.  It intentionally runs only while loading a scene graph, never
/// from the per-frame update path.
@MainActor
enum ReplayAssetGeometry {
    static func hasModel(in entity: Entity) -> Bool {
        if entity.components[ModelComponent.self] != nil {
            return true
        }
        return entity.children.contains { hasModel(in: $0) }
    }
}

/// Loads and validates the converted equipment packages from `Bundle.module`.
///
/// A sport is cached only after its package hash-validates against the
/// equipment manifest, its sidecar contract validates, and the production
/// athlete loads.  Failed loads are cached too: replay rendering must remain
/// deterministic and use the complete procedural fallback instead of
/// repeatedly retrying a broken resource on every SwiftUI update.
@MainActor
final class ReplayAssetLibrary {
    static let shared = ReplayAssetLibrary(source: ReplayModuleAssetResourceSource())

    private let source: any ReplayAssetResourceSource
    private var loadedSets: [Sport: ReplayBundledAssetSet] = [:]
    private var failedSports = Set<Sport>()
    private var inFlightLoads: [Sport: Task<ReplayBundledAssetSet?, Never>] = [:]
    private var manifestPackages: [Sport: (sha256: String, contractSha256: String)]?
    private var manifestLoadFailed = false

    init(source: any ReplayAssetResourceSource) {
        self.source = source
    }

    func bundledAssetSet(for sport: Sport) async -> ReplayBundledAssetSet? {
        if let cached = loadedSets[sport] {
            return cached
        }
        guard !failedSports.contains(sport) else { return nil }

        if let inFlight = inFlightLoads[sport] {
            return await inFlight.value
        }

        let load: Task<ReplayBundledAssetSet?, Never> = Task { @MainActor [weak self] () -> ReplayBundledAssetSet? in
            guard let self else { return nil }
            return await self.loadAssetSet(for: sport)
        }
        inFlightLoads[sport] = load
        let result = await load.value
        inFlightLoads[sport] = nil
        return result
    }

    private func loadManifest() -> [Sport: (sha256: String, contractSha256: String)]? {
        if let manifestPackages { return manifestPackages }
        guard !manifestLoadFailed else { return nil }
        guard let url = source.manifestURL(),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = root["packages"] as? [[String: Any]] else {
            manifestLoadFailed = true
            return nil
        }
        var bySport: [Sport: (String, String)] = [:]
        for entry in packages {
            guard let slug = entry["sport"] as? String,
                  let sha = entry["sha256"] as? String,
                  let contractSha = entry["contractSha256"] as? String else {
                manifestLoadFailed = true
                return nil
            }
            let sport: Sport?
            switch slug {
            case "row": sport = .rower
            case "ski": sport = .skierg
            case "bike": sport = .bike
            default: sport = nil
            }
            guard let sport else {
                manifestLoadFailed = true
                return nil
            }
            bySport[sport] = (sha, contractSha)
        }
        manifestPackages = bySport
        return bySport
    }

    private func loadAssetSet(for sport: Sport) async -> ReplayBundledAssetSet? {
        if let cached = loadedSets[sport] {
            return cached
        }
        guard !failedSports.contains(sport) else { return nil }

        let resource = ReplayEquipmentPackageResource(sport: sport)
        guard let manifest = loadManifest(),
              let expected = manifest[sport],
              let packageURL = source.packageURL(for: resource),
              let contractURL = source.contractURL(for: resource),
              let packageData = try? Data(contentsOf: packageURL),
              let contractData = try? Data(contentsOf: contractURL) else {
            failedSports.insert(sport)
            return nil
        }

        guard Self.sha256Hex(of: packageData) == expected.sha256,
              Self.sha256Hex(of: contractData) == expected.contractSha256,
              let contract = ReplayAssetCatalog.parsePackageContract(data: contractData, sport: sport),
              ReplayAssetCatalog.validatePackageContract(contract) else {
            failedSports.insert(sport)
            return nil
        }

        guard let athleteTemplate = await ReplayAthleteLibrary.shared.athleteTemplate(),
              let equipmentRoot = try? await Entity(contentsOf: packageURL),
              let set = ReplayBundledAssetSet(
                sport: sport,
                equipmentRoot: equipmentRoot,
                equipmentContract: contract,
                athleteTemplate: athleteTemplate
              ) else {
            failedSports.insert(sport)
            return nil
        }

        loadedSets[sport] = set
        return set
    }

    /// Test-only cache reset.  It is intentionally internal so production
    /// code never treats asset loading as an animation or per-frame
    /// operation.
    func resetCacheForTesting() {
        loadedSets.removeAll()
        failedSports.removeAll()
        manifestPackages = nil
        manifestLoadFailed = false
        for load in inFlightLoads.values {
            load.cancel()
        }
        inFlightLoads.removeAll()
    }

    static func bundledURL(name: String, extension ext: String, subdirectory: String) -> URL? {
        let bundle = Bundle.module
        return bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? bundle.url(forResource: name, withExtension: ext)
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
