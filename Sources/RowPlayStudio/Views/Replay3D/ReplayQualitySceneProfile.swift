import Foundation
import RowPlayCore

/// The environment-owned subset of the web quality table.
///
/// Course tessellation, shadows, wakes, spray, and athlete geometry remain
/// owned by `ReplayRenderConfiguration`; duplicating them here would create a
/// second live budget that the environment installer never consumes.
struct ReplayQualitySceneProfile: Equatable, Sendable {
    /// Density of optional venue dressing (web `environmentDetail`, 0...3).
    let environmentDetail: Int
    /// Buoy count per lane ring in the regatta basin.
    let buoysPerRing: Int

    static let low = ReplayQualitySceneProfile(environmentDetail: 0, buoysPerRing: 12)
    static let medium = ReplayQualitySceneProfile(environmentDetail: 1, buoysPerRing: 18)
    static let high = ReplayQualitySceneProfile(environmentDetail: 2, buoysPerRing: 22)
    static let ultra = ReplayQualitySceneProfile(environmentDetail: 3, buoysPerRing: 28)

    static func profile(for quality: ReplayRenderQuality) -> ReplayQualitySceneProfile {
        switch quality {
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .ultra: .ultra
        }
    }
}
