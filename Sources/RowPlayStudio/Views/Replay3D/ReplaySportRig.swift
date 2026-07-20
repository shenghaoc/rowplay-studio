import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// Protocol for sport-specific articulated rig.
///
/// Each rig builds its own entity hierarchy and applies sport-specific
/// poses. The rig owns both the machine geometry and the athlete body.
@MainActor
protocol ReplaySportRig: AnyObject {
    /// The root entity of the rig hierarchy.
    var root: Entity { get }
    /// Apply a sport-specific rig pose.
    func applyPose(_ pose: ReplaySportRigPose)
    /// Apply ghost translucency to all materials.
    func applyGhostTranslucency()
}

/// Default ghost translucency: recursively applies 0.45 opacity to all materials.
@MainActor
extension ReplaySportRig {
    func applyGhostTranslucency() {
        ReplaySportRigTranslucency.apply(to: root, opacity: 0.45)
    }
}

/// Factory for building sport-specific rigs.
@MainActor
enum ReplaySportRigFactory {
    /// Build a sport-specific rig into the given parent entity.
    ///
    /// - Parameters:
    ///   - sport: The workout sport.
    ///   - parent: The entity to attach the rig to.
    ///   - accent: Accent color for sport-specific elements.
    ///   - opacity: Material opacity (1.0 for live, <1 for ghost).
    ///   - meshes: Optional pre-loaded character meshes for the authored athlete.
    ///     When nil, falls back to procedural primitives.
    /// - Returns: A `ReplaySportRig` that can apply poses.
    static func build(
        sport: Sport,
        into parent: ModelEntity,
        accent: Color,
        opacity: Float = 1.0,
        meshes: [String: Entity]? = nil
    ) -> ReplaySportRig {
        switch sport {
        case .rower:
            let rig = ReplayRowerRig()
            rig.build(into: parent, accent: accent, opacity: opacity, meshes: meshes)
            return rig
        case .skierg:
            let rig = ReplaySkiErgRig()
            rig.build(into: parent, accent: accent, opacity: opacity, meshes: meshes)
            return rig
        case .bike:
            let rig = ReplayBikeErgRig()
            rig.build(into: parent, accent: accent, opacity: opacity, meshes: meshes)
            return rig
        }
    }
}

// MARK: - Shared Utilities

/// Finite guard for Studio/RealityKit boundary. Prevents NaN/Infinity from
/// reaching `simd_quatf` or entity transforms.
@MainActor
enum ReplaySportRigFiniteGuard {
    /// Returns `v` if finite, otherwise `fallback`.
    static func finite(_ v: Float, fallback: Float) -> Float {
        v.isFinite ? v : fallback
    }

    /// Returns `v` if finite, otherwise `fallback`.
    static func finite(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        (v.x.isFinite && v.y.isFinite && v.z.isFinite) ? v : fallback
    }
}

/// Shared ghost translucency application for all sport rigs.
@MainActor
enum ReplaySportRigTranslucency {
    /// Recursively apply opacity to all `SimpleMaterial` instances in the hierarchy.
    static func apply(to entity: Entity, opacity: Float) {
        if let model = entity as? ModelEntity {
            model.model?.materials = model.model?.materials.map { mat in
                if var sm = mat as? SimpleMaterial {
                    sm.color.tint = sm.color.tint.withAlphaComponent(CGFloat(opacity))
                    return sm
                }
                return mat
            } ?? []
        }
        for child in entity.children {
            apply(to: child, opacity: opacity)
        }
    }
}
