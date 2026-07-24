import RealityKit

/// Attaches a cloned bundled environment to an existing replay scene.
///
/// Course markers, camera, and lights stay owned by `Replay3DSceneBuilder`.
/// The generated asset therefore cannot replace the scene's animation or
/// camera contracts, and it includes no embedded camera/light nodes.
@MainActor
enum ReplayEnvironmentAssetInstaller {
    @discardableResult
    static func install(
        assetSet: ReplayBundledAssetSet,
        into sceneRoot: Entity
    ) -> Entity {
        let environment = assetSet.cloneEnvironment()
        sceneRoot.addChild(environment)
        return environment
    }
}
