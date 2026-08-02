import Foundation
import RealityKit
import RowPlayCore

/// Loads and validates the bundled production athlete from the
/// `ReplayReference` bundle: contract, source manifest, native USDZ, and the
/// sampled motion table.
///
/// Failure is atomic — a package that fails any gate yields no template, and
/// the failure is cached so scene rebuilds remain deterministic and never
/// retry a broken package on every SwiftUI update.
@MainActor
final class ReplayAthleteLibrary {
    static let shared = ReplayAthleteLibrary()

    private var template: ReplayAthleteTemplate?
    private var loadFailed = false
    private var inFlight: Task<ReplayAthleteTemplate?, Never>?

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
        inFlight?.cancel()
        inFlight = nil
    }

    private func loadTemplate() async -> ReplayAthleteTemplate? {
        if let template {
            return template
        }
        guard !loadFailed else { return nil }

        guard let contractURL = bundledURL(
            name: ReplayAthleteCatalog.contractResourceName,
            extension: ReplayAthleteCatalog.contractExtension,
            subdirectory: ReplayAthleteCatalog.athleteSubdirectory
        ),
        let sourceURL = bundledURL(
            name: ReplayAthleteCatalog.sourceManifestResourceName,
            extension: ReplayAthleteCatalog.sourceManifestExtension,
            subdirectory: ReplayAthleteCatalog.athleteSubdirectory
        ),
        let usdzURL = bundledURL(
            name: ReplayAthleteCatalog.usdzResourceName,
            extension: ReplayAthleteCatalog.usdzExtension,
            subdirectory: ReplayAthleteCatalog.athleteSubdirectory
        ),
        let motionManifestURL = bundledURL(
            name: ReplayAthleteCatalog.motionManifestResourceName,
            extension: ReplayAthleteCatalog.motionManifestExtension,
            subdirectory: ReplayAthleteCatalog.motionSubdirectory
        ),
        let motionBinURL = bundledURL(
            name: ReplayAthleteCatalog.motionBinResourceName,
            extension: ReplayAthleteCatalog.motionBinExtension,
            subdirectory: ReplayAthleteCatalog.motionSubdirectory
        ) else {
            loadFailed = true
            return nil
        }

        guard let contractData = try? Data(contentsOf: contractURL),
              let sourceData = try? Data(contentsOf: sourceURL),
              let usdzData = try? Data(contentsOf: usdzURL),
              let motionManifestData = try? Data(contentsOf: motionManifestURL),
              let motionBinData = try? Data(contentsOf: motionBinURL) else {
            loadFailed = true
            return nil
        }

        guard case .success(let manifest) = ReplayAthleteCatalog.parseSourceManifest(data: sourceData),
              ReplayAthleteCatalog.validateSourceManifest(manifest).isValid else {
            loadFailed = true
            return nil
        }

        let contractHash = ReplayAthleteCatalog.sha256Hex(of: contractData)
        let usdzHash = ReplayAthleteCatalog.sha256Hex(of: usdzData)
        guard contractHash == manifest.contractSha256,
              usdzHash == manifest.usdzSha256,
              case .success(let contract) = ReplayAthleteCatalog.parseContract(data: contractData),
              ReplayAthleteCatalog.validateContract(contract, manifest: manifest).isValid else {
            loadFailed = true
            return nil
        }

        // The motion table must come from the same pinned tree and match the
        // contract's semantic hierarchy exactly.
        guard let motionTable = try? ReplayAthleteMotionTable(
            manifestData: motionManifestData,
            binData: motionBinData
        ),
        motionTable.boneNames == contract.semanticBoneNames,
        motionTable.sourceCommit == manifest.pinnedCommit,
        motionTable.clips.count == 3 else {
            loadFailed = true
            return nil
        }
        for sport in [Sport.rower, .skierg, .bike] {
            guard let tableClip = motionTable.clips[sport],
                  let contractClip = contract.clip(for: sport),
                  tableClip.clipName == contractClip.name,
                  abs(tableClip.driveEnd - contractClip.driveEnd) < 1e-9 else {
                loadFailed = true
                return nil
            }
        }

        guard let root = try? await Entity(contentsOf: usdzURL),
              let template = ReplayAthleteTemplate(
                root: root,
                contract: contract,
                sourceManifest: manifest,
                motionTable: motionTable
              ) else {
            loadFailed = true
            return nil
        }

        self.template = template
        return template
    }

    private func bundledURL(name: String, extension ext: String, subdirectory: String) -> URL? {
        let bundle = Bundle.module
        return bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? bundle.url(forResource: name, withExtension: ext)
    }
}
