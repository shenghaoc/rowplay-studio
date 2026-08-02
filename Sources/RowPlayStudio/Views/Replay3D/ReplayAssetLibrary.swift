import CryptoKit
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

/// A complete validated equipment package for one sport.
///
/// This layer deliberately does not load or require the athlete. The later
/// athlete layer combines independently validated equipment and athlete
/// components at scene construction, preserving all-or-nothing selection.
@MainActor
final class ReplayBundledEquipmentSet {
    let sport: Sport
    let rigVisualProvider: ReplayBundledRigVisualProvider

    init?(
        sport: Sport,
        equipmentRoot: Entity,
        equipmentContract: ReplayEquipmentPackageContract
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

/// Loads, hash-checks, contract-checks, and caches per-sport equipment.
/// Failures are cached so a broken package selects one coherent procedural
/// fallback instead of being retried during render updates.
@MainActor
final class ReplayAssetLibrary {
    static let shared = ReplayAssetLibrary(source: ReplayModuleAssetResourceSource())

    private let source: any ReplayAssetResourceSource
    private var loadedSets: [Sport: ReplayBundledEquipmentSet] = [:]
    private var failedSports = Set<Sport>()
    private var manifestPackages: [Sport: (sha256: String, contractSha256: String)]?
    private var manifestLoadFailed = false

    init(source: any ReplayAssetResourceSource) {
        self.source = source
    }

    func bundledEquipmentSet(for sport: Sport) async -> ReplayBundledEquipmentSet? {
        if let cached = loadedSets[sport] { return cached }
        guard !failedSports.contains(sport) else { return nil }
        guard let expected = loadManifest()?[sport] else {
            failedSports.insert(sport)
            return nil
        }

        let resource = ReplayEquipmentPackageResource(sport: sport)
        guard let packageURL = source.packageURL(for: resource),
              let contractURL = source.contractURL(for: resource),
              let packageData = try? Data(contentsOf: packageURL),
              let contractData = try? Data(contentsOf: contractURL),
              Self.sha256Hex(of: packageData) == expected.sha256,
              Self.sha256Hex(of: contractData) == expected.contractSha256,
              let contract = ReplayAssetCatalog.parsePackageContract(
                  data: contractData,
                  sport: sport
              ),
              ReplayAssetCatalog.validatePackageContract(contract),
              let root = try? await Entity(contentsOf: packageURL),
              let set = ReplayBundledEquipmentSet(
                  sport: sport,
                  equipmentRoot: root,
                  equipmentContract: contract
              ) else {
            failedSports.insert(sport)
            return nil
        }

        loadedSets[sport] = set
        return set
    }

    private func loadManifest() -> [Sport: (sha256: String, contractSha256: String)]? {
        if let manifestPackages { return manifestPackages }
        guard !manifestLoadFailed,
              let url = source.manifestURL(),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = root["packages"] as? [[String: Any]] else {
            manifestLoadFailed = true
            return nil
        }

        var bySport: [Sport: (String, String)] = [:]
        for entry in packages {
            guard let slug = entry["sport"] as? String,
                  let sha256 = entry["sha256"] as? String,
                  let contractSha256 = entry["contractSha256"] as? String,
                  let sport = Self.sport(slug: slug),
                  bySport[sport] == nil else {
                manifestLoadFailed = true
                return nil
            }
            bySport[sport] = (sha256, contractSha256)
        }
        guard Set(bySport.keys) == Set(ReplayAssetCatalog.supportedSports) else {
            manifestLoadFailed = true
            return nil
        }
        manifestPackages = bySport
        return bySport
    }

    func resetCacheForTesting() {
        loadedSets.removeAll()
        failedSports.removeAll()
        manifestPackages = nil
        manifestLoadFailed = false
    }

    static func bundledURL(name: String, extension ext: String, subdirectory: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: ext)
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
