import RealityKit

/// The complete low-quality and load-failure visual source.
///
/// Returning no template lets the articulated rig keep attaching its existing
/// deterministic `ReplayMeshFactory` geometry at every pivot.
@MainActor
final class ReplayProceduralRigVisualProvider: ReplayRigVisualProvider {
    static let shared = ReplayProceduralRigVisualProvider()

    let usesBundledAssets = false

    private init() {}

    func cloneVisual(named name: String) -> Entity? {
        nil
    }
}
