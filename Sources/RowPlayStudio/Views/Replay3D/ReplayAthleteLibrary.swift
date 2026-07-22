import Foundation
import RealityKit
import RowPlayCore

/// Loads and validates the bundled V4 athlete from `Bundle.module`.
///
/// Failed loads are cached so scene rebuilds remain deterministic and never
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
            extension: ReplayAthleteCatalog.contractExtension
        ),
        let sourceURL = bundledURL(
            name: ReplayAthleteCatalog.sourceManifestResourceName,
            extension: ReplayAthleteCatalog.sourceManifestExtension
        ),
        let usdzURL = bundledURL(
            name: ReplayAthleteCatalog.usdzResourceName,
            extension: ReplayAthleteCatalog.usdzExtension
        ) else {
            loadFailed = true
            return nil
        }

        guard let contractData = try? Data(contentsOf: contractURL),
              let sourceData = try? Data(contentsOf: sourceURL),
              let usdzData = try? Data(contentsOf: usdzURL) else {
            loadFailed = true
            return nil
        }

        let contractHash = ReplayAthleteCatalog.sha256Hex(of: contractData)
        let usdzHash = ReplayAthleteCatalog.sha256Hex(of: usdzData)
        if contractHash != ReplayAthleteCatalog.expectedContractSHA256
            || usdzHash != ReplayAthleteCatalog.expectedUSDZSHA256 {
            loadFailed = true
            return nil
        }

        guard case .success(let contract) = ReplayAthleteCatalog.parseContract(data: contractData),
              case .success(let manifest) = ReplayAthleteCatalog.parseSourceManifest(data: sourceData),
              ReplayAthleteCatalog.validateSourceManifest(manifest).isValid,
              ReplayAthleteCatalog.validateContractHashes(contract).isValid else {
            loadFailed = true
            return nil
        }

        guard let root = try? await Entity(contentsOf: usdzURL),
              let template = ReplayAthleteTemplate(
                root: root,
                contract: contract,
                sourceManifest: manifest
              ) else {
            loadFailed = true
            return nil
        }

        self.template = template
        return template
    }

    private func bundledURL(name: String, extension ext: String) -> URL? {
        let bundle = Bundle.module
        return bundle.url(
            forResource: name,
            withExtension: ext,
            subdirectory: ReplayAthleteCatalog.resourceSubdirectory
        ) ?? bundle.url(forResource: name, withExtension: ext)
    }
}
