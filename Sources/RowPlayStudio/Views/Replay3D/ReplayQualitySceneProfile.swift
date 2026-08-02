import Foundation
import RowPlayCore

/// Per-tier scene construction budget for the native premium 3D environments.
///
/// Direct port of the web renderer's `QUALITY` table
/// (`src/lib/replay/renderer3d.ts`, pinned RowPlay commit `4d96480e`). Every
/// value is copied verbatim so the native venues gate features at exactly the
/// same tiers as the web reference. Web-only display fields (`dprCap`,
/// `antialias`, `displacement`) are intentionally not carried over: RealityKit
/// owns backing-store scale and MSAA itself, and the native venue ground is a
/// static plane rather than a displaced height field.
struct ReplayQualitySceneProfile: Equatable, Sendable {
    /// The tier this profile was derived from.
    let quality: ReplayRenderQuality

    /// Density of optional venue dressing (web `environmentDetail`, 0...3).
    /// The authored skyline and landmark silhouette remain at every tier.
    let environmentDetail: Int

    /// Segments used for lane rings and radial arc tessellation.
    let laneSegments: Int

    /// Plane segments per side for the terrain receiver (1 = flat).
    let groundSegments: Int

    /// Whether the key light casts shadows (High and Ultra only).
    let shadowsEnabled: Bool

    /// Web shadow map resolution for the tier (0 when shadows are off).
    let shadowMapSize: Int

    /// Number of wake segments trailing each participant (0 = no wake).
    let wakeSegments: Int

    /// Buoy count per lane ring for the regatta basin.
    let buoysPerRing: Int

    /// Number of buoy rings on the water (always two in the reference).
    let buoyRings: Int

    /// Whether catch spray is simulated at this tier.
    let sprayEnabled: Bool

    /// Catch spray particle pool capacity.
    let sprayParticles: Int

    /// Droplets emitted per catch.
    let sprayPerCatch: Int

    /// Procedural athlete body resolution: limb rings, caps, and hands.
    let bodySegments: Int

    // MARK: - Authored tiers (web QUALITY table)

    static let low = ReplayQualitySceneProfile(
        quality: .low,
        environmentDetail: 0,
        laneSegments: 48,
        groundSegments: 1,
        shadowsEnabled: false,
        shadowMapSize: 0,
        wakeSegments: 0,
        buoysPerRing: 12,
        buoyRings: 2,
        sprayEnabled: false,
        sprayParticles: 0,
        sprayPerCatch: 0,
        bodySegments: 10
    )

    static let medium = ReplayQualitySceneProfile(
        quality: .medium,
        environmentDetail: 1,
        laneSegments: 80,
        groundSegments: 20,
        shadowsEnabled: false,
        shadowMapSize: 0,
        wakeSegments: 20,
        buoysPerRing: 18,
        buoyRings: 2,
        sprayEnabled: true,
        sprayParticles: 64,
        sprayPerCatch: 7,
        bodySegments: 14
    )

    static let high = ReplayQualitySceneProfile(
        quality: .high,
        environmentDetail: 2,
        laneSegments: 112,
        groundSegments: 32,
        shadowsEnabled: true,
        shadowMapSize: 1024,
        wakeSegments: 32,
        buoysPerRing: 22,
        buoyRings: 2,
        sprayEnabled: true,
        sprayParticles: 80,
        sprayPerCatch: 8,
        bodySegments: 18
    )

    static let ultra = ReplayQualitySceneProfile(
        quality: .ultra,
        environmentDetail: 3,
        laneSegments: 160,
        groundSegments: 64,
        shadowsEnabled: true,
        shadowMapSize: 2048,
        wakeSegments: 52,
        buoysPerRing: 28,
        buoyRings: 2,
        sprayEnabled: true,
        sprayParticles: 112,
        sprayPerCatch: 10,
        bodySegments: 24
    )

    /// The scene profile for a user- or degradation-selected render quality.
    static func profile(for quality: ReplayRenderQuality) -> ReplayQualitySceneProfile {
        switch quality {
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .ultra: .ultra
        }
    }
}
