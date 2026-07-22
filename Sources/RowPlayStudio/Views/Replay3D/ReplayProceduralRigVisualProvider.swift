import RealityKit

/// Selects the complete low-quality and load-failure visual source.
///
/// Procedural geometry remains deliberately owned by the articulated rig's
/// established `ReplayMeshFactory` builders. Returning no authored template at
/// every pivot selects those builders without duplicating their geometry or
/// material construction in a second provider implementation.
@MainActor
final class ReplayProceduralRigVisualProvider: ReplayRigVisualProvider {
    static let shared = ReplayProceduralRigVisualProvider()

    let usesBundledAssets = false

    private init() {}

    func cloneVisual(named name: String) -> Entity? {
        nil
    }
}
