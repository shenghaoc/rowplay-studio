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
    ///   - visualProvider: A complete bundled visual provider, or `nil` for the
    ///     existing procedural mesh path.
    /// - Returns: A `ReplaySportRig` that can apply poses.
    static func build(
        sport: Sport,
        into parent: ModelEntity,
        accent: Color,
        opacity: Float = 1.0,
        visualProvider: (any ReplayRigVisualProvider)? = nil
    ) -> ReplaySportRig {
        let resolvedVisualProvider: (any ReplayRigVisualProvider)?
        if let visualProvider {
            // Bundled accent slots are recoloured on an independent clone. The
            // procedural provider remains unchanged because it already creates
            // its materials using this same `accent` value.
            resolvedVisualProvider = ReplayAccentRigVisualProvider(
                base: visualProvider,
                accent: NSColor(accent)
            )
        } else {
            resolvedVisualProvider = nil
        }

        switch sport {
        case .rower:
            let rig = ReplayRowerRig()
            rig.build(into: parent, accent: accent, opacity: opacity, visualProvider: resolvedVisualProvider)
            return rig
        case .skierg:
            let rig = ReplaySkiErgRig()
            rig.build(into: parent, accent: accent, opacity: opacity, visualProvider: resolvedVisualProvider)
            return rig
        case .bike:
            let rig = ReplayBikeErgRig()
            rig.build(into: parent, accent: accent, opacity: opacity, visualProvider: resolvedVisualProvider)
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
    /// Recursively apply opacity to every built-in material type used by the
    /// procedural rig and generated USDA assets. Each live/ghost provider clone
    /// has independent materials, so this never mutates a cached template.
    static func apply(to entity: Entity, opacity: Float) {
        // USDA loading produces generic `Entity` values with a ModelComponent,
        // whereas the procedural path usually produces `ModelEntity`. Replacing
        // the component works for both representations.
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { mat in
                if var sm = mat as? SimpleMaterial {
                    sm.color.tint = sm.color.tint.withAlphaComponent(CGFloat(opacity))
                    return sm
                }
                if var pbr = mat as? PhysicallyBasedMaterial {
                    pbr.baseColor.tint = pbr.baseColor.tint.withAlphaComponent(CGFloat(opacity))
                    return pbr
                }
                if var unlit = mat as? UnlitMaterial {
                    unlit.color.tint = unlit.color.tint.withAlphaComponent(CGFloat(opacity))
                    return unlit
                }
                return mat
            }
            entity.components.set(model)
        }
        for child in entity.children {
            apply(to: child, opacity: opacity)
        }
    }
}
