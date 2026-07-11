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
    func applyPose(_ pose: ReplaySportRigPose, reduceMotion: Bool)
    /// Apply ghost translucency to all materials.
    func applyGhostTranslucency()
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
    /// - Returns: A `ReplaySportRig` that can apply poses.
    static func build(
        sport: Sport,
        into parent: ModelEntity,
        accent: Color,
        opacity: Float = 1.0
    ) -> ReplaySportRig {
        switch sport {
        case .rower:
            let rig = ReplayRowerRig()
            rig.build(into: parent, accent: accent, opacity: opacity)
            return rig
        case .skierg:
            let rig = ReplaySkiErgRig()
            rig.build(into: parent, accent: accent, opacity: opacity)
            return rig
        case .bike:
            let rig = ReplayBikeErgRig()
            rig.build(into: parent, accent: accent, opacity: opacity)
            return rig
        }
    }
}
